# Live test: Pull and chat with an HF GGUF model through Ollama
#
# This actually pulls a small model and chats with it using Ollixir.HuggingFace.
# Run with: elixir examples/huggingface/hf_live_test.exs

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

IO.puts("=== HuggingFace GGUF Live Test ===\n")

client = Ollixir.init()

# Use the smallest reasonable quantization of a small model
# bartowski/Llama-3.2-1B-Instruct-GGUF:IQ4_XS is ~0.69 GB
repo = "bartowski/Llama-3.2-1B-Instruct-GGUF"
quant = "IQ4_XS"

IO.puts("Repository: #{repo}")
IO.puts("Quantization: #{quant}")
IO.puts("Model ref: #{HuggingFace.model_ref(repo, quantization: quant)}")
IO.puts("This will download ~0.69 GB on first run.\n")

# Step 1: Pull the model
IO.puts("Step 1: Pulling model...")

case HuggingFace.pull(client, repo, quantization: quant, stream: true) do
  {:ok, stream} ->
    stream
    |> Stream.each(fn chunk ->
      case chunk do
        %{"status" => status, "completed" => completed, "total" => total}
        when is_number(completed) and total > 0 ->
          percent = Float.round(completed / total * 100, 1)
          IO.write("\r  #{status}: #{percent}%    ")

        %{"status" => status} ->
          IO.puts("  #{status}")

        _ ->
          :ok
      end
    end)
    |> Stream.run()

    IO.puts("\n  Pull complete!")

  {:error, reason} ->
    IO.puts("  Pull error: #{inspect(reason)}")
    System.halt(1)
end

# Step 2: Chat with the model
IO.puts("\nStep 2: Chatting with model...")

messages = [
  %{role: "user", content: "What is 2 + 2? Answer in one word."}
]

case HuggingFace.chat(client, repo, messages, quantization: quant) do
  {:ok, response} ->
    content = get_in(response, ["message", "content"])
    IO.puts("  Response: #{content}")

  {:error, reason} ->
    IO.puts("  Chat error: #{inspect(reason)}")
end

# Step 3: Streaming test
IO.puts("\nStep 3: Streaming test...")
IO.write("  Response: ")

messages2 = [
  %{role: "user", content: "Count from 1 to 5, one number per line."}
]

case HuggingFace.chat(client, repo, messages2, quantization: quant, stream: true) do
  {:ok, stream} ->
    stream
    |> Stream.each(fn chunk ->
      if content = get_in(chunk, ["message", "content"]) do
        IO.write(content)
      end
    end)
    |> Stream.run()

    IO.puts("\n")

  {:error, reason} ->
    IO.puts("\n  Stream error: #{inspect(reason)}")
end

# Step 4: Generate (completion) test
IO.puts("Step 4: Generate test...")

case HuggingFace.generate(client, repo, "Hello, my name is", quantization: quant) do
  {:ok, response} ->
    IO.puts("  Response: #{response["response"]}")

  {:error, reason} ->
    IO.puts("  Generate error: #{inspect(reason)}")
end

IO.puts("\n=== Test complete! ===")
