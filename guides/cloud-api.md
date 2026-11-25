# Cloud API

Ollama provides cloud capabilities including web search, web fetch, cloud models,
and a hosted API.

## API Key Setup

Direct hosted calls use an Ollama API key. For cloud inference through a local
server, sign in with `ollama signin`.

1. Create an account at https://ollama.com
2. Generate a key at https://ollama.com/settings/keys
3. Export the key:

```bash
export OLLAMA_API_KEY="your_api_key_here"
```

Client initialization uses `OLLAMA_API_KEY` as the default bearer token. For
local calls that do not need it, initialize with `api_key: nil`.

## Web Search

Search the web and get structured results:

```elixir
{:ok, response} = Ollixir.web_search(client, query: "Elixir programming language")

for result <- response.results do
  IO.puts("#{result.title}")
  IO.puts("  #{result.url}")
  IO.puts("  #{result.content}")
end
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `query` | string | required | Search query |
| `max_results` | integer | 3 | Maximum results to return |

### Response Structure

```elixir
%Ollixir.Web.SearchResponse{
  results: [
    %Ollixir.Web.SearchResult{
      title: "Elixir Programming Language",
      url: "https://elixir-lang.org",
      content: "Elixir is a dynamic, functional language..."
    }
  ]
}
```

## Web Fetch

Fetch and extract content from a URL:

```elixir
{:ok, response} = Ollixir.web_fetch(client, url: "https://elixir-lang.org")

IO.puts("Title: #{response.title}")
IO.puts("Content: #{response.content}")
IO.inspect(response.links, label: "Links")
```

### Response Structure

```elixir
%Ollixir.Web.FetchResponse{
  title: "The Elixir programming language",
  content: "Elixir is a dynamic, functional language...",
  links: ["https://...", "https://..."]
}
```

## Web Tools for Agents

Use web capabilities as tools in agentic workflows.

See `examples/mcp/mcp_server.exs` for an MCP stdio server that exposes
web_search and web_fetch to MCP clients (Cursor, Cline, Open WebUI, etc.).

```elixir
# Get predefined web tool definitions
tools = Ollixir.Web.Tools.all()

{:ok, response} = Ollixir.chat(client,
  model: "llama3.2",
  messages: [
    %{role: "user", content: "Search for the latest Elixir news"}
  ],
  tools: tools
)

# Handle tool calls
case get_in(response, ["message", "tool_calls"]) do
  [%{"function" => %{"name" => "web_search", "arguments" => args}}] ->
    query = args["query"]
    {:ok, results} = Ollixir.web_search(client, query: query)
    # Continue conversation with results...

  _ ->
    response["message"]["content"]
end
```

## Cloud Models

Cloud models run on Ollama's infrastructure while using your local client.

### Setup

1. Sign in (one-time):

```bash
ollama signin
```

2. Pull a cloud model:

```bash
ollama pull gpt-oss:120b-cloud
```

3. Use it like any local model:

```elixir
client = Ollixir.init()

{:ok, response} = Ollixir.chat(client,
  model: "gpt-oss:120b-cloud",
  messages: [%{role: "user", content: "Explain quantum computing."}]
)
```

### Available Cloud Models

Browse the [Ollama Cloud model catalog](https://ollama.com/search?c=cloud)
for current tags, model capabilities, and availability.

### Cloud Models with Streaming

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "gpt-oss:120b-cloud",
  messages: [%{role: "user", content: "Write a haiku about Elixir."}],
  stream: true
)

stream
|> Stream.each(fn chunk ->
  IO.write(get_in(chunk, ["message", "content"]) || "")
end)
|> Stream.run()
```

## Hosted API (ollama.com)

Use the Ollama-hosted API directly instead of a local server:

```elixir
# Point client at hosted API
client = Ollixir.init("https://ollama.com")

{:ok, response} = Ollixir.chat(client,
  model: "gpt-oss:120b",  # Note: no :cloud suffix for hosted API
  messages: [%{role: "user", content: "Hello!"}]
)
```

### List Available Models

```bash
curl -H "Authorization: Bearer $OLLAMA_API_KEY" https://ollama.com/api/tags
```

### Custom Headers

Override the default authorization:

```elixir
client = Ollixir.init(host: "https://ollama.com",
  headers: [{"authorization", "Bearer your_api_key_here"}]
)
```

Hosted web calls use the environment key only for `https://ollama.com`,
credentials on a client for that same origin, or an explicit `api_key:` on
the operation. A custom web base URL does not inherit a different origin's
credentials. Ollixir routes return redirect responses to the caller without following them.
For a locally signed-in Ollama server, use `web_search_experimental/2` and
`web_fetch_experimental/2` rather than forwarding hosted credentials.

## Cloud vs Local Comparison

| Feature | Local Ollama | Cloud Models | Hosted API |
|---------|--------------|--------------|------------|
| Server | Your machine | Your machine | ollama.com |
| Models | Downloaded | Streamed | Remote |
| Authentication | Depends on deployment | Local server sign-in | Bearer token |
| Model Size | Limited by hardware | Very large | Very large |

## Error Handling

### Missing API Key

```elixir
case Ollixir.web_search(client, query: "test") do
  {:ok, response} ->
    response

  {:error, %Ollixir.RequestError{reason: reason}}
  when reason in [:missing_api_key, :invalid_api_key] ->
    IO.puts("Configure a bearer token with OLLAMA_API_KEY or api_key.")

  {:error, %Ollixir.ResponseError{status: 401}} ->
    IO.puts("The hosted API rejected the bearer token.")

  {:error, %Ollixir.ResponseError{status: 403}} ->
    IO.puts("API key lacks permission for this operation.")

  {:error, error} ->
    IO.puts("Request failed: #{inspect(error)}")
end
```

### Validate API Key

```bash
curl -H "Authorization: Bearer $OLLAMA_API_KEY" https://ollama.com/api/tags
```

## Rate Limiting

Cloud APIs may have rate limits. Implement backoff:

```elixir
defmodule CloudClient do
  def search_with_retry(client, query, retries \\ 3) do
    case Ollixir.web_search(client, query: query) do
      {:ok, response} ->
        {:ok, response}

      {:error, %Ollixir.ResponseError{status: 429}} when retries > 0 ->
        Process.sleep(1000 * (4 - retries))
        search_with_retry(client, query, retries - 1)

      {:error, error} ->
        {:error, error}
    end
  end
end
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OLLAMA_HOST` | Default server URL |
| `OLLAMA_API_KEY` | Bearer token for cloud features |

## Testing Cloud Features

Cloud tests are tagged and excluded by default:

```bash
# Run cloud tests after setting API key
mix test test/ollixir/web_cloud_test.exs --include cloud_api
```

## See Also

- [Getting Started](getting-started.md) - Basic setup
- [Tools Guide](tools.md) - Using web tools in agents
- [Ollama Server Setup](ollama-setup.md) - Local and cloud setup

## Configured-server cloud operations

Ollixir 0.2.0 also supports experimental web search/fetch through the configured
server (`web_search_experimental/2`, `web_fetch_experimental/2`). These are
separate from the hosted `web_search/2` and `web_fetch/2` calls described above.
Use the [Server and Account guide](server-and-account.md) for account status,
usage, balance, sign-in errors and experimental routes.
