# Anthropic Compatibility

`Ollixir.Anthropic` implements the Ollama `POST /v1/messages` compatibility
route. This is not the full Anthropic API. It preserves provider-shaped
messages, content blocks, system prompts, tools, thinking fields and usage
without converting them into native Ollama structs.

```elixir
client = Ollixir.Anthropic.init(base_url: "http://localhost:11434")

{:ok, response} = Ollixir.Anthropic.messages(client,
  model: "llama3.2",
  max_tokens: 128,
  system: "Answer briefly.",
  messages: [%{role: "user", content: [%{type: "text", text: "Hello"}]}]
)

IO.inspect(response["content"])
```

Pass `api_key:` to set an `x-api-key` header if required by your deployment.
Custom headers (including an `anthropic-version` header) can be provided using
Req options. The server controls which model capabilities are supported.
`messages/2` (alias `message/2`) requires `model`, `messages`, and `max_tokens`.
Ollama v0.40.18 exposes Messages on this route. The stream ends with
`message_stop`.

## Streaming

```elixir
{:ok, events} = Ollixir.Anthropic.messages(client,
  model: "llama3.2", max_tokens: 128,
  messages: [%{role: "user", content: "Hello"}], stream: true
)

Enum.each(events, fn event ->
  case event["type"] do
    "content_block_delta" -> IO.inspect(event["delta"])
    _ -> IO.inspect(event)
  end
end)
```

SSE payloads retain their `type` and data fields. With `stream: pid`, the worker
sends `{task.pid, {:data, payload}}` messages and completes with `{:ok, :done}`
or an error tuple. The enumerable raises on errors. Native `response_format:
:struct` does not apply; provider JSON is returned as maps.

See [OpenAI Compatibility](openai-compatibility.md) for shared transport,
error handling, and early termination semantics.
