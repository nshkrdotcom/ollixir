# Web Search Example (Cloud API)
# Run with: elixir examples/web/web_search.exs

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

if System.get_env("OLLAMA_API_KEY") in [nil, ""] do
  IO.puts("""
  Skipping web search. Set OLLAMA_API_KEY to run this example.

  1) Create an account at https://ollama.com
  2) Generate a key at https://ollama.com/settings/keys
  3) export OLLAMA_API_KEY="your_key_here"
  """)

  System.halt(0)
end

case Ollixir.web_search(client, query: "Elixir language release notes", max_results: 3) do
  {:ok, response} ->
    IO.puts("Results:")

    for result <- response.results do
      IO.puts("- #{result.title} (#{result.url})")
    end

  {:error, error} when is_struct(error, Ollixir.ResponseError) and error.status in [401, 403] ->
    IO.puts("""
    Web search failed: #{Exception.message(error)}

    The API key appears to be invalid. Create a new key:
    https://ollama.com/settings/keys
    """)

  {:error, error} ->
    IO.puts("Web search failed: #{inspect(error)}")
end
