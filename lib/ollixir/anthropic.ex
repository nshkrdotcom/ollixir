defmodule Ollixir.Anthropic do
  @moduledoc """
  Client for Ollama's Anthropic-compatible `/v1/messages` route.

  Pass Anthropic-shaped maps or keyword lists. Responses are unmodified
  JSON maps, including content blocks, tool use, thinking, and usage.
  `stream: true` returns an enumerable of SSE JSON payloads, and a PID
  returns a task that sends payload messages as described in `Ollixir.OpenAI`.
  Ollama does not expose all Anthropic API endpoints.
  """

  alias Ollixir.Protocol

  @doc "Initialize with the same host/Req options as `Ollixir.init/1`, or reuse a client."
  def init(opts \\ []), do: Protocol.init(opts, :anthropic)

  @doc "Create a message (`POST /v1/messages`)."
  def messages(client, params),
    do: Protocol.json(client, "/v1/messages", params, [:model, :messages, :max_tokens], :sse)

  @doc "Alias for `messages/2`."
  def message(client, params), do: messages(client, params)
end
