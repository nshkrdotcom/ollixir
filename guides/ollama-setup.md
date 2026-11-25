# Ollama Server Setup

For a pinned, isolated release test server, see [Live Release Validation](live-validation.md).

This guide covers installing Ollama, running the local server, pulling models,
and connecting to local or cloud endpoints from the Elixir client.

## Install Ollama

### macOS and Windows

Download the installer for your platform:

- https://ollama.com/download

### Linux (quick install)

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### Linux installation and service management

The [official Linux guide](https://docs.ollama.com/linux) covers manual
installation, architecture-specific bundles, GPU drivers, systemd, upgrades,
and uninstalling. For release validation, use the isolated setup linked above.
It verifies the exact bundle, uses a separate model store, and runs alongside
an existing system service.

## Start the Server

If you are not using systemd, start manually:

```bash
ollama serve
```

The default base URL is `http://localhost:11434`.

## Pull a Model

```bash
ollama pull llama3.2
```

For examples, also pull:

```bash
ollama pull nomic-embed-text
ollama pull llava
ollama pull deepseek-r1:1.5b
```

Thinking examples use `deepseek-r1:1.5b`, which supports `think`.

Browse models:

- https://ollama.com/search

List local models:

```bash
ollama list
```

## Connect from Elixir

By default, the client targets `http://localhost:11434`:

```elixir
client = Ollixir.init()
```

Override the host with `OLLAMA_HOST`:

```bash
export OLLAMA_HOST="http://ollama.internal:11434"
```

Or pass the URL directly:

```elixir
client = Ollixir.init("http://ollama.internal:11434")
```

## Cloud Models (via Local Ollama)

Cloud models let you run larger models while keeping the same local workflow.
See https://ollama.com/search?c=cloud for the latest list.

1) Sign in (one time):

```bash
ollama signin
```

2) Pull a cloud model:

```bash
ollama pull gpt-oss:120b-cloud
```

3) Use it like any other model:

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "gpt-oss:120b-cloud",
  messages: [%{role: "user", content: "Why is the sky blue?"}],
  stream: true
)

stream
|> Stream.each(fn chunk ->
  IO.write(get_in(chunk, ["message", "content"]) || "")
end)
|> Stream.run()
```

## Cloud API (ollama.com)

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

### Web search/fetch (requires API key)

`web_search/2` and `web_fetch/2` always call the hosted API and require
`OLLAMA_API_KEY`. If the key is missing, these examples will skip; if the key
is invalid, the API will return 401/403.

You can validate the key with:

```bash
curl -H "Authorization: Bearer $OLLAMA_API_KEY" https://ollama.com/api/tags
```

### Cloud test runs (optional)

Cloud tests are tagged and excluded by default. After setting
`OLLAMA_API_KEY`, you can run:

```bash
mix test --include cloud_api
```

## Troubleshooting

- `Ollixir.ConnectionError`: ensure `ollama serve` is running and reachable.
  The error message includes a download link if Ollama is not installed.
- Wrong host/port: set `OLLAMA_HOST` or pass a URL to `Ollixir.init/1`.
- Auth errors: confirm your API key and target host.

## Next Steps

- [Getting Started](getting-started.md)
- [Streaming](streaming.md)
- [Tools](tools.md)
- [Structured Outputs](structured-outputs.md)
- [Cloud API](cloud-api.md) - Web search and cloud models
- [Examples](../examples/README.md)
