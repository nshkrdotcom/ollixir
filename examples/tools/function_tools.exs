# Function Tool Conversion Example
# Run with: elixir examples/tools/function_tools.exs

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

defmodule MathTools do
  @doc "Add two integers together."
  @spec add(integer(), integer()) :: integer()
  def add(a, b), do: a + b
end

client = Ollixir.init()

{:ok, response} =
  Ollixir.chat(client,
    model: "llama3.2",
    messages: [%{role: "user", content: "Add 4 and 7"}],
    tools: [&MathTools.add/2]
  )

case get_in(response, ["message", "tool_calls"]) do
  nil ->
    IO.puts("No tool call: #{response["message"]["content"]}")

  tool_calls ->
    IO.inspect(tool_calls, label: "Tool calls")
end
