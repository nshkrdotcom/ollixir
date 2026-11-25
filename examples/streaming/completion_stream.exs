# Streaming Completion Example
# Run with: elixir examples/streaming/completion_stream.exs

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

{:ok, stream} =
  Ollixir.completion(client,
    model: "llama3.2",
    prompt: "Write a short poem about the ocean.",
    stream: true
  )

stream
|> Stream.each(fn chunk ->
  if content = chunk["response"] do
    IO.write(content)
  end
end)
|> Stream.run()

IO.puts("")
