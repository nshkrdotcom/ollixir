defmodule Ollixir.EmbeddingInput do
  @moduledoc false

  alias Ollixir.{Media, RequestError}

  def normalize(params) do
    case Keyword.fetch(params, :input) do
      :error ->
        {:ok, params}

      {:ok, nil} ->
        {:ok, Keyword.delete(params, :input)}

      {:ok, input} ->
        with {:ok, input} <- normalize_input(input) do
          {:ok, Keyword.put(params, :input, input)}
        end
    end
  end

  defp normalize_input(input) when is_list(input) do
    input
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize_item(item) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp normalize_input(input), do: normalize_item(input)

  defp normalize_item(text) when is_binary(text), do: {:ok, text}

  defp normalize_item(item) when is_map(item) and not is_struct(item) do
    item
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_field(key, value) do
        {:ok, key, value} ->
          if Map.has_key?(acc, key) do
            {:halt, invalid("Duplicate input field #{key}")}
          else
            {:cont, {:ok, Map.put(acc, key, value)}}
          end

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, item} ->
        if Map.get(item, "text", "") != "" or Map.has_key?(item, "image") or
             Map.has_key?(item, "audio") do
          {:ok, item}
        else
          invalid("A multimodal item must contain text, image, or audio")
        end

      error ->
        error
    end
  end

  defp normalize_item(_), do: invalid("Input must be text or a multimodal item")

  defp normalize_field(key, text) when key in [:text, "text"] and is_binary(text),
    do: {:ok, "text", text}

  defp normalize_field(key, data) when key in [:image, "image", :audio, "audio"] do
    kind = if key in [:image, "image"], do: :image, else: :audio

    case Media.encode(data, kind) do
      {:ok, encoded} -> {:ok, Atom.to_string(kind), encoded}
      {:error, reason} -> invalid("Invalid #{kind} input", reason)
    end
  end

  defp normalize_field(_key, _value),
    do: invalid("Only text (string), image, and audio input fields are supported")

  defp invalid(message, reason \\ :validation_error),
    do: {:error, RequestError.exception(message: message, field: :input, reason: reason)}
end
