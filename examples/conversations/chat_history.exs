# Multi-turn Conversation Example
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

defmodule Conversation do
  def run do
    client = Ollixir.init()
    loop(client, [])
  end

  defp loop(client, messages) do
    IO.write("You: ")

    input =
      case IO.gets("") do
        :eof -> "quit"
        {:error, _} -> "quit"
        data -> String.trim(data)
      end

    if input == "quit" do
      IO.puts("Goodbye!")
    else
      messages = messages ++ [%{role: "user", content: input}]

      {:ok, response} =
        Ollixir.chat(client,
          model: "llama3.2",
          messages: messages
        )

      assistant_content = response["message"]["content"]
      IO.puts("\nAssistant: #{assistant_content}\n")

      messages = messages ++ [%{role: "assistant", content: assistant_content}]
      loop(client, messages)
    end
  end
end

Conversation.run()
