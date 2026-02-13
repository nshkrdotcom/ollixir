# Ollixir

<p align="center">
  <img src="assets/ollixir.svg" alt="Ollixir" width="200" />
</p>

[![Hex.pm](https://img.shields.io/hexpm/v/ollixir?color=informational)](https://hex.pm/packages/ollixir)
[![License](https://img.shields.io/badge/license-MIT-informational)](https://github.com/nshkrdotcom/ollixir/blob/main/LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/nshkrdotcom/ollixir/elixir.yml?branch=main)](https://github.com/nshkrdotcom/ollixir/actions)

[Ollama](https://ollama.com) runs large language models locally or on your infrastructure.
Ollixir provides a first-class Elixir client with feature parity to the official
ollama-python library.

## Features

- Chat, generate, embeddings, and full model management API coverage
- Streaming to an `Enumerable` or directly to any process
- Tool use (function calling) + function-to-tool helpers
- Structured outputs (JSON or JSON Schema)
- Multimodal image support with automatic Base64 encoding
- Typed responses (`response_format: :struct`) and typed options (`Ollixir.Options`)
- HuggingFace Hub integration: discover and run 45K+ GGUF models ([optional dep](guides/huggingface.md#installation))
- Cloud API: web search and web fetch

## Prerequisites

1. Install Ollama: https://ollama.com/download
2. Start the server (if needed): `ollama serve`
3. Pull a model: `ollama pull llama3.2`

For examples, also pull:

- `ollama pull nomic-embed-text` (embeddings)
- `ollama pull llava` (multimodal)
- `ollama pull deepseek-r1:1.5b` (thinking)
- `ollama pull codellama:7b-code` (fill-in-middle)

Or pull everything at once:

```bash
./examples/install_models.sh
```

Thinking examples use `deepseek-r1:1.5b`, which supports `think`.

For full setup details (including cloud usage and Linux manual install), see
[Ollama Server Setup](guides/ollama-setup.md).

## Installation

Requires Elixir 1.15+.

```elixir
def deps do
  [
    {:ollixir, "~> 0.1.1"}
  ]
end
```

## Quickstart

### 1. Chat

```elixir
client = Ollixir.init()

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Why is the sky blue?"}]
)

IO.puts(response["message"]["content"])
```

### 2. Completion

```elixir
{:ok, response} = Ollixir.completion(client,
  model: "llama3.2",
  prompt: "The capital of France is"
)

IO.puts(response["response"])
```

### 3. Structured output

```elixir
schema = %{
  type: "object",
  properties: %{
    name: %{type: "string"},
    capital: %{type: "string"},
    languages: %{type: "array", items: %{type: "string"}}
  },
  required: ["name", "capital", "languages"]
}

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Tell me about Canada."}],
  format: schema
)

{:ok, data} = Jason.decode(response["message"]["content"])
IO.inspect(data)
```

## Typed responses

Return response structs instead of maps by setting `response_format: :struct`:

```elixir
{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Summarize Elixir."}],
  response_format: :struct
)

IO.puts(response.message.content)
```

You can also set a default:

```elixir
Application.put_env(:ollixir, :response_format, :struct)
```

## Streaming

### Enumerable mode

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Tell me a short story."}],
  stream: true
)

stream
|> Stream.each(fn chunk ->
  if content = get_in(chunk, ["message", "content"]) do
    IO.write(content)
  end
end)
|> Stream.run()
```

### Process mode

```elixir
{:ok, task} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Stream to my process"}],
  stream: self()
)

receive do
  {_pid, {:data, chunk}} -> IO.inspect(chunk)
end

Task.await(task, 60_000)
```

## Multimodal images

You can pass image paths, binary data, or pre-encoded Base64. The client will
encode automatically:

```elixir
image_path = "/path/to/photo.jpg"

{:ok, response} = Ollixir.chat(client,
  model: "llava",
  messages: [%{role: "user", content: "Describe this image.", images: [image_path]}]
)

IO.puts(response["message"]["content"])
```

Use `Ollixir.Image.encode/1` to pre-encode images if you prefer.

## Tools (function calling)

Define tools manually or use helpers:

```elixir
calculator = Ollixir.Tool.define(:calculator,
  description: "Evaluate a math expression",
  parameters: [expression: [type: :string, required: true]]
)

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "What is 9 * 9?"}],
  tools: [calculator]
)
```

You can also pass functions directly and let Ollixir convert them to tools:

```elixir
defmodule MathTools do
  @doc "Add two integers together."
  @spec add(integer(), integer()) :: integer()
  def add(a, b), do: a + b
end

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Add 4 and 7"}],
  tools: [&MathTools.add/2]
)
```

## Options

Use the `Ollixir.Options` struct or presets:

```elixir
opts =
  Ollixir.Options.Presets.creative()
  |> Ollixir.Options.temperature(0.9)
  |> Ollixir.Options.top_p(0.95)

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [%{role: "user", content: "Write a playful haiku."}],
  options: opts
)
```

## Embeddings

```elixir
{:ok, response} = Ollixir.embed(client,
  model: "nomic-embed-text",
  input: ["The sky is blue", "The grass is green"]
)

IO.inspect(response["embeddings"])
```

## Web search and fetch (cloud API)

These calls require an Ollama API key (`OLLAMA_API_KEY`):

```elixir
{:ok, results} = Ollixir.web_search(client, query: "Elixir language")
{:ok, page} = Ollixir.web_fetch(client, url: "https://elixir-lang.org")
```

### Cloud API key setup

1) Create an Ollama account: https://ollama.com
2) Generate a key: https://ollama.com/settings/keys
3) Export it:

```bash
export OLLAMA_API_KEY="your_api_key_here"
```

If the key is missing, web examples will skip with a helpful message. If the
key is invalid, you will see a 401/403 response from the API.

When passing headers explicitly, the `authorization` value must start with
`Bearer `.

## Cloud Models and Hosted API

### Use cloud models via local Ollama

1) Sign in (one-time):

```bash
ollama signin
```

2) Pull a cloud model:

```bash
ollama pull gpt-oss:120b-cloud
```

3) Make a request:

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "gpt-oss:120b-cloud",
  messages: [%{role: "user", content: "Why is the sky blue?"}],
  stream: true
)

Stream.each(stream, fn chunk ->
  IO.write(get_in(chunk, ["message", "content"]) || "")
end)
|> Stream.run()
```

Cloud models available include:

**Coding & Agentic:**
- `minimax-m2.5:cloud` — Coding, tools, thinking
- `deepseek-v3.1:671b-cloud` — 671B, thinking, tools
- `deepseek-v3.2:cloud` — Reasoning, agentic
- `devstral-2:123b-cloud` — 123B, agentic coding
- `devstral-small-2:24b-cloud` — 24B, agentic coding
- `qwen3-coder:480b-cloud` — 480B, code generation
- `qwen3-coder-next:cloud` — 80B (3B active), agentic coding

**General Purpose & Reasoning:**
- `glm-5:cloud` — 744B (40B active), reasoning
- `gemini-3-flash-preview:cloud` — 1M context, vision, thinking
- `cogito-2.1:671b-cloud` — 671B, MIT license
- `gpt-oss:20b-cloud` / `gpt-oss:120b-cloud` — Thinking levels
- `qwen3-next:80b-cloud` — 80B, efficient inference
- `nemotron-3-nano:30b-cloud` — 30B (3.5B active), 1M context

**Multimodal & Specialized:**
- `kimi-k2.5:cloud` — Vision + language, thinking
- `kimi-k2:1t-cloud` — 1T (32B active), agentic
- `kimi-k2-thinking:cloud` — Reasoning, agentic
- `qwen3-vl:235b-cloud` — 235B, vision-language
- `ministral-3:3b/8b/14b-cloud` — Edge, vision
- `glm-4.6:cloud` / `glm-4.7:cloud` — Coding, agentic
- `minimax-m2:cloud` / `minimax-m2.1:cloud` — Coding
- `rnj-1:8b-cloud` — 8B, code & STEM

See https://ollama.com/search?c=cloud for the latest list.

### Call the hosted API (ollama.com)

1) Create an API key: https://ollama.com/settings/keys

2) Export the key:

```bash
export OLLAMA_API_KEY="your_api_key_here"
```

3) (Optional) List models:

```bash
curl https://ollama.com/api/tags
```

4) Point the client at the hosted API:

```elixir
client = Ollixir.init("https://ollama.com")

{:ok, response} = Ollixir.chat(client,
  model: "gpt-oss:120b",
  messages: [%{role: "user", content: "Why is the sky blue?"}]
)
```

`OLLAMA_API_KEY` is used automatically if it is set. To override headers:

```elixir
client = Ollixir.init("https://ollama.com",
  headers: [{"authorization", "Bearer your_api_key_here"}]
)
```

## Client configuration

```elixir
client = Ollixir.init("http://localhost:11434")
client = Ollixir.init("localhost:11434")
client = Ollixir.init(":11434")
client = Ollixir.init(host: "ollama.internal:11434")
client = Ollixir.init(headers: [{"x-some-header", "some-value"}])
client = Ollixir.init(receive_timeout: 120_000)

req = Req.new(base_url: "http://localhost:11434/api", headers: [{"x-env", "dev"}])
client = Ollixir.init(req)
```

Environment variables:

- `OLLAMA_HOST` sets the default host (e.g. `http://localhost:11434`)
- `OLLAMA_API_KEY` provides a bearer token for the hosted API

## Error handling

All functions return `{:ok, result}` or `{:error, reason}`:

```elixir
case Ollixir.chat(client, model: "not-found", messages: [%{role: "user", content: "Hi"}]) do
  {:ok, response} -> response
  {:error, %Ollixir.ConnectionError{} = error} -> IO.puts("Connection error: #{Exception.message(error)}")
  {:error, %Ollixir.RequestError{} = error} -> IO.puts("Request error: #{Exception.message(error)}")
  {:error, %Ollixir.ResponseError{} = error} -> IO.puts("Response error: #{Exception.message(error)}")
end
```

## API surface

The client mirrors the Ollama REST API, with Python-style aliases where helpful:

```elixir
Ollixir.chat(client, model: "llama3.2", messages: [%{role: "user", content: "Hello"}])
Ollixir.completion(client, model: "llama3.2", prompt: "Hello")
Ollixir.generate(client, model: "llama3.2", prompt: "Hello")
Ollixir.list_models(client)
Ollixir.list(client)
Ollixir.show_model(client, name: "llama3.2")
Ollixir.show(client, name: "llama3.2")
Ollixir.list_running(client)
Ollixir.ps(client)
Ollixir.create_model(client, name: "example", from: "llama3.2", system: "You are Mario.")
Ollixir.create(client, name: "example", from: "llama3.2")
Ollixir.copy_model(client, source: "llama3.2", destination: "user/llama3.2")
Ollixir.copy(client, source: "llama3.2", destination: "user/llama3.2")
Ollixir.delete_model(client, name: "llama3.2")
Ollixir.delete(client, name: "llama3.2")
Ollixir.pull_model(client, name: "llama3.2")
Ollixir.pull(client, name: "llama3.2")
Ollixir.push_model(client, name: "user/llama3.2")
Ollixir.push(client, name: "user/llama3.2")
Ollixir.embed(client, model: "nomic-embed-text", input: "The sky is blue.")
Ollixir.embeddings(client, model: "llama3.2", prompt: "Legacy embeddings")
Ollixir.web_search(client, query: "Elixir language")
Ollixir.web_fetch(client, url: "https://elixir-lang.org")
```

## Examples and Guides

- [Examples](examples/README.md)
- MCP Server (`examples/mcp/mcp_server.exs`) - Works with any MCP client that supports stdio (Cursor, Claude Desktop, Cline, Continue, Open WebUI)
- [Getting Started](guides/getting-started.md)
- [Streaming](guides/streaming.md)
- [Tools](guides/tools.md)
- [Structured Outputs](guides/structured-outputs.md)
- [Thinking Mode](guides/thinking.md)
- [Embeddings](guides/embeddings.md)
- [Multimodal](guides/multimodal.md)
- [HuggingFace Integration](guides/huggingface.md)
- [Cloud API](guides/cloud-api.md)
- [Ollama Server Setup](guides/ollama-setup.md)
- [Cheatsheet](guides/cheatsheet.md)

## License

This package is open source and released under the [MIT License](LICENSE).

---

<sub>Ollixir is based on [ollama-ex](https://github.com/lebrunel/ollama-ex) by Push Code Ltd.</sub>
