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
{:ok, %{"models" => models}} = Ollixir.list_models(client)

for model <- models do
  size_gb = model["size"] / 1_000_000_000
  IO.puts("#{model["name"]} (#{Float.round(size_gb, 2)} GB)")
end
