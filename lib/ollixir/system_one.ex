defmodule Ollixir.SystemOne do
  @moduledoc """
  Builds requests for Ollama's `/v1/systemone` decision-model endpoint.

  Use a list of `{name, question}` pairs to control question order; it is
  encoded as a JSON object, not an array. Maps are accepted when order is
  immaterial. Question criteria may also be `Jason.OrderedObject` values.
  """

  alias Ollixir.RequestError

  @doc false
  def normalize(params) do
    with :ok <- videos(params[:videos]),
         :ok <- optional_content(params[:state], :state),
         {:ok, questions} <- questions(params[:questions]) do
      {:ok, Keyword.put(params, :questions, questions)}
    end
  end

  defp questions(questions) when is_map(questions) and not is_struct(questions),
    do: questions(Map.to_list(questions))

  defp questions(%Jason.OrderedObject{values: pairs}), do: questions(pairs)

  defp questions(pairs) when is_list(pairs) and length(pairs) in 1..64 do
    pairs
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn
      {name, question}, {:ok, acc, seen} when is_binary(name) or is_atom(name) ->
        name = to_string(name)

        with false <- String.trim(name) == "" or MapSet.member?(seen, name),
             {:ok, question} <- normalize_question(question) do
          {:cont, {:ok, [{name, question} | acc], MapSet.put(seen, name)}}
        else
          true -> {:halt, invalid(:questions, "Question names must be nonempty and unique")}
          error -> {:halt, error}
        end

      _, _ ->
        {:halt, invalid(:questions, "Expected named question pairs")}
    end)
    |> case do
      {:ok, pairs, _} -> {:ok, Jason.OrderedObject.new(Enum.reverse(pairs))}
      error -> error
    end
  end

  defp questions(_), do: invalid(:questions, "Expected an object containing 1 to 64 questions")

  defp normalize_question(question) when is_map(question) and not is_struct(question) do
    type = Map.get(question, :type, question["type"])
    instructions = Map.get(question, :instructions, question["instructions"])
    criteria = Map.get(question, :criteria, question["criteria"])

    with :ok <- optional_content(instructions, :instructions),
         :ok <- criteria(type, criteria) do
      result =
        %{type: type, instructions: instructions, criteria: criteria}
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, result}
    end
  end

  defp normalize_question(_), do: invalid(:questions, "Question must be an object")

  defp criteria("noul", nil), do: :ok

  defp criteria(type, %Jason.OrderedObject{values: pairs}) when type in ["noul", "choice"],
    do: object_criteria(type, pairs)

  defp criteria(type, value)
       when type in ["noul", "choice"] and is_map(value) and not is_struct(value),
       do: object_criteria(type, Map.to_list(value))

  defp criteria("score", value) when is_list(value) and length(value) in 1..255, do: :ok
  defp criteria(_, _), do: invalid(:questions, "Invalid question type or criteria shape")

  # Some runners accept structured criterion descriptions and impose tighter limits.
  defp object_criteria(type, pairs) do
    if Enum.all?(pairs, fn
         {key, _} when is_atom(key) or is_binary(key) ->
           key = to_string(key)
           if type == "noul", do: key in ["true", "false"], else: String.trim(key) != ""

         _ ->
           false
       end) do
      :ok
    else
      invalid(:questions, "Invalid criterion key")
    end
  end

  defp videos(value) when value in [nil, []], do: :ok
  defp videos(_), do: invalid(:videos, "Video inputs are unsupported")

  defp optional_content(nil, _field), do: :ok
  defp optional_content(value, field), do: content(value, field)

  defp content(%Jason.OrderedObject{}, _field), do: :ok

  defp content(value, _field)
       when is_binary(value) or is_list(value) or (is_map(value) and not is_struct(value)),
       do: :ok

  defp content(_, field), do: invalid(field, "Expected a string, object, or array")

  defp invalid(field, message),
    do: {:error, RequestError.exception(field: field, message: message)}
end
