defmodule Ollixir.Transport do
  @moduledoc false

  alias Ollixir.{ConnectionError, RequestError, ResponseError}

  # Native init appends /api. Use a sibling route rather than joining /v1 to
  # /api, preserving any reverse-proxy prefix and Req configuration.
  def request(%Ollixir{req: req}, method, path, opts \\ []) do
    with {:ok, url} <- url(req, path) do
      req
      |> Req.request(Keyword.merge(opts, method: method, url: url, http_errors: :return))
      |> result()
    end
  end

  def url(req, path) do
    base = req.options[:base_url] || req.url

    case URI.parse(to_string(base)) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        prefix = (uri.path || "") |> String.trim_trailing("/") |> strip_namespace()
        {:ok, URI.to_string(%{uri | path: prefix <> path, query: nil, fragment: nil})}

      _ ->
        {:error, RequestError.exception("A valid absolute server base URL is required")}
    end
  end

  defp strip_namespace(path) do
    cond do
      String.ends_with?(path, "/v1/api") -> String.trim_trailing(path, "/v1/api")
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

  def result({:error, error}), do: {:error, RequestError.exception(inspect(error))}

  defp decode_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} when is_map(data) -> data
      _ -> body
    end
  end

  defp decode_error(body), do: body
end
