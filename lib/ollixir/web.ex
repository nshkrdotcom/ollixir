defmodule Ollixir.Web do
  @moduledoc """
  Web search and fetch functionality for Ollama cloud API.

  These functions require an Ollama API key when calling the hosted API.
  Set `OLLAMA_API_KEY`, use a client initialized for `https://ollama.com`,
  or pass `api_key:` directly to the web operation. Credentials on a client
  for another origin are not forwarded automatically.
  """

  alias Ollixir.RequestError
  alias Ollixir.Web.{FetchResponse, SearchResponse}

  @cloud_base_url "https://ollama.com/api"

  @type search_opts :: [
          query: String.t(),
          max_results: pos_integer(),
          base_url: String.t(),
          api_key: String.t()
        ]

  @type fetch_opts :: [
          url: String.t(),
          base_url: String.t(),
          api_key: String.t()
        ]

  @doc """
  Search the web using Ollama's cloud search API.
  """
  @spec search(Ollixir.client(), search_opts()) :: {:ok, SearchResponse.t()} | {:error, term()}
  def search(%Ollixir{} = client, opts) do
    {base_url, opts} = Keyword.pop(opts, :base_url)
    {api_key, opts} = Keyword.pop(opts, :api_key, :default)

    with {:ok, validated} <- validate_search_opts(opts),
         {:ok, cloud_client} <- ensure_cloud_client(client, base_url, api_key),
         {:ok, response} when is_map(response) <-
           do_request(cloud_client, :post, "/web_search", validated) do
      cast_search(response)
    else
      {:ok, _} -> invalid_response()
      error -> error
    end
  end

  @doc """
  Search the web, raising on error.
  """
  @spec search!(Ollixir.client(), search_opts()) :: SearchResponse.t()
  def search!(client, opts) do
    case search(client, opts) do
      {:ok, response} -> response
      {:error, reason} -> raise "Web search failed: #{inspect(reason)}"
    end
  end

  @doc """
  Fetch and extract content from a URL.
  """
  @spec fetch(Ollixir.client(), fetch_opts()) :: {:ok, FetchResponse.t()} | {:error, term()}
  def fetch(%Ollixir{} = client, opts) do
    {base_url, opts} = Keyword.pop(opts, :base_url)
    {api_key, opts} = Keyword.pop(opts, :api_key, :default)

    with {:ok, validated} <- validate_fetch_opts(opts),
         {:ok, cloud_client} <- ensure_cloud_client(client, base_url, api_key),
         {:ok, response} when is_map(response) <-
           do_request(cloud_client, :post, "/web_fetch", validated) do
      {:ok, FetchResponse.from_map(response)}
    else
      {:ok, _} -> invalid_response()
      error -> error
    end
  end

  @doc """
  Fetch content, raising on error.
  """
  @spec fetch!(Ollixir.client(), fetch_opts()) :: FetchResponse.t()
  def fetch!(client, opts) do
    case fetch(client, opts) do
      {:ok, response} -> response
      {:error, reason} -> raise "Web fetch failed: #{inspect(reason)}"
    end
  end

  @doc "Search using the configured server's experimental cloud proxy."
  def search_experimental(%Ollixir{} = client, opts) do
    with {:ok, body} <- validate_search_opts(opts),
         {:ok, response} when is_map(response) <-
           Ollixir.Transport.request(client, :post, "/api/experimental/web_search",
             json: body,
             retry: false
           ) do
      cast_search(response)
    else
      {:ok, _} -> invalid_response()
      error -> error
    end
  end

  @doc "Fetch using the configured server's experimental cloud proxy."
  def fetch_experimental(%Ollixir{} = client, opts) do
    with {:ok, body} <- validate_fetch_opts(opts),
         {:ok, response} when is_map(response) <-
           Ollixir.Transport.request(client, :post, "/api/experimental/web_fetch",
             json: body,
             retry: false
           ) do
      {:ok, FetchResponse.from_map(response)}
    else
      {:ok, _} -> invalid_response()
      error -> error
    end
  end

  defp cast_search(%{"results" => results} = response) when is_list(results) do
    if Enum.all?(results, &is_map/1) do
      {:ok, SearchResponse.from_map(response)}
    else
      {:error, RequestError.exception("Expected web search results to be JSON objects")}
    end
  end

  defp cast_search(_), do: {:error, RequestError.exception("Expected a web search results list")}

  defp invalid_response(), do: {:error, RequestError.exception("Expected a web JSON object")}

  defp validate_search_opts(opts) do
    query = Keyword.get(opts, :query)
    max_results = Keyword.get(opts, :max_results, 3)

    cond do
      is_nil(query) or query == "" ->
        {:error, RequestError.missing_field(:query)}

      not is_binary(query) ->
        {:error, RequestError.invalid_type(:query, query, "string")}

      not is_integer(max_results) or max_results < 1 ->
        {:error,
         RequestError.invalid_value(:max_results, max_results, "must be positive integer")}

      true ->
        {:ok, %{query: query, max_results: max_results}}
    end
  end

  defp validate_fetch_opts(opts) do
    url = Keyword.get(opts, :url)

    cond do
      is_nil(url) or url == "" ->
        {:error, RequestError.missing_field(:url)}

      not is_binary(url) ->
        {:error, RequestError.invalid_type(:url, url, "string")}

      true ->
        {:ok, %{url: url}}
    end
  end

  defp ensure_cloud_client(%Ollixir{req: req}, base_url, api_key) do
    with {:ok, base_url} <- normalize_base_url(base_url || default_base_url()) do
      source = origin(req.options[:base_url] || req.url)
      destination = origin(base_url)

      req =
        if source == destination do
          Req.Request.put_option(req, :base_url, base_url)
        else
          # Do not transplant arbitrary headers, auth steps, query parameters,
          # cookies, proxy configuration or TLS client credentials to a new host.
          # The adapter is intentionally retained for custom transports/tests.
          safe_opts =
            req.options
            |> Map.take([:receive_timeout, :pool_timeout])
            |> Map.to_list()

          headers =
            for {name, values} <- Map.take(req.headers, ["user-agent", "accept"]),
                value <- values,
                do: {name, value}

          Req.Request.new()
          |> Req.Steps.attach()
          |> Req.merge(safe_opts ++ [base_url: base_url, adapter: req.adapter, headers: headers])
        end

      with {:ok, req} <- ensure_auth(req, destination, api_key) do
        {:ok, %Ollixir{req: req}}
      end
    end
  end

  defp ensure_auth(req, destination, api_key) do
    cloud? = destination == {"https", "ollama.com", 443}

    cond do
      is_binary(api_key) and api_key != "" ->
        # Explicitly scoped to this web destination; override any Req auth step.
        req = %{req | options: Map.delete(req.options, :auth)}
        {:ok, Req.Request.put_header(req, "authorization", "Bearer " <> api_key)}

      api_key == nil ->
        req = %{req | options: Map.delete(req.options, :auth)}
        req = Req.Request.delete_header(req, "authorization")

        if cloud?, do: missing_web_key(), else: {:ok, req}

      api_key != :default ->
        {:error, RequestError.exception(message: "Invalid web API key", reason: :invalid_api_key)}

      cloud? ->
        case Req.Request.get_header(req, "authorization") do
          [] ->
            cloud_env_auth(req)

          ["Bearer " <> key] when key != "" ->
            {:ok, %{req | options: Map.delete(req.options, :auth)}}

          _ ->
            {:error,
             RequestError.exception(
               message: "Authorization header with Bearer token is required for web endpoints",
               reason: :invalid_api_key
             )}
        end

      true ->
        {:ok, req}
    end
  end

  defp cloud_env_auth(req) do
    case System.get_env("OLLAMA_API_KEY") do
      key when is_binary(key) and key != "" ->
        req = %{req | options: Map.delete(req.options, :auth)}
        {:ok, Req.Request.put_header(req, "authorization", "Bearer " <> key)}

      _ ->
        missing_web_key()
    end
  end

  defp missing_web_key do
    {:error,
     RequestError.exception(
       message: "OLLAMA_API_KEY or an explicit web API key is required for web endpoints",
       reason: :missing_api_key
     )}
  end

  defp origin(base_url) do
    case Ollixir.Transport.parse_http_url(base_url) do
      {:ok, %URI{scheme: scheme, host: host, port: port}} ->
        {scheme, String.downcase(host), port}

      _ ->
        nil
    end
  end

  defp do_request(%Ollixir{req: req}, method, url, body) do
    req
    |> Req.request(
      method: method,
      url: String.trim_leading(url, "/"),
      json: body,
      retry: false,
      redirect: false,
      redirect_trusted: false,
      http_errors: :return
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Ollixir.Transport.result({:ok, %{status: status, body: body}})
  end

  defp handle_response({:error, %Req.TransportError{reason: reason}}) do
    {:error,
     RequestError.exception(
       message: "Connection failed: #{inspect(reason)}",
       reason: :connection_error
     )}
  end

  defp handle_response({:error, reason}) do
    {:error, RequestError.exception(inspect(reason))}
  end

  defp normalize_base_url(url) when is_binary(url) do
    with {:ok, %URI{query: nil, fragment: nil} = uri} <-
           Ollixir.Transport.parse_http_url(url) do
      path = String.trim_trailing(uri.path || "", "/")
      path = if String.ends_with?(path, "/api"), do: path, else: path <> "/api"
      {:ok, URI.to_string(%{uri | path: path})}
    else
      _ ->
        {:error, RequestError.exception("Expected an absolute web base URL without credentials")}
    end
  end

  defp normalize_base_url(_), do: {:error, RequestError.exception("Invalid web base URL")}

  defp default_base_url do
    System.get_env("OLLAMA_WEB_BASE_URL") || Application.get_env(:ollixir, :web_base_url) ||
      @cloud_base_url
  end
end
