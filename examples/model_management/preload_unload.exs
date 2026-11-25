# Preload/Unload Example
# Run with: elixir examples/model_management/preload_unload.exs

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
  Mix.install([ollixir_dep])
end

client = Ollixir.init()
model = "llama3.2"

case Ollixir.preload(client, model: model) do
  {:ok, true} -> IO.puts("Preloaded #{model}")
  {:ok, false} -> IO.puts("Model not found: #{model}")
  {:error, err} -> IO.puts("Preload failed: #{inspect(err)}")
end

case Ollixir.unload(client, model: model) do
  {:ok, true} -> IO.puts("Unloaded #{model}")
  {:ok, false} -> IO.puts("Model not found: #{model}")
  {:error, err} -> IO.puts("Unload failed: #{inspect(err)}")
end
