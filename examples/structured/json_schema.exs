# JSON Schema Structured Output
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

country_schema = %{
  type: "object",
  properties: %{
    name: %{type: "string"},
    capital: %{type: "string"},
    population: %{type: "integer"},
    languages: %{type: "array", items: %{type: "string"}},
    continent: %{type: "string"}
  },
  required: ["name", "capital", "population", "languages", "continent"]
}

{:ok, response} =
  Ollixir.chat(client,
    model: "llama3.2",
    messages: [%{role: "user", content: "Tell me about Japan"}],
    format: country_schema
  )

json_content = response["message"]["content"]

case Jason.decode(json_content) do
  {:ok, country} ->
    IO.inspect(country, label: "Structured Country Data")

  {:error, _} ->
    IO.puts("Model returned non-JSON output:")
    IO.puts(json_content)
end
