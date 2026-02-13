# Ollixir Cheatsheet

## Installation

```elixir
{:ollixir, "~> 0.1.1"}
```

## Error Types

```elixir
{:error, %Ollixir.ConnectionError{}}  # Server unreachable
{:error, %Ollixir.RequestError{}}     # Invalid request
{:error, %Ollixir.ResponseError{}}    # API error (4xx/5xx)
```

## Client

```elixir
client = Ollixir.init()                              # Default
client = Ollixir.init("http://host:11434")          # Custom host
client = Ollixir.init("host:11434")                 # Host without scheme
client = Ollixir.init(":11434")                     # Port-only host
client = Ollixir.init(host: "host:11434")           # Host option
client = Ollixir.init(receive_timeout: 120_000)     # With options
```

## Environment

```bash
export OLLAMA_HOST="http://host:11434"
export OLLAMA_API_KEY="your_api_key_here"
```

`OLLAMA_API_KEY` is required for web search/fetch and cloud tests.

## Chat

```elixir
Ollixir.chat(client, model: "llama3.2", messages: [%{role: "user", content: "Hi"}])
```

## Completion

```elixir
Ollixir.completion(client, model: "llama3.2", prompt: "Once upon a time")
Ollixir.generate(client, model: "llama3.2", prompt: "...")  # Alias
Ollixir.completion(client, ..., suffix: "return result")    # Fill-in-middle
Ollixir.completion(client, ..., logprobs: true, top_logprobs: 3)  # Log probs
```

## Streaming

```elixir
# Enumerable
{:ok, stream} = Ollixir.chat(client, ..., stream: true)
Enum.each(stream, &IO.inspect/1)

# Process
{:ok, task} = Ollixir.chat(client, ..., stream: self())
```

## Structured Output

```elixir
Ollixir.chat(client, ..., format: %{type: "object", properties: %{...}})
```

## Tools

```elixir
Ollixir.chat(client, ..., tools: [%{type: "function", function: %{name: "...", ...}}])
Ollixir.chat(client, ..., tools: [&MyTools.add/2])       # Function → tool
Ollixir.Tool.define(:get_weather, description: "...", parameters: [...])
Ollixir.Web.Tools.all()                                  # Web search/fetch tools
```

## Images (Multimodal)

```elixir
Ollixir.chat(client, ..., messages: [%{role: "user", content: "Describe", images: ["./photo.jpg"]}])
Ollixir.completion(client, ..., images: ["./photo.jpg"])
```

## Options

```elixir
opts = Ollixir.Options.Presets.creative() |> Ollixir.Options.temperature(0.9)
Ollixir.chat(client, ..., options: opts)
```

## Typed Responses

```elixir
Ollixir.chat(client, ..., response_format: :struct)
```

## Web (Cloud API)

```elixir
Ollixir.web_search(client, query: "elixir language")
Ollixir.web_fetch(client, url: "https://elixir-lang.org")
```

## Thinking

```elixir
Ollixir.chat(client, ..., think: true)                   # Basic thinking
Ollixir.chat(client, ..., think: "high")                 # Thinking levels (gpt-oss, etc.)
```

## Embeddings

```elixir
Ollixir.embed(client, model: "nomic-embed-text", input: "text")
Ollixir.embed(client, model: "nomic-embed-text", input: ["text1", "text2"])
Ollixir.embed(client, ..., truncate: true, dimensions: 256)
```

## Model Management

```elixir
Ollixir.list_models(client)                          # List all
Ollixir.list_running(client)                         # Running models
Ollixir.show_model(client, name: "llama3.2")        # Model info
Ollixir.pull_model(client, name: "llama3.2")        # Download
Ollixir.preload(client, model: "llama3.2")          # Load to memory
Ollixir.unload(client, model: "llama3.2")           # Unload
Ollixir.copy_model(client, source: "a", destination: "b")
Ollixir.delete_model(client, name: "model")
```

## Response Fields

| Chat | Completion |
|------|------------|
| `response["message"]["content"]` | `response["response"]` |
| `response["message"]["thinking"]` | `response["thinking"]` |
| `response["message"]["tool_calls"]` | N/A |

## Common Options

| Option | Description |
|--------|-------------|
| `:model` | Model name |
| `:stream` | `true` or `pid` |
| `:format` | `"json"` or schema |
| `:response_format` | `:map` (default) or `:struct` |
| `:think` | Enable thinking (`true` or `"low"|"medium"|"high"`) |
| `:logprobs` | Return token log probabilities |
| `:top_logprobs` | Alternatives per token (0-20) |
| `:suffix` | FIM suffix (completion only) |
| `:dimensions` | Embedding output size (embed only) |
| `:keep_alive` | Memory duration |
| `:options` | Model params |
