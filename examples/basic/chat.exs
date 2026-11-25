# Basic Chat Example
# Run with: elixir examples/basic/chat.exs

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

{:ok, response} =
  Ollixir.chat(client,
    model: "llama3.2",
    messages: [
      %{role: "user", content: "Why is the sky blue?"}
    ]
  )

IO.puts(response["message"]["content"])
