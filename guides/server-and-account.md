# Server and Account

Ollixir 0.2.0 targets Ollama v0.40.18. The following functions address the
configured Ollama server, not a separate hosted service. They preserve the
client's Req configuration, authentication and reverse-proxy prefix.

| Function | Method and route | Successful value |
| --- | --- | --- |
| `heartbeat/1` | `HEAD /` | `true` |
| `version/1,2` | `GET /api/version` | Version map or struct |
| `status/1,2` | `GET /api/status` | Cloud status map or struct |
| `whoami/1,2` (`me`) | `POST /api/me` | Account map or struct |
| `balance/1` | `GET /api/balance` | Raw response |
| `usage/1` | `GET /api/usage` | Raw response |
| `signout/1` | `POST /api/signout` | `true` |
| `disconnect/2` | `DELETE /api/user/keys/:encodedKey` | `true` |
| `model_recommendations/1,2` | `GET /api/experimental/model-recommendations` | Map or struct |
| `web_search_experimental/2` | `POST /api/experimental/web_search` | Search response struct |
| `web_fetch_experimental/2` | `POST /api/experimental/web_fetch` | Fetch response struct |

```elixir
client = Ollixir.init()
{:ok, true} = Ollixir.heartbeat(client)
{:ok, version} = Ollixir.version(client, response_format: :struct)
{:ok, status} = Ollixir.cloud_status(client)
IO.inspect({version, status})
```

The version, status, identity, and recommendations calls honor the native
`response_format: :struct` option. Account calls depend on server sign-in and
cloud availability. A failed identity call may include a `signin_url` in the
body of a `ResponseError`; callers can present that URL rather than treating
an unauthorized account as a valid identity.

`signout/1` and `disconnect/2` change account state. Use them only deliberately.
`disconnect/2` takes an already encoded key identifier, not a private key or a
raw SSH key. On current local servers this deprecated route aliases signout,
so it is not a targeted key-revocation operation. Successful status-only operations return `{:ok, true}`; errors
are not converted to success.

Experimental web methods differ from the existing `Ollixir.web_search/2`
and `Ollixir.web_fetch/2` hosted API methods:

```elixir
{:ok, result} = Ollixir.web_search_experimental(client, query: "Elixir", max_results: 3)
{:ok, page} = Ollixir.web_fetch_experimental(client, url: "https://elixir-lang.org")
```

The server may require sign-in or disable cloud access; handle errors and do
not assume availability. See [Cloud API](cloud-api.md) for hosted calls.

For model creation on Ollama v0.40.18, use `from` or uploaded blobs referenced
by digest in `files` and `draft_files`. The SDK retains the older `modelfile`
and `adapters` fields for existing callers targeting older servers. Check the
target server's creation contract when migrating those requests.
