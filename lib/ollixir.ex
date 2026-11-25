defmodule Ollixir do
  @version Keyword.fetch!(Mix.Project.config(), :version)
  @moduledoc """
  Elixir client for the Ollama API.

  ## Quick Start

      client = Ollixir.init()
      {:ok, response} = Ollixir.chat(client,
        model: "llama3.2",
        messages: [%{role: "user", content: "Hello!"}]
      )

  ## Client Configuration

      # Default (localhost:11434)
      client = Ollixir.init()

      # Custom host
      client = Ollixir.init("http://ollama.example.com:11434")

      # With options
      client = Ollixir.init(
        base_url: "http://localhost:11434/api",
        receive_timeout: 120_000,
        headers: [{"authorization", "Bearer token"}]
      )

  ## Streaming

  Two modes are available:

  ### Enumerable Mode

      {:ok, stream} = Ollixir.chat(client, model: "llama3.2", messages: msgs, stream: true)
      Enum.each(stream, &IO.inspect/1)

  ### Process Mode (for GenServer/LiveView)

      {:ok, task} = Ollixir.chat(client, model: "llama3.2", messages: msgs, stream: self())
      # Receive messages with handle_info/2

  See the [Streaming Guide](guides/streaming.md) for details.

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}`.

      case Ollixir.chat(client, opts) do
        {:ok, response} -> handle_success(response)
        {:error, %Ollixir.ConnectionError{} = error} -> handle_connection(error)
        {:error, %Ollixir.ResponseError{status: 404}} -> handle_not_found()
        {:error, %Ollixir.ResponseError{status: status}} -> handle_error(status)
      end

  ## Links

  - [GitHub](https://github.com/nshkrdotcom/ollixir)
  - [Ollama API Docs](https://github.com/ollama/ollama/blob/main/docs/api.md)
  """
  use Ollixir.Schemas
  alias Ollixir.{Blob, ConnectionError, Image, Options, RequestError, ResponseError, Tool, Web}
  defstruct [:req]

  @typedoc "Client struct"
  @type client() :: %__MODULE__{
          req: Req.Request.t()
        }

  @permissive_map {:map, {:or, [:atom, :string]}, :any}

  schema(:chat_message,
    role: [
      type: {:in, ["system", "user", "assistant", "tool"]},
      required: true,
      doc: "The role of the message, either `system`, `user`, `assistant` or `tool`."
    ],
    content: [
      type: {:or, [:string, nil]},
      doc: "The content of the message. Optional for tool calls."
    ],
    images: [
      type: {:list, :string},
      doc: "*(optional)* List of Base64 encoded images (for multimodal models only)."
    ],
    thinking: [type: :string, doc: "Prior assistant thinking."],
    tool_call_id: [type: :string, doc: "Tool call identifier for a tool result."],
    tool_name: [
      type: :string,
      doc: "*(optional)* Tool name for tool responses."
    ],
    tool_calls: [
      type: {:list, @permissive_map},
      doc: "*(optional)* List of tools the model wants to use."
    ]
  )

  @typedoc """
  Chat message

  A chat message is a `t:map/0` with the following fields:

  #{doc(:chat_message)}
  """
  @type message() :: unquote(NimbleOptions.option_typespec(schema_def(:chat_message)))

  schema(:tool_def,
    type: [
      type: :string,
      default: "function",
      doc: "Type of tool. Defaults to `\"function\"`."
    ],
    items: [type: :any, doc: "Additional tool items, when supported by the model."],
    function: [
      type: :map,
      keys: [
        name: [
          type: :string,
          required: true,
          doc: "The name of the function to be called."
        ],
        description: [
          type: :string,
          doc: "A description of what the function does."
        ],
        parameters: [
          type: @permissive_map,
          required: true,
          doc: "The parameters the functions accepts."
        ]
      ],
      required: true
    ]
  )

  @typedoc """
  Tool definition

  A tool definition is a `t:map/0` with the following fields:

  #{doc(:tool_def)}
  """
  @type tool() :: unquote(NimbleOptions.option_typespec(schema_def(:tool_def)))

  @typedoc "Client response"
  @type response() ::
          {:ok, map() | boolean() | binary() | Enumerable.t() | Task.t()}
          | {:error, term()}

  @typep req_response() ::
           {:ok, Req.Response.t() | Task.t() | Enumerable.t()}
           | {:error, term()}

  @doc """
  Initializes a new Ollama client.

  ## Parameters

  - `opts` - Base URL, host string, `%URI{}`, `Req.Request`, or keyword options for `Req.new/1`.

  ## Environment Variables

  - `OLLAMA_HOST` - Default Ollama server URL (default: http://localhost:11434)
  - `OLLAMA_API_KEY` - Bearer token for API authentication

  ## Examples

      # Uses OLLAMA_HOST or defaults to localhost:11434
      client = Ollixir.init()

      # Explicit URL (overrides OLLAMA_HOST)
      client = Ollixir.init("http://ollama.example.com:11434")

      # Host strings without a scheme use http:// and default port 11434
      client = Ollixir.init("ollama.example.com")
      client = Ollixir.init(":11434")

      # With host option
      client = Ollixir.init(host: "ollama.example.com:11434")

      # With custom options
      client = Ollixir.init(receive_timeout: 120_000)

  ## Returns

  - `t:client/0` - Configured Ollama client

  ## See Also

  - `chat/2` - Chat API requests
  - `completion/2` - Completion API requests

  """
  @spec init(Req.url() | keyword() | Req.Request.t()) :: client()
  def init(opts \\ [])

  def init(url) when is_binary(url),
    do: struct(__MODULE__, req: init_req(base_url: url))

  def init(%URI{} = uri),
    do: init(URI.to_string(uri))

  def init(opts) when is_list(opts),
    do: struct(__MODULE__, req: init_req(opts))

  def init(%Req.Request{} = req),
    do: struct(__MODULE__, req: req)

  @spec init_req(keyword()) :: Req.Request.t()
  defp init_req(opts) do
    api_key = System.get_env("OLLAMA_API_KEY")

    base_url =
      opts
      |> Keyword.get(:base_url, Keyword.get(opts, :host, System.get_env("OLLAMA_HOST")))
      |> normalize_base_url()

    base_headers = [{"user-agent", user_agent()}]

    api_key_headers =
      if api_key do
        [{"authorization", "Bearer #{api_key}"}]
      else
        []
      end

    user_headers = Keyword.get(opts, :headers, [])

    merged_headers = merge_headers(base_headers ++ api_key_headers, user_headers)

    opts
    |> Keyword.drop([:base_url, :host, :headers])
    |> Keyword.put(:base_url, base_url)
    |> Keyword.put(:headers, merged_headers)
    |> Keyword.put_new(:receive_timeout, 60_000)
    |> Req.new()
  end

  defp user_agent do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.split("-", parts: 2)
      |> hd()

    os = user_agent_os()

    "ollixir/#{@version} (#{arch} #{os}) Elixir/#{System.version()} OTP/#{System.otp_release()}"
  end

  defp user_agent_os do
    case :os.type() do
      {:unix, :darwin} -> "darwin"
      {:unix, :linux} -> "linux"
      {:win32, _} -> "windows"
      {_, name} -> to_string(name)
    end
  end

  defp ensure_api_suffix(url) when is_binary(url) do
    trimmed = String.trim_trailing(url, "/")

    if String.ends_with?(trimmed, "/api") do
      trimmed
    else
      trimmed <> "/api"
    end
  end

  defp normalize_base_url(%URI{} = uri), do: normalize_base_url(URI.to_string(uri))
  defp normalize_base_url(nil), do: ensure_api_suffix(parse_host(nil))

  defp normalize_base_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    if trimmed == "" do
      ensure_api_suffix(parse_host(nil))
    else
      base =
        if String.contains?(trimmed, "://") do
          trimmed
        else
          trimmed
          |> String.trim_trailing("/")
          |> String.split("/", parts: 2)
          |> hd()
          |> parse_host()
        end

      ensure_api_suffix(base)
    end
  end

  defp parse_host(nil), do: "http://localhost:11434"
  defp parse_host(""), do: "http://localhost:11434"

  defp parse_host(host) when is_binary(host) do
    host = String.trim(host)
    host = String.trim_trailing(host, "/")

    cond do
      String.starts_with?(host, "http://") or String.starts_with?(host, "https://") ->
        host

      String.starts_with?(host, ":") ->
        "http://localhost:" <> String.trim_leading(host, ":")

      String.contains?(host, ":") ->
        "http://" <> host

      true ->
        "http://" <> host <> ":11434"
    end
  end

  defp merge_headers(base, override) do
    override_keys = Enum.map(override, fn {k, _} -> String.downcase(to_string(k)) end)

    base
    |> Enum.reject(fn {k, _} -> String.downcase(to_string(k)) in override_keys end)
    |> Kernel.++(override)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp pop_response_format(params) do
    {format, params} = Keyword.pop(params, :response_format)
    {resolve_response_format(format), params}
  end

  defp resolve_response_format(nil) do
    Application.get_env(:ollixir, :response_format, :map)
  end

  defp resolve_response_format(format) when format in [:map, :struct], do: format
  defp resolve_response_format(_), do: :map

  defp validate_params(params, schema) do
    case NimbleOptions.validate(params, schema) do
      {:ok, params} ->
        {:ok, params}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         RequestError.exception(
           message: Exception.message(error),
           field: error.key,
           reason: :validation_error
         )}
    end
  end

  defp validate_model_name(params) do
    model = params[:model]
    name = params[:name]

    cond do
      is_nil(model) and is_nil(name) ->
        {:error, RequestError.missing_field(:model)}

      model == "" or name == "" ->
        {:error, RequestError.exception("Model name must not be empty")}

      model && name && model != name ->
        {:error, RequestError.exception("Conflicting model and name")}

      true ->
        :ok
    end
  end

  defp normalize_debug(params) do
    case Keyword.pop(params, :debug_render_only) do
      {nil, params} ->
        {:ok, params}

      {value, params} ->
        case Keyword.fetch(params, :_debug_render_only) do
          {:ok, other} when other != value ->
            {:error, RequestError.exception("Conflicting debug_render_only values")}

          _ ->
            {:ok, Keyword.put(params, :_debug_render_only, value)}
        end
    end
  end

  defp cast_fun_for(_endpoint, :map), do: nil
  defp cast_fun_for(_endpoint, nil), do: nil
  defp cast_fun_for(:chat, :struct), do: &Ollixir.Types.ChatResponse.from_map/1
  defp cast_fun_for(:completion, :struct), do: &Ollixir.Types.GenerateResponse.from_map/1
  defp cast_fun_for(:embed, :struct), do: &Ollixir.Types.EmbedResponse.from_map/1
  defp cast_fun_for(:embeddings, :struct), do: &Ollixir.Types.EmbeddingsResponse.from_map/1
  defp cast_fun_for(:list_models, :struct), do: &Ollixir.Types.ListResponse.from_map/1
  defp cast_fun_for(:list_running, :struct), do: &Ollixir.Types.ProcessResponse.from_map/1
  defp cast_fun_for(:show_model, :struct), do: &Ollixir.Types.ShowResponse.from_map/1
  defp cast_fun_for(:show_manifests, :struct), do: &Ollixir.Types.ShowManifestsResponse.from_map/1
  defp cast_fun_for(:system_one, :struct), do: &Ollixir.Types.SystemOneResponse.from_map/1
  defp cast_fun_for(:version, :struct), do: &Ollixir.Types.VersionResponse.from_map/1
  defp cast_fun_for(:server_status, :struct), do: &Ollixir.Types.ServerStatusResponse.from_map/1
  defp cast_fun_for(:whoami, :struct), do: &Ollixir.Types.UserResponse.from_map/1

  defp cast_fun_for(:model_recommendations, :struct),
    do: &Ollixir.Types.ModelRecommendationsResponse.from_map/1

  defp cast_fun_for(:progress, :struct), do: &Ollixir.Types.ProgressResponse.from_map/1
  defp cast_fun_for(:status, :struct), do: &Ollixir.Types.StatusResponse.from_map/1
  defp cast_fun_for(_endpoint, _format), do: nil

  defp apply_cast({:ok, %Task{} = task}, _cast_fun), do: {:ok, task}

  defp apply_cast({:ok, enum}, cast_fun) when is_function(enum) do
    if is_function(cast_fun) do
      {:ok, Stream.map(enum, cast_fun)}
    else
      {:ok, enum}
    end
  end

  defp apply_cast({:ok, body}, cast_fun) when is_function(cast_fun) do
    {:ok, cast_fun.(body)}
  end

  defp apply_cast(result, _cast_fun), do: result

  defp normalize_options(opts) do
    case Keyword.get(opts, :options) do
      nil ->
        {:ok, opts}

      %Options{} = options ->
        {:ok, Keyword.put(opts, :options, Options.to_map(options))}

      map when is_map(map) ->
        {:ok, opts}

      keyword when is_list(keyword) ->
        case Options.build(keyword) do
          {:ok, options} ->
            {:ok, Keyword.put(opts, :options, Options.to_map(options))}

          {:error, reason} ->
            {:error, RequestError.exception(message: "Invalid options", reason: reason)}
        end

      other ->
        {:error,
         RequestError.invalid_type(:options, other, "map, keyword list, or Ollixir.Options")}
    end
  end

  defp normalize_tools(opts) do
    case Keyword.get(opts, :tools) do
      nil ->
        {:ok, opts}

      tools when is_list(tools) ->
        case Tool.prepare(tools) do
          {:ok, prepared} ->
            {:ok, Keyword.put(opts, :tools, prepared)}

          {:error, reason} ->
            {:error, RequestError.exception(message: "Invalid tool", reason: reason)}
        end

      other ->
        {:error, RequestError.invalid_type(:tools, other, "list")}
    end
  end

  defp normalize_images(opts) do
    case Keyword.get(opts, :images) do
      nil ->
        {:ok, opts}

      images when is_list(images) ->
        case Image.encode_all(images) do
          {:ok, encoded} ->
            {:ok, Keyword.put(opts, :images, encoded)}

          {:error, reason} ->
            {:error, RequestError.exception(message: "Image encoding failed", reason: reason)}
        end

      other ->
        {:error, RequestError.invalid_type(:images, other, "list")}
    end
  end

  defp normalize_messages_images(opts) do
    case Keyword.get(opts, :messages) do
      nil ->
        {:ok, opts}

      messages when is_list(messages) ->
        with {:ok, updated} <- encode_message_images(messages) do
          {:ok, Keyword.put(opts, :messages, updated)}
        end

      other ->
        {:error, RequestError.invalid_type(:messages, other, "list")}
    end
  end

  defp encode_message_images(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      case encode_message_images_one(message) do
        {:ok, updated} -> {:cont, {:ok, acc ++ [updated]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp encode_message_images_one(message) when is_map(message) do
    message = if is_struct(message), do: Map.from_struct(message), else: message

    message =
      Enum.reduce(
        ~w(role content thinking images tool_name tool_call_id tool_calls)a,
        message,
        fn key, acc ->
          string_key = Atom.to_string(key)

          if Map.has_key?(acc, string_key) do
            {value, acc} = Map.pop(acc, string_key)
            Map.put_new(acc, key, value)
          else
            acc
          end
        end
      )

    message =
      case message[:tool_calls] do
        calls when is_list(calls) ->
          Map.put(
            message,
            :tool_calls,
            Enum.map(calls, fn
              %Ollixir.Types.ToolCall{} = call -> call |> Map.from_struct() |> drop_nil_values()
              call -> call
            end)
          )

        _ ->
          message
      end

    {key, images} =
      cond do
        Map.has_key?(message, :images) -> {:images, Map.get(message, :images)}
        Map.has_key?(message, "images") -> {"images", Map.get(message, "images")}
        true -> {nil, nil}
      end

    cond do
      is_nil(key) ->
        {:ok, drop_nil_values(message)}

      is_nil(images) ->
        {:ok, drop_nil_values(message)}

      is_list(images) ->
        case Image.encode_all(images) do
          {:ok, encoded} ->
            {:ok, drop_nil_values(Map.put(message, key, encoded))}

          {:error, reason} ->
            {:error, RequestError.exception(message: "Image encoding failed", reason: reason)}
        end

      true ->
        {:error, RequestError.invalid_type(:images, images, "list")}
    end
  end

  defp encode_message_images_one(other), do: {:ok, other}

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  schema(:chat,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [
      type: :string,
      required: true,
      doc: "The Ollama model name."
    ],
    messages: [
      type: {:list, {:map, schema_def(:chat_message).schema}},
      required: true,
      doc: "List of messages - used to keep a chat memory."
    ],
    tools: [
      type: {:list, {:map, schema_def(:tool_def).schema}},
      doc: "Tools for the model to use if supported."
    ],
    format: [
      type: {:or, [:string, @permissive_map]},
      doc: "Set the expected format of the response (`json` or JSON schema map)."
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming)."
    ],
    think: [
      type: {:or, [:boolean, :string]},
      doc: "Enable thinking mode or specify a model-defined effort name."
    ],
    truncate: [type: :boolean, doc: "Truncate prompts that exceed context length."],
    shift: [type: :boolean, doc: "Shift context instead of failing at its limit."],
    _debug_render_only: [type: :boolean, doc: "Return rendered prompt debug information."],
    logprobs: [
      type: :boolean,
      doc: "Return log probabilities for generated tokens"
    ],
    top_logprobs: [
      type: :integer,
      doc: "Number of alternative tokens to return (0-20)"
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded."
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc:
        "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)."
    ]
  )

  @doc """
  Generates the next message in a chat using the specified model. Optionally
  streamable.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list of chat options (see below)

  ## Options

  #{doc(:chat)}

  ## Message structure

  Each message is a map with the following fields:

  #{doc(:chat_message)}

  ## Tool definitions

  #{doc(:tool_def)}

  ## Examples

      iex> messages = [
      ...>   %{role: "system", content: "You are a helpful assistant."},
      ...>   %{role: "user", content: "Why is the sky blue?"},
      ...>   %{role: "assistant", content: "Due to rayleigh scattering."},
      ...>   %{role: "user", content: "How is that different than mie scattering?"},
      ...> ]

      iex> Ollixir.chat(client, [
      ...>   model: "llama2",
      ...>   messages: messages,
      ...> ])
      {:ok, %{"message" => %{
        "role" => "assistant",
        "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
      }, ...}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollixir.chat(client, [
      ...>   model: "llama2",
      ...>   messages: messages,
      ...>   stream: true,
      ...> ])
      {:ok, Ollixir.Streaming{}}

  ## Returns

  - `{:ok, map()}` - Success with response data
  - `{:ok, Stream.t()}` - When `stream: true`
  - `{:ok, Task.t()}` - When `stream: pid`
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `completion/2` - For single-turn generation
  - `embed/2` - For embeddings
  """
  @spec chat(client(), keyword()) :: response()
  def chat(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:chat, format)

    with {:ok, params} <- normalize_debug(params),
         {:ok, params} <- normalize_options(params),
         {:ok, params} <- normalize_tools(params),
         {:ok, params} <- normalize_messages_images(params),
         {:ok, params} <- validate_params(params, schema_def(:chat)) do
      result =
        client
        |> req(:post, "/chat", json: Enum.into(params, %{}), cast: cast_fun)
        |> res()

      if params[:stream], do: result, else: apply_cast(result, cast_fun)
    end
  end

  schema(:completion,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [
      type: :string,
      required: true,
      doc: "The Ollama model name."
    ],
    prompt: [
      type: :string,
      required: true,
      doc: "Prompt to generate a response for."
    ],
    suffix: [
      type: :string,
      doc: "Text to append after generated content (for code completion)"
    ],
    images: [
      type: {:list, :string},
      doc:
        "A list of Base64 encoded images to be included with the prompt (for multimodal models only)."
    ],
    system: [
      type: :string,
      doc: "System prompt, overriding the model default."
    ],
    template: [
      type: :string,
      doc: "Prompt template, overriding the model default."
    ],
    context: [
      type: {:list, {:or, [:integer, :float]}},
      doc:
        "The context parameter returned from a previous `completion/2` call (enabling short conversational memory)."
    ],
    format: [
      type: {:or, [:string, @permissive_map]},
      doc: "Set the expected format of the response (`json` or JSON schema map)."
    ],
    raw: [
      type: :boolean,
      doc: "Set `true` if specifying a fully templated prompt. (`:template` is ingored)"
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming)."
    ],
    think: [
      type: {:or, [:boolean, :string]},
      doc: "Enable thinking mode or specify a model-defined effort name."
    ],
    truncate: [type: :boolean, doc: "Truncate prompts that exceed context length."],
    shift: [type: :boolean, doc: "Shift context instead of failing at its limit."],
    _debug_render_only: [type: :boolean, doc: "Return rendered prompt debug information."],
    logprobs: [
      type: :boolean,
      doc: "Return log probabilities for generated tokens"
    ],
    top_logprobs: [
      type: :integer,
      doc: "Number of alternative tokens to return (0-20)"
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded."
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc:
        "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)."
    ]
  )

  @doc """
  Generates a completion for the given prompt using the specified model.
  Optionally streamable.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list of completion options (see below)

  ## Options

  #{doc(:completion)}

  ## Examples

      iex> Ollixir.completion(client, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...> ])
      {:ok, %{"response": "The sky is blue because it is the color of the sky.", ...}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollixir.completion(client, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...>   stream: true,
      ...> ])
      {:ok, %Ollixir.Streaming{}}

  ## Returns

  - `{:ok, map()}` - Success with response data
  - `{:ok, Stream.t()}` - When `stream: true`
  - `{:ok, Task.t()}` - When `stream: pid`
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `chat/2` - For multi-turn conversations
  - `embed/2` - For embeddings
  """
  @spec completion(client(), keyword()) :: response()
  def completion(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:completion, format)

    with {:ok, params} <- normalize_debug(params),
         {:ok, params} <- normalize_options(params),
         {:ok, params} <- normalize_images(params),
         {:ok, params} <- validate_params(params, schema_def(:completion)) do
      result =
        client
        |> req(:post, "/generate", json: Enum.into(params, %{}), cast: cast_fun)
        |> res()

      if params[:stream], do: result, else: apply_cast(result, cast_fun)
    end
  end

  @doc """
  Alias for `completion/2` to match the Python client's `generate`.
  """
  @spec generate(client(), keyword()) :: response()
  def generate(%__MODULE__{} = client, params) when is_list(params) do
    completion(client, params)
  end

  schema(:create_model,
    model: [type: :string, doc: "Name for the new model"],
    name: [type: :string, doc: "Legacy model name"],
    modelfile: [type: :string, doc: "Modelfile contents"],
    draft_quantize: [type: :string, doc: "Draft weight quantization"],
    draft_files: [type: {:map, :string, :string}, doc: "Draft files and digests"],
    list: [type: {:list, :string}, doc: "Local tags for a manifest list"],
    remote_host: [type: :string, doc: "Upstream Ollama host"],
    renderer: [type: :string, doc: "Prompt renderer"],
    parser: [type: :string, doc: "Output parser"],
    requires: [type: :string, doc: "Minimum Ollama version"],
    capabilities: [type: {:list, :string}, doc: "Additional capabilities"],
    info: [type: @permissive_map, doc: "Additional model metadata"],
    quantization: [type: :string, doc: "Legacy quantization field"],
    from: [type: :string, doc: "Base model to create from"],
    files: [type: {:map, :string, :string}, doc: "Custom files to include"],
    adapters: [type: {:map, :string, :string}, doc: "LoRA adapter files"],
    template: [type: :string, doc: "Custom prompt template"],
    license: [type: {:or, [:string, {:list, :string}]}, doc: "License declaration"],
    system: [type: :string, doc: "System prompt"],
    parameters: [type: {:or, [:map, :keyword_list]}, doc: "Model parameters"],
    messages: [type: {:list, :map}, doc: "Sample conversation messages"],
    quantize: [type: :string, doc: "Quantization level (f16, f32, etc.)"],
    stream: [type: {:or, [:boolean, :pid]}, doc: "Enable streaming"]
  )

  @doc """
  Creates a model using the given name and model file. Optionally
  streamable.

  Any dependent blobs reference in the modelfile, such as `FROM` and `ADAPTER`
  instructions, must exist first. See `check_blob/2` and `create_blob/2`.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list of model creation options (see below)

  ## Options

  #{doc(:create_model)}

  ## Example

      iex> modelfile = "FROM llama2\\nSYSTEM \\"You are mario from Super Mario Bros.\\""
      iex> Ollixir.create_model(client, [
      ...>   name: "mario",
      ...>   modelfile: modelfile,
      ...>   stream: true,
      ...> ])
      {:ok, Ollixir.Streaming{}}

  ## Returns

  - `{:ok, map()}` - Success with response data
  - `{:ok, Stream.t()}` - When `stream: true`
  - `{:ok, Task.t()}` - When `stream: pid`
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `check_blob/2` - Verify dependent blobs
  - `create_blob/2` - Create blob dependencies
  """
  @spec create_model(client(), keyword()) :: response()
  def create_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:progress, format)

    with {:ok, params} <- normalize_messages_images(params),
         {:ok, params} <- validate_params(params, schema_def(:create_model)),
         :ok <- validate_model_name(params) do
      parameters =
        case params[:parameters] do
          list when is_list(list) -> Enum.into(list, %{})
          map -> map
        end

      body =
        params
        |> Map.new()
        |> maybe_put(:parameters, parameters)

      result =
        client
        |> req(:post, "/create", json: body, cast: cast_fun)
        |> res()

      if params[:stream], do: result, else: apply_cast(result, cast_fun)
    end
  end

  @doc """
  Alias for `create_model/2` to match the Python client's `create`.
  """
  @spec create(client(), keyword()) :: response()
  def create(%__MODULE__{} = client, params) when is_list(params) do
    create_model(client, params)
  end

  @doc """
  Lists all models that Ollama has available.

  ## Parameters

  - `client` - Ollama client from `init/1`

  ## Example

      iex> Ollixir.list_models(client)
      {:ok, %{"models" => [
        %{"name" => "codellama:13b", ...},
        %{"name" => "llama2:latest", ...},
      ]}}

  ## Returns

  - `{:ok, map()}` - Map containing available models
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `show_model/2` - Fetch model details
  - `list_running/1` - List running models
  """
  @spec list_models(client(), keyword()) :: response()
  def list_models(%__MODULE__{} = client, opts \\ []) when is_list(opts) do
    {format, _opts} = pop_response_format(opts)
    cast_fun = cast_fun_for(:list_models, format)

    client
    |> req(:get, "/tags")
    |> res()
    |> apply_cast(cast_fun)
  end

  @doc """
  Alias for `list_models/2` to match the Python client's `list`.
  """
  @spec list(client(), keyword()) :: response()
  def list(%__MODULE__{} = client, opts \\ []) when is_list(opts) do
    list_models(client, opts)
  end

  @doc """
  Lists currently running models, their memory footprint, and process details.

  ## Parameters

  - `client` - Ollama client from `init/1`

  ## Example

      iex> Ollixir.list_running(client)
      {:ok, %{"models" => [
        %{"name" => "nomic-embed-text:latest", ...},
      ]}}

  ## Returns

  - `{:ok, map()}` - Map containing running models
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `list_models/1` - List available models
  - `show_model/2` - Fetch model details
  """
  @spec list_running(client(), keyword()) :: response()
  def list_running(%__MODULE__{} = client, opts \\ []) when is_list(opts) do
    {format, _opts} = pop_response_format(opts)
    cast_fun = cast_fun_for(:list_running, format)

    client
    |> req(:get, "/ps")
    |> res()
    |> apply_cast(cast_fun)
  end

  @doc """
  Alias for `list_running/2` to match the Python client's `ps`.
  """
  @spec ps(client(), keyword()) :: response()
  def ps(%__MODULE__{} = client, opts \\ []) when is_list(opts) do
    list_running(client, opts)
  end

  schema(:load_model,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [
      type: :string,
      required: true,
      doc: "Name of the model to load."
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded."
    ]
  )

  @doc """
  Load a model into memory without generating a completion. Optionally specify
  a keep alive value (defaults to 5 minutes, set `-1` to permanently keep alive).

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:model` and optional `:keep_alive`

  ## Options

  #{doc(:load_model)}

  ## Example

      iex> Ollixir.preload(client, model: "llama3.1", timeout: 3_600_000)
      true

  ## Returns

  - `{:ok, true}` - When the model was loaded
  - `{:ok, false}` - When the model was not found
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `unload/2` - Unload a model
  - `list_running/1` - Check running models
  """
  @spec preload(client(), keyword()) :: response()
  def preload(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- validate_params(params, schema_def(:load_model)) do
      client
      |> req(:post, "/generate", json: Enum.into(params, %{}))
      |> res_status()
    end
  end

  @doc """
  Stops a running model and unloads it from memory.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:model`

  ## Options

  - `:model` (`t:String.t/0`) - Required. Name of the model to unload.

  ## Example

      iex> Ollixir.preload(client, model: "llama3.1")
      true

  ## Returns

  - `{:ok, true}` - When the model was unloaded
  - `{:ok, false}` - When the model was not found
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `preload/2` - Load a model
  - `list_running/1` - Check running models
  """
  @spec unload(client(), keyword()) :: response()
  def unload(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- validate_params(params, schema_def(:load_model)) do
      params = Keyword.put(params, :keep_alive, 0)

      client
      |> req(:post, "/generate", json: Enum.into(params, %{}))
      |> res_status()
    end
  end

  schema(:show_model,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [type: :string, doc: "Model name"],
    all_manifests: [type: :boolean, doc: "Return every runner manifest."],
    verbose: [type: :boolean, doc: "Include verbose model metadata."],
    system: [type: :string, doc: "Override system prompt."],
    template: [type: :string, doc: "Legacy template override."],
    options: [type: @permissive_map, doc: "Model options."],
    name: [
      type: :string,
      doc: "Name of the model to show."
    ]
  )

  @doc """
  Shows all information for a specific model.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:name`

  ## Options

  #{doc(:show_model)}

  ## Example

      iex> Ollixir.show_model(client, name: "llama2")
      {:ok, %{
        "details" => %{
          "families" => ["llama", "clip"],
          "family" => "llama",
          "format" => "gguf",
          "parameter_size" => "7B",
          "quantization_level" => "Q4_0"
        },
        "modelfile" => "...",
        "parameters" => "...",
        "template" => "..."
      }}

  ## Returns

  - `{:ok, map()}` - Model details
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `list_models/1` - List available models
  """
  @spec show_model(client(), keyword()) :: response()
  def show_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    endpoint = if params[:all_manifests], do: :show_manifests, else: :show_model
    cast_fun = cast_fun_for(endpoint, format)

    with {:ok, params} <- normalize_options(params),
         {:ok, params} <- validate_params(params, schema_def(:show_model)),
         :ok <- validate_model_name(params) do
      client
      |> req(:post, "/show", json: Enum.into(params, %{}))
      |> res()
      |> apply_cast(cast_fun)
    end
  end

  @doc """
  Alias for `show_model/2` to match the Python client's `show`.
  """
  @spec show(client(), keyword()) :: response()
  def show(%__MODULE__{} = client, params) when is_list(params) do
    show_model(client, params)
  end

  schema(:copy_model,
    source: [
      type: :string,
      required: true,
      doc: "Name of the model to copy from."
    ],
    destination: [
      type: :string,
      required: true,
      doc: "Name of the model to copy to."
    ]
  )

  @doc """
  Creates a model with another name from an existing model.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:source` and `:destination`

  ## Options

  #{doc(:copy_model)}

  ## Example

      iex> Ollixir.copy_model(client, [
      ...>   source: "llama2",
      ...>   destination: "llama2-backup"
      ...> ])
      {:ok, true}

  ## Returns

  - `{:ok, true}` - When the copy succeeded
  - `{:ok, false}` - When the model was not found
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `delete_model/2` - Delete a model
  - `show_model/2` - Inspect a model
  """
  @spec copy_model(client(), keyword()) :: response()
  def copy_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:status, format)

    with {:ok, params} <- validate_params(params, schema_def(:copy_model)) do
      result =
        client
        |> req(:post, "/copy", json: Enum.into(params, %{}))
        |> res_status()

      if format == :struct do
        case result do
          {:ok, true} -> apply_cast({:ok, %{"status" => "success"}}, cast_fun)
          {:ok, false} -> apply_cast({:ok, %{"status" => "error"}}, cast_fun)
          {:error, _} = error -> error
        end
      else
        result
      end
    end
  end

  @doc """
  Alias for `copy_model/2` to match the Python client's `copy`.
  """
  @spec copy(client(), keyword()) :: response()
  def copy(%__MODULE__{} = client, params) when is_list(params) do
    copy_model(client, params)
  end

  schema(:delete_model,
    model: [type: :string, doc: "Model name"],
    name: [
      type: :string,
      doc: "Name of the model to delete."
    ]
  )

  @doc """
  Deletes a model and its data.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:name`

  ## Options

  #{doc(:copy_model)}

  ## Example

      iex> Ollixir.delete_model(client, name: "llama2")
      {:ok, true}

  ## Returns

  - `{:ok, true}` - When the delete succeeded
  - `{:ok, false}` - When the model was not found
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `copy_model/2` - Copy a model
  - `show_model/2` - Inspect a model
  """
  @spec delete_model(client(), keyword()) :: response()
  def delete_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:status, format)

    with {:ok, params} <- validate_params(params, schema_def(:delete_model)),
         :ok <- validate_model_name(params) do
      result =
        client
        |> req(:delete, "/delete", json: Enum.into(params, %{}))
        |> res_status()

      if format == :struct do
        case result do
          {:ok, true} -> apply_cast({:ok, %{"status" => "success"}}, cast_fun)
          {:ok, false} -> apply_cast({:ok, %{"status" => "error"}}, cast_fun)
          {:error, _} = error -> error
        end
      else
        result
      end
    end
  end

  @doc """
  Alias for `delete_model/2` to match the Python client's `delete`.
  """
  @spec delete(client(), keyword()) :: response()
  def delete(%__MODULE__{} = client, params) when is_list(params) do
    delete_model(client, params)
  end

  schema(:pull_model,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [type: :string, doc: "Model name"],
    name: [
      type: :string,
      doc: "Name of the model to pull."
    ],
    insecure: [
      type: :boolean,
      doc: "Allow insecure (HTTP) connections."
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming)."
    ]
  )

  @doc """
  Downloads a model from the Ollama library. Optionally streamable.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:name` and optional `:stream`

  ## Options

  #{doc(:pull_model)}

  ## Example

      iex> Ollixir.pull_model(client, name: "llama2")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollixir.pull_model(client, name: "llama2", stream: true)
      {:ok, %Ollixir.Streaming{}}

  ## Returns

  - `{:ok, map()}` - Status updates or completion
  - `{:ok, Stream.t()}` - When `stream: true`
  - `{:ok, Task.t()}` - When `stream: pid`
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `push_model/2` - Upload a model
  """
  @spec pull_model(client(), keyword()) :: response()
  def pull_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:progress, format)

    with {:ok, params} <- validate_params(params, schema_def(:pull_model)),
         :ok <- validate_model_name(params) do
      result =
        client
        |> req(:post, "/pull", json: Enum.into(params, %{}), cast: cast_fun)
        |> res()

      if params[:stream], do: result, else: apply_cast(result, cast_fun)
    end
  end

  @doc """
  Alias for `pull_model/2` to match the Python client's `pull`.
  """
  @spec pull(client(), keyword()) :: response()
  def pull(%__MODULE__{} = client, params) when is_list(params) do
    pull_model(client, params)
  end

  schema(:push_model,
    model: [type: :string, doc: "Model name"],
    name: [
      type: :string,
      doc: "Name of the model to pull."
    ],
    insecure: [
      type: :boolean,
      doc: "Allow insecure (HTTP) connections."
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming)."
    ]
  )

  @doc """
  Upload a model to a model library. Requires an Ollama account and a public
  key from https://ollama.com/settings/keys. Optionally streamable.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list with `:name` and optional `:stream`

  ## Options

  #{doc(:push_model)}

  ## Example

      iex> Ollixir.push_model(client, name: "mattw/pygmalion:latest")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollixir.push_model(client, name: "mattw/pygmalion:latest", stream: true)
      {:ok, %Ollixir.Streaming{}}

  ## Returns

  - `{:ok, map()}` - Status updates or completion
  - `{:ok, Stream.t()}` - When `stream: true`
  - `{:ok, Task.t()}` - When `stream: pid`
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `pull_model/2` - Download a model
  """
  @spec push_model(client(), keyword()) :: response()
  def push_model(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:progress, format)

    with {:ok, params} <- validate_params(params, schema_def(:push_model)),
         :ok <- validate_model_name(params) do
      result =
        client
        |> req(:post, "/push", json: Enum.into(params, %{}), cast: cast_fun)
        |> res()

      if params[:stream], do: result, else: apply_cast(result, cast_fun)
    end
  end

  @doc """
  Alias for `push_model/2` to match the Python client's `push`.
  """
  @spec push(client(), keyword()) :: response()
  def push(%__MODULE__{} = client, params) when is_list(params) do
    push_model(client, params)
  end

  @doc """
  Checks a blob exists in Ollama by its digest or binary data.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `digest_or_blob` - Digest string or raw binary data

  ## Examples

      iex> Ollixir.check_blob(client, "sha256:fe938a131f40e6f6d40083c9f0f430a515233eb2edaa6d72eb85c50d64f2300e")
      {:ok, true}

      iex> Ollixir.check_blob(client, "this should not exist")
      {:ok, false}

  ## Returns

  - `{:ok, true}` - When the blob exists
  - `{:ok, false}` - When the blob does not exist
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `create_blob/2` - Create a blob
  """
  @spec check_blob(client(), Blob.digest() | binary()) :: response()
  def check_blob(%__MODULE__{} = client, "sha256:" <> _ = digest),
    do: req(client, :head, "/blobs/#{digest}") |> res_status()

  def check_blob(%__MODULE__{} = client, blob) when is_binary(blob),
    do: check_blob(client, Blob.digest(blob))

  @doc """
  Uploads a blob and returns its digest.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `blob` - File path or raw binary data

  ## Examples

      iex> Ollixir.create_blob(client, "adapter.bin")
      {:ok, "sha256:..."}

      iex> data = File.read!("adapter.bin")
      iex> Ollixir.create_blob(client, data)
      {:ok, "sha256:..."}

  ## Returns

  - `{:ok, digest}` - When the blob was created or already exists
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `check_blob/2` - Verify blob existence
  """
  @spec create_blob(client(), binary()) :: response()
  def create_blob(%__MODULE__{} = client, blob) when is_binary(blob) do
    with {:ok, data} <- read_blob_data(blob) do
      digest = Blob.digest(data)

      client
      |> req(:post, "/blobs/#{digest}", body: data)
      |> res_blob(digest)
    end
  end

  defp read_blob_data(blob) when is_binary(blob) do
    cond do
      File.exists?(blob) ->
        case File.read(blob) do
          {:ok, data} ->
            {:ok, data}

          {:error, reason} ->
            {:error,
             RequestError.exception(
               message: "Failed to read blob file",
               reason: {:file_read_error, reason}
             )}
        end

      path_like?(blob) ->
        {:error,
         RequestError.exception(
           message: "Blob file not found",
           reason: :file_not_found
         )}

      true ->
        {:ok, blob}
    end
  end

  defp path_like?(value) when is_binary(value) do
    String.contains?(value, "/") or String.contains?(value, "\\") or Path.extname(value) != ""
  end

  schema(:embed,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [
      type: :string,
      required: true,
      doc: "The name of the model used to generate the embeddings."
    ],
    input: [
      type: {:or, [:string, @permissive_map, {:list, {:or, [:string, @permissive_map]}}]},
      required: true,
      doc: "Text, a multimodal item, or a mixed list of items."
    ],
    truncate: [
      type: :boolean,
      doc: "Truncates the end of each input to fit within context length."
    ],
    dimensions: [
      type: :integer,
      doc: "Output embedding dimensions (model-specific)"
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded."
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc:
        "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)."
    ]
  )

  @doc """
  Generate embeddings from a model for the given prompt.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list of embed options (see below)

  ## Options

  #{doc(:embed)}

  ## Example

      iex> Ollixir.embed(client, [
      ...>   model: "nomic-embed-text",
      ...>   input: ["Why is the sky blue?", "Why is the grass green?"],
      ...> ])
      {:ok, %{"embedding" => [
        [ 0.009724553, 0.04449892, -0.14063916, 0.0013168337, 0.032128844,
          0.10730086, -0.008447222, 0.010106917, 5.2289694e-4, -0.03554127, ...],
        [ 0.028196355, 0.043162502, -0.18592504, 0.035034444, 0.055619627,
          0.12082449, -0.0090096295, 0.047170386, -0.032078084, 0.0047163847, ...]
      ]}}

  ## Returns

  - `{:ok, map()}` - Embedding response data
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `embeddings/2` - Deprecated embedding API
  """
  @spec embed(client(), keyword()) :: response()
  def embed(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:embed, format)

    with {:ok, params} <- Ollixir.EmbeddingInput.normalize(params),
         {:ok, params} <- normalize_options(params),
         {:ok, params} <- validate_params(params, schema_def(:embed)) do
      client
      |> req(:post, "/embed", json: Enum.into(params, %{}))
      |> res()
      |> apply_cast(cast_fun)
    end
  end

  schema(:embeddings,
    runner: [type: :string, doc: "Select a runner variant."],
    model: [
      type: :string,
      required: true,
      doc: "The name of the model used to generate the embeddings."
    ],
    prompt: [
      type: :string,
      required: true,
      doc: "The prompt used to generate the embedding."
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded."
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc:
        "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)."
    ]
  )

  @doc """
  Generate embeddings from a model for the given prompt.

  ## Parameters

  - `client` - Ollama client from `init/1`
  - `params` - Keyword list of embedding options (see below)

  ## Options

  #{doc(:embeddings)}

  ## Example

      iex> Ollixir.embeddings(client, [
      ...>   model: "llama2",
      ...>   prompt: "Here is an article about llamas..."
      ...> ])
      {:ok, %{"embedding" => [
        0.5670403838157654, 0.009260174818336964, 0.23178744316101074, -0.2916173040866852, -0.8924556970596313,
        0.8785552978515625, -0.34576427936553955, 0.5742510557174683, -0.04222835972905159, -0.137906014919281
      ]}}

  ## Returns

  - `{:ok, map()}` - Embedding response data
  - `{:error, Ollixir.RequestError.t()}` - On validation errors
  - `{:error, Ollixir.ResponseError.t()}` - On HTTP errors

  ## See Also

  - `embed/2` - Preferred embedding API
  """
  @deprecated "Superseded by embed/2"
  @spec embeddings(client(), keyword()) :: response()
  def embeddings(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)
    cast_fun = cast_fun_for(:embeddings, format)

    with {:ok, params} <- normalize_options(params),
         {:ok, params} <- validate_params(params, schema_def(:embeddings)) do
      client
      |> req(:post, "/embeddings", json: Enum.into(params, %{}))
      |> res()
      |> apply_cast(cast_fun)
    end
  end

  @doc """
  Search the web using Ollama's cloud search API.

  Delegates to `Ollixir.Web.search/2`.
  """
  @spec web_search(client(), keyword()) :: response()
  def web_search(%__MODULE__{} = client, params) when is_list(params) do
    Web.search(client, params)
  end

  @doc """
  Search the web using Ollama's cloud search API, raising on error.

  Delegates to `Ollixir.Web.search!/2`.
  """
  @spec web_search!(client(), keyword()) :: Web.SearchResponse.t()
  def web_search!(%__MODULE__{} = client, params) when is_list(params) do
    Web.search!(client, params)
  end

  @doc """
  Fetch content from a URL using Ollama's cloud fetch API.

  Delegates to `Ollixir.Web.fetch/2`.
  """
  @spec web_fetch(client(), keyword()) :: response()
  def web_fetch(%__MODULE__{} = client, params) when is_list(params) do
    Web.fetch(client, params)
  end

  @doc """
  Fetch content from a URL using Ollama's cloud fetch API, raising on error.

  Delegates to `Ollixir.Web.fetch!/2`.
  """
  @spec web_fetch!(client(), keyword()) :: Web.FetchResponse.t()
  def web_fetch!(%__MODULE__{} = client, params) when is_list(params) do
    Web.fetch!(client, params)
  end

  schema(:system_one,
    model: [type: :string, required: true, doc: "Decision model name."],
    runner: [type: :string, doc: "Runner variant."],
    state: [type: :any, required: true, doc: "String, JSON object, or array to evaluate."],
    images: [type: {:list, :string}, doc: "Optional images for a compatible model."],
    videos: [type: {:list, :any}, doc: "Reserved; only an empty list is accepted."],
    questions: [type: :any, required: true, doc: "Named questions (map or ordered pairs)."],
    keep_alive: [type: {:or, [:integer, :string]}, doc: "Model keep-alive duration."]
  )

  @doc """
  Ask a decision model typed questions about a state via `/v1/systemone`.

  #{doc(:system_one)}

      Ollixir.system_one(client,
        model: "decision-model",
        state: "The parcel arrived yesterday.",
        questions: [{"delivered", %{type: "noul", instructions: "Was it delivered?"}}]
      )

  Questions are encoded as an object; ordered pairs preserve request order.
  The endpoint is non-streaming. Video is not supported by current local runners.
  """
  @spec system_one(client(), keyword()) :: response()
  def system_one(%__MODULE__{} = client, params) when is_list(params) do
    {format, params} = pop_response_format(params)

    with {:ok, params} <- normalize_images(params),
         {:ok, params} <- validate_params(params, schema_def(:system_one)),
         {:ok, params} <- Ollixir.SystemOne.normalize(params) do
      client
      |> Ollixir.Transport.request(:post, "/v1/systemone", json: Map.new(params))
      |> apply_cast(cast_fun_for(:system_one, format))
    end
  end

  @doc """
  Show all manifests for a model. With `response_format: :struct`, returns
  `Ollixir.Types.ShowManifestsResponse` rather than a single show response.
  """
  @spec show_manifests(client(), keyword()) :: response()
  def show_manifests(client, params),
    do: show_model(client, Keyword.put(params, :all_manifests, true))

  @doc "Check the server root with HEAD. Returns `{:ok, true}` on success."
  @spec heartbeat(client()) :: response()
  def heartbeat(client), do: successful_request(client, :head, "/")

  @doc "Get the Ollama server version (`GET /api/version`)."
  @spec version(client(), keyword()) :: response()
  def version(client, opts \\ []), do: server_get(client, "/api/version", :version, opts)

  @doc "Get the server cloud configuration (`GET /api/status`)."
  @spec status(client(), keyword()) :: response()
  def status(client, opts \\ []), do: server_get(client, "/api/status", :server_status, opts)

  @doc "Alias for `status/2`."
  def cloud_status(client, opts \\ []), do: status(client, opts)

  @doc "Alias matching the upstream Go client's experimental cloud status operation."
  def cloud_status_experimental(client, opts \\ []), do: status(client, opts)

  @doc "Get the account signed into the server (`POST /api/me`)."
  @spec whoami(client(), keyword()) :: response()
  def whoami(client, opts \\ []) do
    {format, _opts} = pop_response_format(opts)

    client
    |> Ollixir.Transport.request(:post, "/api/me")
    |> apply_cast(cast_fun_for(:whoami, format))
  end

  @doc "Alias for `whoami/2`."
  def me(client, opts \\ []), do: whoami(client, opts)

  @doc "Get the signed-in server account's balance as a raw response map."
  def balance(client), do: Ollixir.Transport.request(client, :get, "/api/balance")

  @doc "Get the signed-in server account's usage as a raw response map."
  def usage(client), do: Ollixir.Transport.request(client, :get, "/api/usage")

  @doc "Sign the server account out. This changes server state."
  def signout(client), do: successful_request(client, :post, "/api/signout")

  @doc "Disconnect using an already encoded public-key identifier."
  def disconnect(client, encoded_key) when is_binary(encoded_key) and encoded_key != "" do
    segment = URI.encode(encoded_key, &URI.char_unreserved?/1)
    successful_request(client, :delete, "/api/user/keys/" <> segment)
  end

  def disconnect(_client, _key), do: {:error, RequestError.missing_field(:encoded_key)}

  @doc "Get experimental model recommendations from the configured server."
  def model_recommendations(client, opts \\ []),
    do:
      server_get(client, "/api/experimental/model-recommendations", :model_recommendations, opts)

  @doc "Alias for `model_recommendations/2`."
  def model_recommendations_experimental(client, opts \\ []),
    do: model_recommendations(client, opts)

  @doc "Search the web through the configured server's experimental proxy."
  def web_search_experimental(client, params), do: Web.search_experimental(client, params)

  @doc "Fetch a URL through the configured server's experimental proxy."
  def web_fetch_experimental(client, params), do: Web.fetch_experimental(client, params)

  defp server_get(client, path, endpoint, opts) do
    {format, _opts} = pop_response_format(opts)

    client
    |> Ollixir.Transport.request(:get, path)
    |> apply_cast(cast_fun_for(endpoint, format))
  end

  defp successful_request(client, method, path) do
    case Ollixir.Transport.request(client, method, path, retry: false) do
      {:ok, _} -> {:ok, true}
      error -> error
    end
  end

  @doc false
  def __schemas__, do: @schemas

  # Builds the request from the given params
  @spec req(client(), atom(), Req.url(), keyword()) :: req_response()
  defp req(%__MODULE__{req: req}, method, url, opts \\ []) do
    {cast_fun, opts} = Keyword.pop(opts, :cast)
    streaming_endpoint = url in ["/chat", "/generate", "/create", "/pull", "/push"]
    opts = Keyword.merge(opts, method: method, url: normalize_url(url))
    stream_opt = get_in(opts, [:json, :stream])

    cond do
      stream_opt ->
        opts =
          opts
          |> Keyword.update!(:json, &Map.put(&1, :stream, true))
          |> Keyword.merge(decode_body: false, retry: false, compressed: false)

        work = fn dest -> native_stream(req, opts, dest, cast_fun) end

        case stream_opt do
          true ->
            stream =
              Stream.resource(
                fn ->
                  dest = self()
                  {Task.async(fn -> work.(dest) end), false}
                end,
                &stream_next/1,
                &stream_end/1
              )

            {:ok, stream}

          pid ->
            {:ok, Task.async(fn -> work.(pid) end)}
        end

      streaming_endpoint and is_map(Keyword.get(opts, :json)) ->
        opts = Keyword.update!(opts, :json, &Map.put(&1, :stream, false))
        Req.request(req, opts)

      true ->
        Req.request(req, opts)
    end
  end

  defp normalize_url(url) when is_binary(url), do: String.trim_leading(url, "/")
  defp normalize_url(url), do: url

  # Normalizes the response returned from the request
  @spec res(req_response()) :: response()
  defp res({:ok, %Task{} = task}), do: {:ok, task}
  defp res({:ok, enum}) when is_function(enum), do: {:ok, enum}

  defp res({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp res({:ok, %{status: status, body: body}}) do
    {:error, ResponseError.exception(status: status, body: body)}
  end

  defp res({:ok, %{status: status}}) do
    {:error, ResponseError.exception(status)}
  end

  defp res({:error, %Req.TransportError{} = error}) do
    {:error, ConnectionError.exception(original_error: error)}
  end

  defp res({:error, error}) do
    {:error, RequestError.exception(inspect(error))}
  end

  # Normalizes blob uploads, returning the digest on success.
  @spec res_blob(req_response(), binary()) :: response()
  defp res_blob({:ok, %{status: status}}, digest) when status in 200..299, do: {:ok, digest}

  defp res_blob({:ok, %{status: status, body: body}}, _digest),
    do: {:error, ResponseError.exception(status: status, body: body)}

  defp res_blob({:ok, %{status: status}}, _digest), do: {:error, ResponseError.exception(status)}

  defp res_blob({:error, %Req.TransportError{} = error}, _digest) do
    {:error, ConnectionError.exception(original_error: error)}
  end

  defp res_blob({:error, error}, _digest), do: {:error, RequestError.exception(inspect(error))}

  # Normalizes status-only responses without raising on HTTP errors.
  @spec res_status(req_response()) :: response()
  defp res_status({:ok, %{status: status}}) when status in 200..299, do: {:ok, true}
  defp res_status({:ok, %{status: _status}}), do: {:ok, false}

  defp res_status({:error, %Req.TransportError{} = error}) do
    {:error, ConnectionError.exception(original_error: error)}
  end

  defp res_status({:error, error}), do: {:error, RequestError.exception(inspect(error))}

  # Native streaming uses NDJSON, not one JSON object per transport chunk.
  defp native_stream(req, opts, dest, cast_fun) do
    handler = fn {:data, chunk}, {request, response} ->
      {:cont, {request, native_chunk(response, chunk, dest, cast_fun)}}
    end

    case Req.request(req, Keyword.put(opts, :into, handler)) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        response =
          if not Map.has_key?(response.private, :ollixir_ndjson) and is_binary(response.body) do
            native_chunk(%{response | body: ""}, response.body, dest, cast_fun)
          else
            response
          end

        buffer = Map.get(response.private, :ollixir_ndjson, "")
        response = native_line(response, buffer, dest, cast_fun)

        case response.private[:ollixir_ndjson_error] do
          nil -> finish_native(response, opts[:url])
          error -> {:error, error}
        end

      result ->
        Ollixir.Transport.result(result)
    end
  end

  defp finish_native(%{body: %{"done" => true} = body}, endpoint)
       when endpoint in ["chat", "generate"],
       do: {:ok, body}

  defp finish_native(%{body: %{"_debug_info" => _} = body}, endpoint)
       when endpoint in ["chat", "generate"],
       do: {:ok, body}

  defp finish_native(%{body: body}, endpoint)
       when endpoint not in ["chat", "generate"] and is_map(body),
       do: {:ok, body}

  defp finish_native(_response, _endpoint),
    do: {:error, RequestError.exception("Incomplete NDJSON response")}

  defp native_chunk(%{status: status} = response, chunk, _dest, _cast_fun)
       when status not in 200..299 do
    %{response | body: (response.body || "") <> chunk}
  end

  defp native_chunk(response, chunk, dest, cast_fun) do
    buffer = Map.get(response.private, :ollixir_ndjson, "")
    {buffer, lines} = List.pop_at(:binary.split(buffer <> chunk, "\n", [:global]), -1)
    response = %{response | private: Map.put(response.private, :ollixir_ndjson, buffer)}
    Enum.reduce(lines, response, &native_line(&2, &1, dest, cast_fun))
  end

  defp native_line(response, line, dest, cast_fun) do
    cond do
      response.private[:ollixir_ndjson_error] ->
        response

      line in ["", "\r", " ", "\t"] ->
        response

      true ->
        case Jason.decode(line) do
          {:ok, %{"error" => _} = data} ->
            native_error(response, ResponseError.exception(status: response.status, body: data))

          {:ok, data} when is_map(data) ->
            payload = if is_function(cast_fun), do: cast_fun.(data), else: data
            send(dest, {self(), {:data, payload}})
            %{response | body: merge_native(response.body, data)}

          _ ->
            native_error(response, RequestError.exception("Invalid NDJSON response"))
        end
    end
  end

  defp native_error(response, error) do
    %{response | private: Map.put(response.private, :ollixir_ndjson_error, error)}
  end

  defp merge_native(body, %{"done" => _} = data) when is_map(body),
    do: Map.merge(body, data, &merge_native_field/3)

  defp merge_native(_body, data), do: data

  defp merge_native_field(key, prev, next)
       when key in ["response", "content", "thinking"] and is_binary(prev) and is_binary(next),
       do: prev <> next

  defp merge_native_field("message", prev, next) when is_map(prev) and is_map(next),
    do: Map.merge(prev, next, &merge_native_field/3)

  defp merge_native_field(key, prev, next)
       when key in ["tool_calls", "logprobs"] and is_list(prev) and is_list(next),
       do: prev ++ next

  defp merge_native_field(_key, _prev, next), do: next

  defp stream_next({%Task{pid: pid, ref: ref} = task, false}) do
    receive do
      {^pid, {:data, data}} ->
        {[data], {task, false}}

      {^ref, {:ok, _}} ->
        Process.demonitor(ref, [:flush])
        {:halt, {task, true}}

      {^ref, {:error, error}} ->
        Process.demonitor(ref, [:flush])
        raise error

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise RequestError.exception("Stream task stopped: #{inspect(reason)}")
    end
  end

  defp stream_end({%Task{pid: pid} = task, finished}) do
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

    drain_stream(pid)
  end

  defp drain_stream(pid) do
    receive do
      {^pid, {:data, _}} -> drain_stream(pid)
    after
      0 -> :ok
    end
  end
end
