# HuggingFace Integration

Run any of the 45,000+ GGUF models on HuggingFace Hub directly through Ollama.
The `Ollixir.HuggingFace` module provides discovery, selection, and convenience
functions for working with HuggingFace models.

## Installation

The HuggingFace integration requires the `hf_hub` package. This is an **optional
dependency** - you only need to add it if you want to use the `Ollixir.HuggingFace`
module for model discovery and auto-selection.

Add `hf_hub` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:ollixir, "~> 0.1.1"},
    {:hf_hub, "~> 0.1.3"}  # Required for Ollixir.HuggingFace module
  ]
end
```

Then run:

```bash
mix deps.get
```

> #### Note {: .info}
>
> If you don't need the discovery features and already know the repository and
> quantization you want, you can skip `hf_hub` entirely and use Ollama directly
> with the `hf.co/{repo}:{quantization}` model format. See [Direct Ollama Usage](#direct-ollama-usage).

## Overview

Ollama natively supports HuggingFace models using the `hf.co/{repo}:{quantization}`
format. This module adds:

| Feature | Function | Description |
|---------|----------|-------------|
| Discovery | `list_gguf_files/2` | Find available GGUF files and quantizations |
| Selection | `auto_select/2` | Auto-pick best quantization for your hardware |
| Convenience | `chat/4`, `pull/3` | Wrappers that build correct model references |
| Metadata | `model_info/2` | Get downloads, tags, and other model info |

## Quick Start

```elixir
client = Ollixir.init()

# Option 1: Direct (if you know the repo and quantization)
{:ok, response} = Ollixir.chat(client,
  model: "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M",
  messages: [%{role: "user", content: "Hello!"}]
)

# Option 2: With discovery and auto-selection
alias Ollixir.HuggingFace

{:ok, model_ref, info} = HuggingFace.auto_select("bartowski/Llama-3.2-1B-Instruct-GGUF")
# => {:ok, "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M", %{size_gb: 0.75, ...}}

{:ok, response} = HuggingFace.chat(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  [%{role: "user", content: "Hello!"}],
  quantization: "Q4_K_M"
)
```

## Discovering Available Models

### Listing GGUF Files

Find all GGUF files in a HuggingFace repository:

```elixir
{:ok, ggufs} = Ollixir.HuggingFace.list_gguf_files("bartowski/Llama-3.2-1B-Instruct-GGUF")

# Returns a list sorted by size:
# [
#   %{filename: "Llama-3.2-1B-Instruct-IQ3_M.gguf", size_gb: 0.61, quantization: "IQ3_M", ...},
#   %{filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf", size_gb: 0.75, quantization: "Q4_K_M", ...},
#   %{filename: "Llama-3.2-1B-Instruct-Q8_0.gguf", size_gb: 1.23, quantization: "Q8_0", ...},
#   ...
# ]
```

Each entry contains:
- `filename` - Full filename in the repository
- `size_bytes` - File size in bytes
- `size_gb` - File size in gigabytes
- `quantization` - Extracted quantization type (e.g., "Q4_K_M")
- `ollama_tag` - Tag to use with Ollama (uppercase quantization)

### Getting Model Metadata

```elixir
{:ok, info} = Ollixir.HuggingFace.model_info("bartowski/Llama-3.2-1B-Instruct-GGUF")

IO.puts("Downloads: #{info.downloads}")
IO.puts("Tags: #{Enum.join(info.tags, ", ")}")
```

## Quantization Selection

### Understanding Quantization Types

| Type | Size | Quality | Use Case |
|------|------|---------|----------|
| Q4_K_M | ~4 bits | Good | Best balance for most users |
| Q4_K_S | ~4 bits | Good | Slightly smaller than Q4_K_M |
| Q5_K_M | ~5 bits | Better | Higher quality, moderate size |
| Q6_K | ~6 bits | High | Near-original quality |
| Q8_0 | 8 bits | Very High | Minimal quality loss |
| IQ3_M | ~3 bits | Lower | For constrained environments |
| IQ4_XS | ~4 bits | Good | Smallest with decent quality |
| F16 | 16 bits | Original | Full precision, largest |

### Auto-Selection

Let the library pick the best available quantization:

```elixir
# Default: picks Q4_K_M if available, then next best
{:ok, model_ref, info} = Ollixir.HuggingFace.auto_select("bartowski/Llama-3.2-1B-Instruct-GGUF")

# With size constraint (e.g., only 1GB available)
{:ok, model_ref, info} = Ollixir.HuggingFace.auto_select("bartowski/Llama-3.2-1B-Instruct-GGUF",
  max_size_gb: 1.0
)

# Force specific quantization
{:ok, model_ref, info} = Ollixir.HuggingFace.auto_select("bartowski/Llama-3.2-1B-Instruct-GGUF",
  quantization: "Q8_0"
)
```

### Manual Selection

```elixir
{:ok, ggufs} = Ollixir.HuggingFace.list_gguf_files("bartowski/Llama-3.2-1B-Instruct-GGUF")

# Find best quantization from available options
best = Ollixir.HuggingFace.best_quantization(ggufs)
# => "Q4_K_M"

# With size constraint
best = Ollixir.HuggingFace.best_quantization(ggufs, max_size_gb: 0.7)
# => "IQ3_M" (if Q4_K_M is too large)

# Custom preference order
best = Ollixir.HuggingFace.best_quantization(ggufs, preference: ["Q8_0", "Q6_K", "Q5_K_M"])
```

## Building Model References

### Programmatic Reference Building

```elixir
# Without quantization (Ollama picks default, usually Q4_K_M)
ref = Ollixir.HuggingFace.model_ref("bartowski/Llama-3.2-1B-Instruct-GGUF")
# => "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF"

# With specific quantization
ref = Ollixir.HuggingFace.model_ref("bartowski/Llama-3.2-1B-Instruct-GGUF", quantization: "Q8_0")
# => "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q8_0"
```

### Parsing Model References

```elixir
{:ok, parsed} = Ollixir.HuggingFace.parse_model_ref("hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M")
# => %{repo_id: "bartowski/Llama-3.2-1B-Instruct-GGUF", quantization: "Q4_K_M"}

# Check if a model is from HuggingFace
Ollixir.HuggingFace.hf_model?("hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M")
# => true

Ollixir.HuggingFace.hf_model?("llama3.2")
# => false
```

## Using HuggingFace Models

### Pulling Models

```elixir
client = Ollixir.init()

# Pull with specific quantization
{:ok, _} = Ollixir.HuggingFace.pull(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  quantization: "Q4_K_M"
)

# Pull with streaming progress
{:ok, stream} = Ollixir.HuggingFace.pull(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  quantization: "Q4_K_M",
  stream: true
)

stream
|> Stream.each(fn chunk ->
  case chunk do
    %{"completed" => completed, "total" => total} when total > 0 ->
      IO.write("\rProgress: #{Float.round(completed / total * 100, 1)}%")
    %{"status" => status} ->
      IO.puts(status)
    _ -> :ok
  end
end)
|> Stream.run()
```

### Chat

```elixir
{:ok, response} = Ollixir.HuggingFace.chat(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  [%{role: "user", content: "What is the capital of France?"}],
  quantization: "Q4_K_M"
)

IO.puts(response["message"]["content"])

# With streaming
{:ok, stream} = Ollixir.HuggingFace.chat(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  [%{role: "user", content: "Tell me a story"}],
  quantization: "Q4_K_M",
  stream: true
)

Enum.each(stream, fn chunk ->
  if content = get_in(chunk, ["message", "content"]), do: IO.write(content)
end)
```

### Generate (Completion)

```elixir
{:ok, response} = Ollixir.HuggingFace.generate(client, "bartowski/Llama-3.2-1B-Instruct-GGUF",
  "The quick brown fox",
  quantization: "Q4_K_M"
)

IO.puts(response["response"])
```

### Embeddings

```elixir
# Use an embedding model from HuggingFace
{:ok, response} = Ollixir.HuggingFace.embed(client, "nomic-ai/nomic-embed-text-v1.5-GGUF",
  "Hello world",
  quantization: "Q4_K_M"
)

embeddings = response["embeddings"]
```

## Private Repositories

To access private HuggingFace repositories, set your HuggingFace token:

```bash
export HF_TOKEN="hf_..."
```

Or configure in your application:

```elixir
# config/config.exs
config :hf_hub,
  token: System.get_env("HF_TOKEN")
```

Then use normally:

```elixir
{:ok, ggufs} = Ollixir.HuggingFace.list_gguf_files("your-org/private-model")
```

## Popular GGUF Repositories

Community members maintain high-quality GGUF quantizations:

| Maintainer | Repository Pattern | Known For |
|------------|-------------------|-----------|
| bartowski | `bartowski/{model}-GGUF` | Comprehensive quant coverage |
| TheBloke | `TheBloke/{model}-GGUF` | Wide model variety |
| MaziyarPanahi | `MaziyarPanahi/{model}-GGUF` | Latest models |

Browse all GGUF models: https://huggingface.co/models?library=gguf

## Complete Example

```elixir
defmodule MyApp.HuggingFaceChat do
  alias Ollixir.HuggingFace

  def run do
    client = Ollixir.init()
    repo = "bartowski/Llama-3.2-1B-Instruct-GGUF"

    # 1. Discover available quantizations
    IO.puts("Discovering available models...")
    {:ok, ggufs} = HuggingFace.list_gguf_files(repo)

    IO.puts("\nAvailable quantizations:")
    for gguf <- ggufs do
      IO.puts("  #{gguf.quantization}: #{gguf.size_gb} GB")
    end

    # 2. Auto-select best option
    {:ok, model_ref, selected} = HuggingFace.auto_select(repo, max_size_gb: 1.0)
    IO.puts("\nSelected: #{selected.quantization} (#{selected.size_gb} GB)")

    # 3. Pull the model
    IO.puts("\nPulling model...")
    {:ok, _} = HuggingFace.pull(client, repo, quantization: selected.quantization)

    # 4. Chat
    IO.puts("\nChatting...")
    {:ok, response} = HuggingFace.chat(client, repo,
      [%{role: "user", content: "What is 2 + 2?"}],
      quantization: selected.quantization
    )

    IO.puts("Response: #{response["message"]["content"]}")
  end
end
```

## Direct Ollixir Usage

If you already know the repository and quantization, you can skip this module
entirely and use Ollixir directly:

```elixir
client = Ollixir.init()

# Pull
Ollixir.pull_model(client, name: "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M")

# Chat
Ollixir.chat(client,
  model: "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M",
  messages: [%{role: "user", content: "Hello!"}]
)

# Generate
Ollixir.generate(client,
  model: "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M",
  prompt: "Hello"
)
```

The `Ollixir.HuggingFace` module is most useful when you need to:
- Discover what's available in a repository
- Auto-select based on hardware constraints
- Get model metadata
- Access private repositories with authentication
