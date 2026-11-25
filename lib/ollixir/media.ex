defmodule Ollixir.Media do
  @moduledoc false

  # Tagged inputs remove ambiguity between raw bytes, paths and base64 text.
  def encode({:file, path}, _kind) when is_binary(path) do
    case File.read(path) do
      {:ok, data} -> encode({:binary, data}, :media)
      {:error, reason} -> {:error, {:read_error, reason}}
    end
  end

  def encode({:binary, data}, _kind) when is_binary(data) and byte_size(data) > 0,
    do: {:ok, Base.encode64(data)}

  def encode({:base64, data}, _kind) when is_binary(data), do: validate_base64(data)

  def encode(data, :image) when is_binary(data), do: Ollixir.Image.encode(data)

  def encode(data, :audio) when is_binary(data) do
    cond do
      File.regular?(data) -> encode({:file, data}, :audio)
      audio_binary?(data) -> encode({:binary, data}, :audio)
      true -> validate_base64(data)
    end
  end

  def encode(_, _), do: {:error, :invalid_media}

  defp validate_base64(data) do
    case Base.decode64(data) do
      {:ok, bytes} when byte_size(bytes) > 0 -> {:ok, data}
      _ -> {:error, :invalid_base64}
    end
  end

  defp audio_binary?(<<"RIFF", _::binary-size(4), "WAVE", _::binary>>), do: true
  defp audio_binary?(<<"fLaC", _::binary>>), do: true
  defp audio_binary?(<<"OggS", _::binary>>), do: true
  defp audio_binary?(<<"ID3", _::binary>>), do: true
  defp audio_binary?(data), do: not String.valid?(data)
end
