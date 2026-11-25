# HuggingFace GGUF Integration Example
#
# This example demonstrates the full integration between:
# - Ollixir.HuggingFace module for discovering GGUF files on HuggingFace
# - Ollixir client for running those models through Ollama
#
# Run with: elixir examples/huggingface/hf_gguf_integration.exs
#
# Prerequisites:
# - Ollama running locally (ollama serve)
# - HF_TOKEN environment variable set (optional, for private repos)

root = Path.expand("../..", __DIR__)

ollixir_dep =
  if File.exists?(Path.join(root, "mix.exs")) do
    {:ollixir, path: root}
  else
    {:ollixir, "~> 0.2.0"}
  end

if Code.ensure_loaded?(Mix.Project) &&
     function_exported?(Mix.Project, :get, 0) &&
     Process.whereis(Mix.ProjectStack) &&
     Mix.Project.get() do
  :ok
else
  Mix.install([ollixir_dep, {:hf_hub, "~> 0.1.3"}])
end

alias Ollixir.HuggingFace

IO.puts("""

╔═══════════════════════════════════════════════════════════════════╗
║          HuggingFace GGUF + Ollama Integration Demo               ║
╠═══════════════════════════════════════════════════════════════════╣
║  This demo shows how to:                                          ║
║  1. Discover GGUF files in HF repos using Ollixir.HuggingFace     ║
║  2. Build Ollama model references from HF repos                   ║
║  3. Auto-select optimal quantization                              ║
║  4. Pull and run HF models directly through Ollama                ║
╚═══════════════════════════════════════════════════════════════════╝
""")

# Initialize Ollixir client
ollama_client = Ollixir.init()

# Example repos with GGUFs (popular community quantizations)
demo_repos = [
  "bartowski/Llama-3.2-1B-Instruct-GGUF",
  "bartowski/Llama-3.2-3B-Instruct-GGUF",
  "TheBloke/Mistral-7B-Instruct-v0.2-GGUF",
  "MaziyarPanahi/Qwen2.5-1.5B-Instruct-GGUF"
]

IO.puts("Demo repositories:")
Enum.each(demo_repos, &IO.puts("  - #{&1}"))

# ============================================================================
# DEMO 1: List GGUF files from a HuggingFace repo
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 1: Discovering GGUF files")
IO.puts(String.duplicate("─", 60))

repo_id = "bartowski/Llama-3.2-1B-Instruct-GGUF"
IO.puts("\nListing GGUF files in #{repo_id}...")

case HuggingFace.list_gguf_files(repo_id) do
  {:ok, ggufs} ->
    IO.puts("\nFound #{length(ggufs)} GGUF files:")

    ggufs
    |> Enum.take(5)
    |> Enum.each(fn gguf ->
      IO.puts("  #{gguf.quantization}: #{gguf.size_gb} GB")
      IO.puts("    File: #{gguf.filename}")
      IO.puts("    Ollama tag: #{repo_id}:#{gguf.ollama_tag}")
    end)

    if length(ggufs) > 5 do
      IO.puts("  ... and #{length(ggufs) - 5} more")
    end

  {:error, reason} ->
    IO.puts("Error listing files: #{inspect(reason)}")
end

# ============================================================================
# DEMO 2: Build Ollama model references
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 2: Building Ollama model references")
IO.puts(String.duplicate("─", 60))

# Default (uses Q4_K_M)
ref1 = HuggingFace.model_ref("bartowski/Llama-3.2-1B-Instruct-GGUF")
IO.puts("\nDefault reference:")
IO.puts("  #{ref1}")

# With specific quantization
ref2 = HuggingFace.model_ref("bartowski/Llama-3.2-1B-Instruct-GGUF", quantization: "Q8_0")
IO.puts("\nWith Q8_0 quantization:")
IO.puts("  #{ref2}")

# Check if it's an HF model
IO.puts("\nModel type checking:")
IO.puts("  hf_model?(\"#{ref2}\"): #{HuggingFace.hf_model?(ref2)}")
IO.puts("  hf_model?(\"llama3.2\"): #{HuggingFace.hf_model?("llama3.2")}")

# Parse a model reference
IO.puts("\nParsing model reference:")
{:ok, parsed} = HuggingFace.parse_model_ref(ref2)
IO.puts("  repo_id: #{parsed.repo_id}")
IO.puts("  quantization: #{parsed.quantization}")

# ============================================================================
# DEMO 3: Auto-select best quantization
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 3: Auto-selecting best quantization")
IO.puts(String.duplicate("─", 60))

IO.puts("\nAuto-selecting from #{repo_id}...")

case HuggingFace.auto_select(repo_id) do
  {:ok, model_ref, info} ->
    IO.puts("\n  Selected: #{info.quantization} (#{info.size_gb} GB)")
    IO.puts("  Model ref: #{model_ref}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

IO.puts("\nWith size constraint (max 0.7 GB)...")

case HuggingFace.auto_select(repo_id, max_size_gb: 0.7) do
  {:ok, model_ref, info} ->
    IO.puts("\n  Selected: #{info.quantization} (#{info.size_gb} GB)")
    IO.puts("  Model ref: #{model_ref}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# ============================================================================
# DEMO 4: Quantization preference
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 4: Quantization preference order")
IO.puts(String.duplicate("─", 60))

prefs = HuggingFace.quant_preference()
IO.puts("\nDefault preference order (first 10):")
prefs |> Enum.take(10) |> Enum.each(&IO.puts("  - #{&1}"))

# Manual best_quantization selection
{:ok, ggufs} = HuggingFace.list_gguf_files(repo_id)
best = HuggingFace.best_quantization(ggufs)
IO.puts("\nBest available: #{best}")

best_small = HuggingFace.best_quantization(ggufs, max_size_gb: 0.7)
IO.puts("Best under 0.7 GB: #{best_small}")

# ============================================================================
# DEMO 5: Running HF model through Ollama (END-TO-END TEST)
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 5: Running HF model through Ollama (END-TO-END)")
IO.puts(String.duplicate("─", 60))

# Use SmolLM2-135M - a tiny model NOT in Ollama's standard library
# This proves we're actually using HuggingFace, not a cached Ollama model
hf_repo = "bartowski/SmolLM2-135M-Instruct-GGUF"

IO.puts("\nDiscovering GGUF files from HuggingFace...")
IO.puts("  Repository: #{hf_repo}")

case HuggingFace.list_gguf_files(hf_repo) do
  {:ok, ggufs} ->
    IO.puts("  Found #{length(ggufs)} GGUF files via hf_hub API")

    # Show available quantizations
    IO.puts("\n  Available quantizations:")

    ggufs
    |> Enum.take(5)
    |> Enum.each(fn g -> IO.puts("    - #{g.quantization}: #{g.size_gb} GB") end)

    # Auto-select best small quantization
    IO.puts("\n  Auto-selecting best quantization under 0.2 GB...")
    best_quant = HuggingFace.best_quantization(ggufs, max_size_gb: 0.2)
    IO.puts("  Selected: #{best_quant}")

    selected = Enum.find(ggufs, fn g -> g.quantization == best_quant end)
    model_ref = HuggingFace.model_ref(hf_repo, quantization: best_quant)

    IO.puts("\n  Model reference: #{model_ref}")
    IO.puts("  File size: #{selected.size_gb} GB")

    # Check if Ollama is running and execute
    case Ollixir.list_models(ollama_client) do
      {:ok, _models} ->
        IO.puts("\n  Ollama is running! Pulling model...")

        # Pull the model with progress
        case HuggingFace.pull(ollama_client, hf_repo, quantization: best_quant, stream: true) do
          {:ok, stream} ->
            stream
            |> Stream.each(fn chunk ->
              case chunk do
                %{"status" => status, "completed" => completed, "total" => total}
                when is_number(completed) and total > 0 ->
                  percent = Float.round(completed / total * 100, 1)
                  IO.write("\r    #{status}: #{percent}%     ")

                %{"status" => status} ->
                  IO.puts("    #{status}")

                _ ->
                  :ok
              end
            end)
            |> Stream.run()

            IO.puts("\n    Pull complete!")

            # Chat with the model
            IO.puts("\n  Chatting with model...")
            messages = [%{role: "user", content: "What is 2 + 2? Reply with just the number."}]

            case HuggingFace.chat(ollama_client, hf_repo, messages, quantization: best_quant) do
              {:ok, response} ->
                content = get_in(response, ["message", "content"])
                IO.puts("    User: What is 2 + 2? Reply with just the number.")
                IO.puts("    Assistant: #{content}")
                IO.puts("\n  END-TO-END TEST PASSED!")

                IO.puts(
                  "  Successfully: discovered via hf_hub -> pulled from HF -> ran inference"
                )

              {:error, reason} ->
                IO.puts("    Chat error: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("    Pull error: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("\n  Ollama is not running: #{inspect(reason)}")
        IO.puts("  Start Ollama with: ollama serve")
        IO.puts("\n  To run this demo manually:")
        IO.puts("    HuggingFace.pull(client, \"#{hf_repo}\", quantization: \"#{best_quant}\")")

        IO.puts(
          "    HuggingFace.chat(client, \"#{hf_repo}\", [%{role: \"user\", content: \"Hi!\"}], quantization: \"#{best_quant}\")"
        )
    end

  {:error, reason} ->
    IO.puts("  Error discovering files: #{inspect(reason)}")
    IO.puts("  (This requires network access to HuggingFace)")
end

# ============================================================================
# DEMO 6: Model info from HuggingFace
# ============================================================================

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("DEMO 6: Model info from HuggingFace")
IO.puts(String.duplicate("─", 60))

IO.puts("\nFetching model info for #{repo_id}...")

case HuggingFace.model_info(repo_id) do
  {:ok, info} ->
    IO.puts("  ID: #{info.id}")
    IO.puts("  Downloads: #{info.downloads}")
    IO.puts("  Likes: #{info.likes}")
    IO.puts("  Tags: #{info.tags |> Enum.take(5) |> Enum.join(", ")}...")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# ============================================================================
# Summary
# ============================================================================

IO.puts("\n" <> String.duplicate("═", 60))
IO.puts("SUMMARY: Ollixir.HuggingFace API")
IO.puts(String.duplicate("═", 60))

IO.puts("""

  Discovery:
    HuggingFace.list_gguf_files(repo_id)
    HuggingFace.model_info(repo_id)

  Selection:
    HuggingFace.auto_select(repo_id, opts)
    HuggingFace.best_quantization(ggufs, opts)
    HuggingFace.quant_preference()

  Model References:
    HuggingFace.model_ref(repo_id, quantization: "Q4_K_M")
    HuggingFace.parse_model_ref("hf.co/repo:Q4_K_M")
    HuggingFace.hf_model?("hf.co/repo:Q4_K_M")

  Ollama Operations:
    HuggingFace.pull(client, repo_id, quantization: "Q4_K_M")
    HuggingFace.chat(client, repo_id, messages, quantization: "Q4_K_M")
    HuggingFace.generate(client, repo_id, prompt, quantization: "Q4_K_M")
    HuggingFace.embed(client, repo_id, input, quantization: "Q4_K_M")

  See guides/huggingface.md for full documentation.
""")

IO.puts("Demo complete!")
