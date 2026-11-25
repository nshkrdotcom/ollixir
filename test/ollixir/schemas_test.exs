defmodule Ollixir.SchemasTest do
  use Supertester.ExUnitFoundation, isolation: :basic

  describe "chat schema validation" do
    test "requires model parameter" do
      assert {:error, _} =
               NimbleOptions.validate(
                 [
                   messages: [%{role: "user", content: "Hi"}]
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end

    test "defaults messages to an empty list for preload" do
      assert {:ok, opts} =
               NimbleOptions.validate(
                 [
                   model: "llama2"
                 ],
                 Ollixir.Schemas.schema(:chat)
               )

      assert opts[:messages] == []
    end

    test "validates stream option type" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [%{role: "user", content: "Hi"}],
                   stream: true
                 ],
                 Ollixir.Schemas.schema(:chat)
               )

      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [%{role: "user", content: "Hi"}],
                   stream: self()
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end

    test "validates think option accepts boolean and strings" do
      for think_val <- [true, false, "low", "medium", "high"] do
        assert {:ok, _} =
                 NimbleOptions.validate(
                   [
                     model: "llama2",
                     messages: [%{role: "user", content: "Hi"}],
                     think: think_val
                   ],
                   Ollixir.Schemas.schema(:chat)
                 )
      end
    end

    test "validates logprobs is boolean" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [%{role: "user", content: "Hi"}],
                   logprobs: true
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end

    test "validates top_logprobs is integer" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [%{role: "user", content: "Hi"}],
                   top_logprobs: 5
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end

    test "allows message without content" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [
                     %{
                       role: "assistant",
                       tool_calls: [%{function: %{name: "noop", arguments: %{}}}]
                     }
                   ]
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end

    test "allows tool_name in messages" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "llama2",
                   messages: [%{role: "tool", tool_name: "lookup", content: "ok"}]
                 ],
                 Ollixir.Schemas.schema(:chat)
               )
    end
  end

  describe "completion schema validation" do
    test "requires model parameter" do
      assert {:error, _} =
               NimbleOptions.validate(
                 [
                   prompt: "Hello"
                 ],
                 Ollixir.Schemas.schema(:completion)
               )
    end

    test "validates suffix parameter" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "codellama",
                   prompt: "def add(",
                   suffix: ")"
                 ],
                 Ollixir.Schemas.schema(:completion)
               )
    end
  end

  describe "embed schema validation" do
    test "validates dimensions parameter" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   model: "nomic-embed-text",
                   input: "Hello",
                   dimensions: 256
                 ],
                 Ollixir.Schemas.schema(:embed)
               )
    end
  end

  describe "tool schema validation" do
    test "allows custom tool types" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   type: "custom_type",
                   function: %{name: "custom", parameters: %{}}
                 ],
                 Ollixir.Schemas.schema(:tool_def)
               )
    end

    test "defaults tool type to function when missing" do
      assert {:ok, opts} =
               NimbleOptions.validate(
                 [
                   function: %{name: "defaulted", parameters: %{}}
                 ],
                 Ollixir.Schemas.schema(:tool_def)
               )

      assert Keyword.get(opts, :type) == "function"
    end
  end

  describe "model transfer schema validation" do
    test "accepts insecure for pull_model" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   name: "llama2",
                   insecure: true
                 ],
                 Ollixir.Schemas.schema(:pull_model)
               )
    end

    test "accepts insecure for push_model" do
      assert {:ok, _} =
               NimbleOptions.validate(
                 [
                   name: "llama2",
                   insecure: true
                 ],
                 Ollixir.Schemas.schema(:push_model)
               )
    end
  end
end
