defmodule Ollixir.Release020LiveTest do
  use ExUnit.Case, async: true

  @moduletag :ollama_live

  test "stable server discovery and OpenAI model listing agree" do
    client = Ollixir.init(host: System.fetch_env!("OLLIXIR_RELEASE_LIVE_HOST"), api_key: nil)

    assert {:ok, true} = Ollixir.heartbeat(client)
    assert {:ok, %{"version" => "0.40.18"}} = Ollixir.version(client)
    assert {:ok, %{"models" => models}} = Ollixir.list(client)
    assert {:ok, %{"data" => compatible}} = Ollixir.OpenAI.models(client)
    assert is_list(models)
    assert is_list(compatible)
  end
end
