defmodule Ollixir.Protocol do
  @moduledoc false

  alias Ollixir.{RequestError, ResponseError, SSE, Transport}

  def init(%Ollixir{} = client, _kind), do: client

  def init(opts, kind) when is_list(opts) do
    explicit_key? = Keyword.has_key?(opts, :api_key)
    {api_key, opts} = Keyword.pop(opts, :api_key)
    opts = if explicit_key?, do: Keyword.put(opts, :api_key, nil), else: opts
    client = Ollixir.init(opts)

    if is_binary(api_key) and api_key != "" do
      case kind do
        :openai -> put_header(client, "authorization", "Bearer " <> api_key)
        :anthropic -> put_header(client, "x-api-key", api_key)
      end
    else
      client
    end
  end

  def init(opts, _kind), do: Ollixir.init(opts)

  defp put_header(client, name, value) do
    req =
      %{client.req | options: Map.delete(client.req.options, :auth)}
      |> Req.Request.put_header(name, value)
      |> Req.Request.put_option(:redirect, false)

    %{client | req: req}
  end

  # Preserve provider-specific keys rather than validating them with native
  # Ollama schemas. Only the top-level keyword convenience is normalized.
  def body(params) when is_list(params) do
    if Keyword.keyword?(params), do: normalize_fields(params), else: invalid_body()
  end

  def body(params) when is_map(params) and not is_struct(params), do: normalize_fields(params)
  def body(_), do: invalid_body()

  defp normalize_fields(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn
      {key, value}, {:ok, acc} when is_atom(key) or is_binary(key) ->
        key = to_string(key)

        if Map.has_key?(acc, key) do
          {:halt, {:error, RequestError.exception("Duplicate request field #{key}")}}
        else
          {:cont, {:ok, Map.put(acc, key, value)}}
        end

      _, _ ->
        {:halt, invalid_body()}
    end)
  end

  defp invalid_body(), do: {:error, RequestError.exception("Expected a map or keyword list")}

  def require_fields(body, fields) do
    case Enum.find(fields, fn key ->
           is_nil(body[to_string(key)]) or body[to_string(key)] == ""
         end) do
      nil -> :ok
      key -> {:error, RequestError.missing_field(key)}
    end
  end

  def json(client, path, params, required, mode \\ :none) do
    with {:ok, body} <- body(params),
         :ok <- require_fields(body, required),
         {:ok, stream} <- stream_option(body, mode) do
      {body, mode} =
        case mode do
          :binary -> {Map.delete(body, "stream"), :binary}
          :none -> {Map.delete(body, "stream"), :none}
          :sse -> {wire_stream(body, stream), :sse}
        end

      opts = [json: body, retry: false]
      dispatch(client, path, opts, stream, mode)
    end
  end

  def stream_option(body, mode) do
    case Map.get(body, "stream", false) do
      false ->
        {:ok, false}

      value when mode != :none and (value == true or is_pid(value)) ->
        {:ok, value}

      _ ->
        {:error,
         RequestError.exception(
           field: :stream,
           message: "Invalid stream option for this endpoint"
         )}
    end
  end

  def wire_stream(body, stream) do
    if Map.has_key?(body, "stream"), do: Map.put(body, "stream", stream != false), else: body
  end

  def dispatch(client, path, opts, false, mode) do
    opts = if mode == :binary, do: Keyword.put(opts, :decode_body, false), else: opts
    Transport.request(client, :post, path, opts)
  end

  def dispatch(client, path, opts, stream, mode) do
    with {:ok, url} <- Transport.url(client.req, path) do
      opts =
        Keyword.merge(opts,
          url: url,
          method: :post,
          decode_body: false,
          retry: false,
          compressed: false,
          http_errors: :return
        )

      opts = Transport.secure_options(client.req, opts)
      mode = if mode == :sse, do: {:sse, terminal_event(path)}, else: mode

      work = fn dest ->
        Ollixir.StreamWorker.run(fn -> run_stream(client.req, opts, dest, mode) end)
      end

      case stream do
        true -> {:ok, Ollixir.StreamWorker.enumerable(work, client.req)}
        pid when is_pid(pid) -> {:ok, Ollixir.StreamWorker.task(work, pid, client.req)}
      end
    end
  end

  defp terminal_event("/v1/messages"), do: ["message_stop"]
  defp terminal_event("/v1/responses"), do: ["response.completed", "response.incomplete"]
  defp terminal_event("/v1/audio/" <> _), do: ["transcript.text.done"]
  defp terminal_event(_path), do: []

  defp run_stream(req, opts, dest, mode) do
    handler = fn {:data, chunk}, {request, response} ->
      response = handle_chunk(response, chunk, dest, mode)
      state = response.private[:ollixir_sse]
      action = if state && (state.terminal || state.error), do: :halt, else: :cont
      {action, {request, response}}
    end

    case Transport.request_req(req, Keyword.put(opts, :into, handler)) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        finish(response, dest, mode)

      result ->
        Transport.result(result)
    end
  end

  defp handle_chunk(%{status: status} = response, chunk, _dest, _mode)
       when status not in 200..299 do
    %{response | body: (response.body || "") <> chunk}
  end

  defp handle_chunk(response, chunk, dest, :binary) do
    Ollixir.StreamWorker.emit(dest, chunk)
    %{response | private: Map.put(response.private, :ollixir_binary_stream, true)}
  end

  defp handle_chunk(response, chunk, dest, {:sse, terminal_event}) do
    state = Map.get(response.private, :ollixir_sse, SSE.new())
    {events, state} = SSE.feed(state, chunk)

    state =
      Enum.reduce_while(events, state, fn
        :done, acc when terminal_event == [] ->
          {:halt, %{acc | terminal: true, error: nil}}

        :done, acc ->
          {:halt, %{acc | error: :unexpected_done_marker}}

        {event, data}, acc ->
          type = data["type"]

          cond do
            event in ["error", "response.failed"] or type in ["error", "response.failed"] or
                not is_nil(data["error"]) ->
              error = ResponseError.exception(status: response.status, body: data)
              {:halt, %{acc | error: error}}

            event in terminal_event or type in terminal_event ->
              Ollixir.StreamWorker.emit(dest, data)
              {:halt, %{acc | terminal: true, error: nil}}

            true ->
              Ollixir.StreamWorker.emit(dest, data)
              {:cont, acc}
          end
      end)

    %{response | private: Map.put(response.private, :ollixir_sse, state)}
  end

  defp finish(response, dest, :binary) do
    # Some Req adapters return a body without calling :into.
    if not Map.get(response.private, :ollixir_binary_stream, false) and is_binary(response.body) and
         byte_size(response.body) > 0 do
      Ollixir.StreamWorker.emit(dest, response.body)
    end

    {:ok, :done}
  end

  defp finish(response, dest, {:sse, _} = mode) do
    response =
      if not Map.has_key?(response.private, :ollixir_sse) and is_binary(response.body) do
        handle_chunk(response, response.body, dest, mode)
      else
        response
      end

    case SSE.finish(Map.get(response.private, :ollixir_sse, SSE.new())) do
      :ok ->
        {:ok, :done}

      {:error, %ResponseError{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, RequestError.exception(message: "Invalid SSE response", reason: reason)}
    end
  end
end
