# JSON Format Example
# Run with: elixir examples/structured/json_format.exs

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
      %{role: "user", content: "Return a JSON object with keys name and capital for Canada."}
    ],
    format: "json"
  )

json = response["message"]["content"]

case Jason.decode(json) do
  {:ok, data} -> IO.inspect(data, label: "Decoded JSON")
  {:error, reason} -> IO.puts("Failed to parse JSON: #{inspect(reason)}")
end
