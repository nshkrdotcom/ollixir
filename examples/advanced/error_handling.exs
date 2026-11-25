# Error Handling Example
# Run with: elixir examples/advanced/error_handling.exs

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

IO.puts("=== Request Error Example ===")

case Ollixir.chat(client, model: "llama3.2", messages: "not-a-list") do
  {:error, error} when is_struct(error, Ollixir.RequestError) ->
    IO.puts("RequestError: #{Exception.message(error)}")

  other ->
    IO.inspect(other)
end

IO.puts("\n=== Response Error Example ===")

case Ollixir.chat(client, model: "not-found", messages: [%{role: "user", content: "Hi"}]) do
  {:error, error} when is_struct(error, Ollixir.ResponseError) ->
    IO.puts("ResponseError: #{Exception.message(error)}")
    IO.puts("Retryable? #{Ollixir.Errors.retryable?(error)}")

  other ->
    IO.inspect(other)
end
