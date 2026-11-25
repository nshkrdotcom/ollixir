defmodule Ollixir.Multipart do
  @moduledoc false

  alias Ollixir.RequestError

  def encode(body) do
    with {:ok, file, filename} <- read_file(body["file"]),
         {:ok, fields} <- fields(Map.delete(body, "file")) do
      boundary = "ollixir-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      parts =
        Enum.map(fields, fn {key, value} ->
          [
            "--",
            boundary,
            "\r\nContent-Disposition: form-data; name=\"",
            key,
            "\"\r\n\r\n",
            value,
            "\r\n"
          ]
        end)

      data =
        IO.iodata_to_binary([
          parts,
          "--",
          boundary,
          "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"",
          sanitize_filename(filename),
          "\"\r\nContent-Type: ",
          content_type(filename),
          "\r\n\r\n",
          file,
          "\r\n--",
          boundary,
          "--\r\n"
        ])

      {:ok,
       [
         body: data,
         headers: [{"content-type", "multipart/form-data; boundary=" <> boundary}],
         retry: false
       ]}
    end
  end

  defp read_file({:file, path}), do: read_file(path)

  defp read_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, data} ->
        read_file({:binary, data, Path.basename(path)})

      {:error, reason} ->
        {:error,
         RequestError.exception(field: :file, message: "Cannot read audio file", reason: reason)}
    end
  end

  defp read_file({:binary, data}), do: read_file({:binary, data, "audio.wav"})

  defp read_file({:binary, data, filename})
       when is_binary(data) and byte_size(data) > 0 and is_binary(filename) and filename != "" do
    if String.valid?(filename) do
      {:ok, data, filename}
    else
      {:error, RequestError.exception(field: :file, message: "Expected a UTF-8 filename")}
    end
  end

  defp read_file(_),
    do:
      {:error,
       RequestError.exception(
         field: :file,
         message: "Expected a nonempty file path or {:binary, bytes, filename}"
       )}

  defp fields(body) do
    Enum.reduce_while(body, {:ok, []}, fn {key, value}, {:ok, acc} ->
      cond do
        not Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, key) ->
          {:halt, {:error, RequestError.exception("Invalid multipart field name")}}

        is_binary(value) or is_boolean(value) or is_number(value) ->
          {:cont, {:ok, [{key, to_string(value)} | acc]}}

        is_nil(value) ->
          {:cont, {:ok, acc}}

        true ->
          {:halt, {:error, RequestError.exception("Multipart fields must be scalar values")}}
      end
    end)
  end

  defp content_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".wav" -> "audio/wav"
      ".mp3" -> "audio/mpeg"
      ".flac" -> "audio/flac"
      ".ogg" -> "audio/ogg"
      ".opus" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      ".webm" -> "audio/webm"
      _ -> "application/octet-stream"
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/["\\\x00-\x1F\x7F]/, "_")
  end
end
