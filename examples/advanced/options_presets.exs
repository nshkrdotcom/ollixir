# Options and Presets Example
# Run with: elixir examples/advanced/options_presets.exs

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

opts =
  Ollixir.Options.Presets.creative()
  |> Ollixir.Options.temperature(0.9)
  |> Ollixir.Options.top_p(0.95)

{:ok, response} =
  Ollixir.chat(client,
    model: "llama3.2",
    messages: [%{role: "user", content: "Write a playful haiku about rain."}],
    options: opts
  )

IO.puts(response["message"]["content"])
