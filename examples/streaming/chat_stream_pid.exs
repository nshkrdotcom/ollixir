# Streaming Chat to Process (PID) Example
# Run with: elixir examples/streaming/chat_stream_pid.exs

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

{:ok, task} =
  Ollixir.chat(client,
    model: "llama3.2",
    messages: [%{role: "user", content: "Tell me a short story about a lighthouse."}],
    stream: self()
  )

receive_chunks = fn receive_chunks, acc ->
  receive do
    {_pid, {:data, %{"done" => false} = chunk}} ->
      content = get_in(chunk, ["message", "content"]) || ""
      IO.write(content)
      receive_chunks.(receive_chunks, acc <> content)

    {_pid, {:data, %{"done" => true}}} ->
      IO.puts("\n\n=== Complete ===")
      acc
  after
    60_000 ->
      IO.puts("\nTimed out waiting for response.")
      acc
  end
end

_content = receive_chunks.(receive_chunks, "")

Task.await(task, 60_000)
