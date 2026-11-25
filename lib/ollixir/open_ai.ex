defmodule Ollixir.OpenAI do
  @moduledoc """
  Client for Ollama's OpenAI-compatible `/v1` endpoints.

  These are Ollama's compatibility routes, not a complete OpenAI SDK. Send
  provider-shaped maps or keyword lists; responses and SSE payloads are raw
  JSON maps. Native options such as `response_format: :struct` do not apply.
  `response_format` is a provider request field on the relevant routes.

  Streaming endpoints accept `stream: true` for a lazy enumerable or a PID
  for a task which sends `{task.pid, {:data, payload}}` messages. The task
  returns `{:ok, :done}` or `{:error, error}`; enumeration raises on errors.
  SSE `[DONE]` markers are not returned as data. Speech can stream raw bytes.
  """

  alias Ollixir.{Multipart, Protocol, RequestError, Transport}

  @doc "Initialize with the same host/Req options as `Ollixir.init/1`, or reuse a client."
  def init(opts \\ []), do: Protocol.init(opts, :openai)

  @doc "Create a chat completion (`POST /v1/chat/completions`)."
  def chat_completions(client, params),
    do: Protocol.json(client, "/v1/chat/completions", params, [:model, :messages], :sse)

  @doc "Alias for `chat_completions/2`."
  def chat(client, params), do: chat_completions(client, params)

  @doc "Create a text completion (`POST /v1/completions`)."
  def completions(client, params),
    do: Protocol.json(client, "/v1/completions", params, [:model, :prompt], :sse)

  @doc "Alias for `completions/2`."
  def completion(client, params), do: completions(client, params)

  @doc "Create embeddings (`POST /v1/embeddings`)."
  def embeddings(client, params),
    do: Protocol.json(client, "/v1/embeddings", params, [:model, :input])

  @doc "Alias for `embeddings/2`."
  def embed(client, params), do: embeddings(client, params)

  @doc "List available models (`GET /v1/models`)."
  def models(client), do: Transport.request(client, :get, "/v1/models")

  @doc "Alias for `models/1`."
  def list_models(client), do: models(client)

  @doc "Retrieve a model (`GET /v1/models/:model`)."
  def retrieve_model(client, model) when is_binary(model) and model != "" do
    segment = URI.encode(model, &URI.char_unreserved?/1)
    Transport.request(client, :get, "/v1/models/" <> segment)
  end

  def retrieve_model(_client, _model), do: {:error, RequestError.missing_field(:model)}

  @doc "Alias for `retrieve_model/2`."
  def model(client, model), do: retrieve_model(client, model)

  @doc "Create a Responses API response (`POST /v1/responses`)."
  def responses(client, params),
    do: Protocol.json(client, "/v1/responses", params, [:model, :input], :sse)

  @doc "Compact a Responses API transcript (`POST /v1/responses/compact`)."
  def responses_compact(client, params),
    do: Protocol.json(client, "/v1/responses/compact", params, [:model, :input])

  @doc "Alias for `responses_compact/2`."
  def compact(client, params), do: responses_compact(client, params)

  @doc """
  Transcribe an audio file (`POST /v1/audio/transcriptions`).

  `file` is a path or `{:binary, bytes, filename}`. The wire request is
  multipart form data. Response formats are `json`, `text`, `verbose_json`;
  `stream: true` or a PID requests SSE.
  """
  def audio_transcriptions(client, params),
    do: audio_text(client, "/v1/audio/transcriptions", params)

  @doc "Translate audio (`POST /v1/audio/translations`); supports `to_language`."
  def audio_translations(client, params), do: audio_text(client, "/v1/audio/translations", params)

  @doc "Synthesize speech (`POST /v1/audio/speech`); returns audio bytes or streams byte chunks."
  def audio_speech(client, params),
    do: Protocol.json(client, "/v1/audio/speech", params, [:model, :input], :binary)

  @doc "Alias for `audio_transcriptions/2`."
  def transcription(client, params), do: audio_transcriptions(client, params)

  @doc "Alias for `audio_translations/2`."
  def translation(client, params), do: audio_translations(client, params)

  @doc "Alias for `audio_speech/2`."
  def speech(client, params), do: audio_speech(client, params)

  defp audio_text(client, path, params) do
    with {:ok, body} <- Protocol.body(params),
         :ok <- Protocol.require_fields(body, [:model, :file]),
         {:ok, stream} <- Protocol.stream_option(body, :sse),
         {:ok, opts} <- Multipart.encode(Protocol.wire_stream(body, stream)) do
      Protocol.dispatch(client, path, opts, stream, :sse)
    end
  end
end
