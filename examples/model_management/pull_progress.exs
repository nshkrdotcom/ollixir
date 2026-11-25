# Pull Model with Progress Example
# Run with: elixir examples/model_management/pull_progress.exs

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

IO.puts("Pulling #{model} (this may take a while on first run)...")

{:ok, stream} = Ollixir.pull_model(client, name: model, stream: true)

stream
|> Stream.each(fn chunk ->
  status = chunk["status"] || "working"

  line =
    case {chunk["completed"], chunk["total"]} do
      {completed, total} when is_number(completed) and is_number(total) and total > 0 ->
        percent = Float.round(completed / total * 100, 1)
        "#{status} (#{percent}%)"

      _ ->
        status
    end

  IO.puts(line)
end)
|> Stream.run()

IO.puts("Done.")
