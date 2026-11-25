# OpenAI Compatibility

`Ollixir.OpenAI` calls the OpenAI-compatible routes of the configured Ollama
server. It accepts maps or keyword lists with provider-shaped fields and
returns raw JSON maps. It does not target the OpenAI service or implement all
OpenAI SDK operations. Server and model capabilities determine accepted fields.

```elixir
client = Ollixir.OpenAI.init(base_url: "http://localhost:11434")
# Or reuse the configuration of an existing native Ollixir client:
# client = Ollixir.OpenAI.init(Ollixir.init())

{:ok, response} = Ollixir.OpenAI.chat_completions(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Hello"}],
  response_format: %{type: "json_object"}
)
```

`api_key:` sets a Bearer authorization header if needed. As with the native
client, Req headers and options can be supplied at initialization. Do not
send real credentials to untrusted hosts. Hosts with `/api`, `/v1`, or a
reverse-proxy prefix resolve to sibling `/v1` routes.

| Function | Route | Streaming |
| --- | --- | --- |
| `chat_completions/2` (`chat`) | `POST /v1/chat/completions` | SSE |
| `completions/2` (`completion`) | `POST /v1/completions` | SSE |
| `embeddings/2` (`embed`) | `POST /v1/embeddings` | No |
| `models/1` (`list_models`) | `GET /v1/models` | No |
| `retrieve_model/2` (`model`) | `GET /v1/models/:model` | No |
| `responses/2` | `POST /v1/responses` | SSE |
| `responses_compact/2` (`compact`) | `POST /v1/responses/compact` | No |
| `audio_transcriptions/2` (`transcription`) | `POST /v1/audio/transcriptions` | SSE |
| `audio_translations/2` (`translation`) | `POST /v1/audio/translations` | SSE |
| `audio_speech/2` (`speech`) | `POST /v1/audio/speech` | Bytes |

`response_format` is a provider request field, not Ollixir's native
`:map`/`:struct` option. Provider messages, tool schemas, input items and
content blocks retain their JSON shape. Unsupported fields or models may be
rejected by Ollama.

## Streaming

```elixir
{:ok, stream} = Ollixir.OpenAI.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Hello"}],
  stream: true
)

Enum.each(stream, &IO.inspect/1)
```

The lazy enumerable emits decoded SSE data objects, not lines or `[DONE]`.
Chunk boundaries are independent of events. Early termination closes the worker.
With `stream: self()`, receive `{task.pid, {:data, payload}}` messages and call
`Task.await(task)` for `{:ok, :done}` or `{:error, error}`. Enumeration raises
on transport, HTTP, or stream decoding errors. Responses and chat chunks are
not merged into a synthesized provider response; accumulate them as needed.

## Responses and audio

```elixir
{:ok, result} = Ollixir.OpenAI.responses(client,
  model: "llama3.2", input: "Summarize this topic."
)
```

Compaction sends a provider-shaped transcript to `responses_compact/2`.
Audio transcription and translation use multipart fields, not JSON:

```elixir
{:ok, transcript} = Ollixir.OpenAI.audio_transcriptions(client,
  model: "your-transcription-model", file: "recording.wav",
  response_format: "json"
)

{:ok, bytes} = Ollixir.OpenAI.audio_speech(client,
  model: "your-speech-model", input: "Hello", response_format: "wav"
)
File.write!("speech.wav", bytes)
```

`file:` accepts a path, `{:file, path}`, or `{:binary, bytes, filename}`.
Audio fields are scalar multipart values. Use `language` for the source
language and `to_language` for the translation target. The server accepts
`json`, `text`, and `verbose_json` response formats.

`audio_speech/2` returns WAV or PCM bytes. Pass `voice` to select a voice
supported by the model. The server accepts `speed: 1` and
`stream_format: "audio"` when supplied. With `stream: true`, Ollixir delivers
each binary chunk in order and omits `stream` from the JSON request.

Failures use Ollixir's `RequestError`, `ConnectionError`, or `ResponseError`
exceptions (returned as error tuples for non-streaming calls). HTTP/provider
error bodies are retained, including nested error details.

Ollama v0.40.18 accepts a string prompt for text completions. Send the
conversation as `input` when continuing a Responses request. The stable
converter does not restore conversation state from `previous_response_id`.
