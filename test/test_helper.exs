ExUnit.start(exclude: [:cloud_api, :hf_integration, :ollama_live, :retry_warnings])

# Load test support modules
for {module, file} <- [
      {Ollixir.MockServer, "support/mock_server.ex"},
      {Ollixir.StreamCatcher, "support/stream_catcher.ex"},
      {Ollixir.TestAdapter, "support/test_adapter.ex"},
      {Ollixir.TestHelpers, "support/test_helpers.ex"}
    ] do
  unless Code.ensure_loaded?(module) do
    Code.require_file(file, __DIR__)
  end
end

# Start the mock server
{:ok, _pid} = Bandit.start_link(plug: Ollixir.MockServer, port: 4000)
