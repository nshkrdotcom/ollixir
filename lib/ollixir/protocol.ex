defmodule Ollixir.Protocol do
  @moduledoc false

  alias Ollixir.{RequestError, ResponseError, SSE, Transport}

  def init(%Ollixir{} = client, _kind), do: client

  def init(opts, kind) when is_list(opts) do
    {api_key, opts} = Keyword.pop(opts, :api_key)
    client = Ollixir.init(opts)

    if is_binary(api_key) do
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
    %{client | req: Req.Request.put_header(client.req, name, value)}
  end

  # Preserve provider-specific keys rather than validating them with native
  # Ollama schemas. Only the top-level keyword convenience is normalized.
  def body(params) when is_list(params) do
    if Keyword.keyword?(params), do: body(Map.new(params)), else: invalid_body()
  end

  def body(params) when is_map(params) and not is_struct(params) do
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

  def body(_), do: invalid_body()

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

      work = fn dest -> run_stream(client.req, opts, dest, mode) end

      case stream do
        true -> {:ok, enumerable(work)}
        pid when is_pid(pid) -> {:ok, Task.async(fn -> work.(pid) end)}
      end
    end
  end

  defp enumerable(work) do
    Stream.resource(
      fn ->
        owner = self()
        {Task.async(fn -> work.(owner) end), false}
      end,
      &next/1,
      &close/1
    )
  end

  defp next({%Task{pid: pid, ref: ref} = task, false}) do
    receive do
      {^pid, {:data, data}} ->
        {[data], {task, false}}

      {^ref, {:ok, :done}} ->
        Process.demonitor(ref, [:flush])
        {:halt, {task, true}}

      {^ref, {:error, error}} ->
        Process.demonitor(ref, [:flush])
        raise error

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise RequestError.exception("Stream task stopped: #{inspect(reason)}")
    end
  end

  defp close({%Task{pid: pid} = task, finished}) do
    unless finished do
      if Process.alive?(pid), do: Task.shutdown(task, :brutal_kill)
      Process.demonitor(task.ref, [:flush])
      ref = task.ref

      receive do
        {^ref, _} -> :ok
      after
        0 -> :ok
      end
    end

    drain(pid)
  end

  defp drain(pid) do
    receive do
      {^pid, {:data, _}} -> drain(pid)
    after
      0 -> :ok
    end
  end

  defp run_stream(req, opts, dest, mode) do
    handler = fn {:data, chunk}, {request, response} ->
      response = handle_chunk(response, chunk, dest, mode)
      {:cont, {request, response}}
    end

    case Req.request(req, Keyword.put(opts, :into, handler)) do
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
    send(dest, {self(), {:data, chunk}})
    %{response | private: Map.put(response.private, :ollixir_binary_stream, true)}
  end

  defp handle_chunk(response, chunk, dest, :sse) do
    state = Map.get(response.private, :ollixir_sse, SSE.new())
    {events, state} = SSE.feed(state, chunk)

    state =
      Enum.reduce_while(events, state, fn {event, data}, acc ->
        if event == "error" or data["type"] == "error" or not is_nil(data["error"]) do
          error = ResponseError.exception(status: response.status, body: data)
          {:halt, %{acc | error: error}}
        else
          send(dest, {self(), {:data, data}})
          {:cont, acc}
        end
      end)

    %{response | private: Map.put(response.private, :ollixir_sse, state)}
  end

  defp finish(response, dest, :binary) do
    # Some Req adapters return a body without calling :into.
    if not Map.get(response.private, :ollixir_binary_stream, false) and is_binary(response.body) and
         byte_size(response.body) > 0 do
      send(dest, {self(), {:data, response.body}})
    end

    {:ok, :done}
  end

  defp finish(response, dest, :sse) do
    response =
      if not Map.has_key?(response.private, :ollixir_sse) and is_binary(response.body) do
        handle_chunk(response, response.body, dest, :sse)
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
