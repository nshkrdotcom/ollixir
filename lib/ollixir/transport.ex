defmodule Ollixir.Transport do
  @moduledoc false

  alias Ollixir.{ConnectionError, RequestError, ResponseError}

  # Native init appends /api. Use a sibling route rather than joining /v1 to
  # /api, preserving any reverse-proxy prefix and Req configuration.
  def request(%Ollixir{req: req}, method, path, opts \\ []) do
    with {:ok, url} <- url(req, path) do
      opts = Keyword.merge(opts, method: method, url: url, http_errors: :return)
      opts = secure_options(opts)

      req
      |> request_req(opts)
      |> result()
    end
  end

  # Custom request steps can attach credentials after options are selected.
  def secure_options(opts) do
    Keyword.merge(opts, redirect: false, redirect_trusted: false)
  end

  def request_req(req, opts) do
    Req.request(req, opts)
  rescue
    _error in [Jason.EncodeError, Protocol.UndefinedError] ->
      {:error, RequestError.exception("Request contains a value that cannot be encoded as JSON")}
  end

  def normalize_keys(map, keys) do
    Enum.reduce_while(keys, {:ok, map}, fn key, {:ok, acc} ->
      case Map.pop(acc, Atom.to_string(key)) do
        {_, ^acc} ->
          {:cont, {:ok, acc}}

        {value, rest} ->
          if Map.has_key?(rest, key) do
            {:halt, {:error, RequestError.exception("Duplicate request field #{key}")}}
          else
            {:cont, {:ok, Map.put(rest, key, value)}}
          end
      end
    end)
  end

  def parse_http_url(value) when is_binary(value) do
    with {:ok, %URI{scheme: scheme, host: host, port: port, userinfo: nil} = uri} <-
           URI.new(value),
         true <- scheme in ["http", "https"] and is_binary(host) and host != "",
         true <- is_integer(port) and port in 1..65_535,
         authority when is_binary(authority) <- URI.parse(value).authority,
         false <- String.ends_with?(authority, ":") do
      {:ok, %{uri | authority: authority}}
    else
      _ ->
        {:error, RequestError.exception("Expected an absolute HTTP(S) URL without credentials")}
    end
  end

  def parse_http_url(%URI{} = uri), do: parse_http_url(URI.to_string(uri))

  def parse_http_url(_),
    do: {:error, RequestError.exception("Expected an absolute HTTP(S) URL without credentials")}

  def url(req, path) do
    base = req.options[:base_url] || req.url

    with {:ok, uri} <- parse_http_url(base) do
      prefix = (uri.path || "") |> String.trim_trailing("/") |> strip_namespace()
      {:ok, URI.to_string(%{uri | path: prefix <> path, query: nil, fragment: nil})}
    end
  end

  defp strip_namespace(path) do
    cond do
      String.ends_with?(path, "/api") -> String.trim_trailing(path, "/api")
      String.ends_with?(path, "/v1") -> String.trim_trailing(path, "/v1")
      true -> path
    end
  end

  def result({:ok, %{status: status, body: body}}) when status in 200..299, do: {:ok, body}

  def result({:ok, %{status: status, body: body}}),
    do: {:error, ResponseError.exception(status: status, body: decode_error(body))}

  def result({:error, %Req.TransportError{} = error}),
    do: {:error, ConnectionError.exception(original_error: error)}

  def result({:error, %RequestError{} = error}), do: {:error, error}

  def result({:error, error}), do: {:error, RequestError.exception(inspect(error))}

  defp decode_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} when is_map(data) -> data
      _ -> body
    end
  end

  defp decode_error(body), do: body
end
