defmodule Ollixir.AuditRegressionsTest do
  use ExUnit.Case, async: false

  alias Ollixir.{Anthropic, Image, OpenAI, RequestError, ResponseError, Web}

  defp body(request), do: request.body |> IO.iodata_to_binary() |> Jason.decode!()

  defp client(adapter) do
    Ollixir.init(Req.new(base_url: "http://ollama.test/mount/v1", adapter: adapter))
  end

  defp local, do: Ollixir.init(host: "http://localhost:4000", api_key: nil)

  test "host parsing retains mount prefixes and handles IPv6" do
    for {host, expected} <- [
          {"localhost:11434/mount/v1", "http://localhost:11434/mount/api"},
          {"[::1]", "http://[::1]:11434/api"},
          {"::1", "http://[::1]:11434/api"},
          {"https://example.test/mount/api/", "https://example.test/mount/api"}
        ] do
      assert Ollixir.init(host).req.options.base_url == expected
    end
  end

  test "explicit keys and nil take precedence over native environment credentials" do
    original = System.get_env("OLLAMA_API_KEY")
    System.put_env("OLLAMA_API_KEY", "fake-environment-key")

    try do
      assert Ollixir.init(api_key: "explicit").req.headers["authorization"] == ["Bearer explicit"]
      refute Ollixir.init(api_key: nil).req.headers["authorization"]
      refute Anthropic.init(api_key: nil).req.headers["authorization"]
      refute Anthropic.init(api_key: "fake-anthropic-key").req.headers["authorization"]
    after
      if original,
        do: System.put_env("OLLAMA_API_KEY", original),
        else: System.delete_env("OLLAMA_API_KEY")
    end
  end

  test "native empty preload inputs and fractional durations are preserved" do
    c =
      client(fn request ->
        assert request.url.path in ["/mount/api/chat", "/mount/api/generate"]
        data = body(request)
        assert data["keep_alive"] == 0.5
        refute Map.has_key?(data, "think")
        assert data["stream"] == false

        case request.url.path do
          "/mount/api/chat" -> assert data["messages"] == []
          "/mount/api/generate" -> assert data["prompt"] == ""
        end

        {request, Req.Response.json(%{"done" => true})}
      end)

    assert {:ok, _} = Ollixir.chat(c, model: "m", keep_alive: 0.5, think: nil)
    assert {:ok, _} = Ollixir.generate(c, model: "m", keep_alive: 0.5, think: nil)
    assert {:error, %RequestError{}} = Ollixir.generate(c, model: "")
  end

  test "tagged media bytes and blob digests are byte safe" do
    bytes = <<0, 255, 46, 47, 128>>
    assert Image.encode({:binary, bytes}) == {:ok, Base.encode64(bytes)}
    assert Image.encode(bytes) == {:ok, Base.encode64(bytes)}
    assert {:error, _} = Image.encode(17)
    digest = Ollixir.Blob.digest(bytes)

    c =
      client(fn request ->
        assert request.url.path == "/mount/api/blobs/" <> digest
        assert IO.iodata_to_binary(request.body) == bytes
        {request, %Req.Response{status: 201, body: ""}}
      end)

    assert {:ok, ^digest} = Ollixir.create_blob(c, {:binary, bytes})
    assert {:ok, false} = Ollixir.check_blob(c, "sha256:../other")
  end

  test "typed log probabilities retain byte fields" do
    c =
      client(fn request ->
        {request,
         Req.Response.json(%{
           "response" => "a",
           "done" => true,
           "logprobs" => [%{"token" => "a", "logprob" => -0.5, "bytes" => [97]}]
         })}
      end)

    assert {:ok, %{logprobs: [%{bytes: [97]}]}} =
             Ollixir.generate(c, model: "m", logprobs: true, response_format: :struct)
  end

  test "duplicate compatibility and decision fields fail before sending HTTP" do
    c = client(fn _ -> flunk("must not send an invalid request") end)
    assert {:error, %RequestError{}} = OpenAI.chat(c, model: "a", model: "b", messages: [])

    criteria = Jason.OrderedObject.new([{"yes", "first"}, {"yes", "second"}])

    assert {:error, %RequestError{}} =
             Ollixir.system_one(c,
               model: "m",
               state: "text",
               questions: [{"choice", %{type: "choice", criteria: criteria}}]
             )
  end

  test "string-keyed native tool definitions are encoded without atomizing schema keys" do
    c =
      client(fn request ->
        assert [%{"function" => %{"name" => "lookup", "parameters" => %{"type" => "object"}}}] =
                 body(request)["tools"]

        {request, Req.Response.json(%{"done" => true})}
      end)

    assert {:ok, _} =
             Ollixir.chat(c,
               model: "m",
               tools: [
                 %{"function" => %{"name" => "lookup", "parameters" => %{"type" => "object"}}}
               ]
             )
  end

  test "runner-specific roles and decision JSON scalars reach the server" do
    c =
      client(fn request ->
        data = body(request)

        case request.url.path do
          "/mount/api/chat" ->
            assert [%{"role" => "custom-role"}] = data["messages"]

          "/mount/v1/systemone" ->
            assert data["state"] == false
            assert data["questions"]["q"]["instructions"] == 42
        end

        {request, Req.Response.json(%{})}
      end)

    assert {:ok, _} = Ollixir.chat(c, model: "m", messages: [%{role: "custom-role"}])

    assert {:ok, _} =
             Ollixir.systemone(c,
               model: "m",
               state: false,
               questions: [{"q", %{type: "noul", instructions: 42}}]
             )
  end

  test "web calls to a different origin don't inherit local credentials" do
    c =
      Ollixir.init(
        host: "https://local.test/api",
        api_key: "local-secret",
        headers: [{"cookie", "session=fake"}, {"x-api-key", "local-provider-secret"}],
        adapter: fn request ->
          assert request.url.host == "web.test"
          assert request.url.path == "/mount/api/web_search"
          assert Req.Request.get_header(request, "authorization") == ["Bearer scoped-web-key"]
          assert Req.Request.get_header(request, "cookie") == []
          assert Req.Request.get_header(request, "x-api-key") == []
          {request, Req.Response.json(%{"results" => []})}
        end
      )

    assert {:ok, _} =
             Web.search(c,
               query: "test",
               base_url: "https://web.test/mount",
               api_key: "scoped-web-key"
             )
  end

  test "real HTTP NDJSON handles UTF-8 fragmentation and terminal events" do
    assert {:ok, stream} = Ollixir.generate(local(), model: "audit-fragmented", stream: true)
    assert Enum.map(stream, & &1["response"]) == ["café", ""]
  end

  test "real HTTP NDJSON reports truncated inference and progress streams" do
    assert {:ok, stream} = Ollixir.generate(local(), model: "audit-truncated", stream: true)
    assert_raise RequestError, ~r/Incomplete NDJSON/, fn -> Enum.to_list(stream) end
    assert {:ok, progress} = Ollixir.pull(local(), model: "audit-truncated", stream: true)
    assert_raise RequestError, ~r/Incomplete NDJSON/, fn -> Enum.to_list(progress) end
  end

  test "real HTTP reports errors before and after stream data" do
    assert {:ok, stream} = Ollixir.generate(local(), model: "audit-stream-error", stream: true)
    assert_raise ResponseError, ~r/runner failed/, fn -> Enum.to_list(stream) end
    assert {:ok, denied} = Ollixir.generate(local(), model: "audit-denied", stream: true)
    assert_raise ResponseError, ~r/signin required/, fn -> Enum.to_list(denied) end

    assert {:error, %ResponseError{status: 401, body: %{"signin_url" => "https://example.test"}}} =
             Ollixir.generate(local(), model: "audit-denied")
  end

  test "hosted web requests do not follow redirects to a sibling origin" do
    assert {:error, %ResponseError{status: 307}} =
             Web.search(local(),
               query: "audit-redirect",
               base_url: "http://localhost:4000/api",
               api_key: "fake-secret"
             )
  end

  defmodule Receiver do
    def init(handler), do: handler
    def call(conn, handler), do: handler.(conn)
  end

  defp receive_http(handler, id) do
    server =
      start_supervised!(
        Supervisor.child_spec({Bandit, plug: {Receiver, handler}, ip: {127, 0, 0, 1}, port: 0},
          id: id
        )
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  test "redirect destinations receive no requests, including dynamically attached credentials" do
    owner = self()

    target =
      receive_http(
        fn conn ->
          send(owner, :redirect_replayed)
          Plug.Conn.send_resp(conn, 200, "{}")
        end,
        :redirect_target
      )

    source =
      receive_http(
        fn conn ->
          status = conn.path_info |> List.first() |> String.to_integer()
          send(owner, {:source, status, Plug.Conn.get_req_header(conn, "x-custom-secret")})

          conn
          |> Plug.Conn.put_resp_header("location", target <> "/capture")
          |> Plug.Conn.send_resp(status, "")
        end,
        :redirect_source
      )

    for status <- [301, 302, 307, 308] do
      base_url = "#{source}/#{status}"

      req =
        Req.new(base_url: base_url)
        |> Req.Request.append_request_steps(
          custom_auth: &Req.Request.put_header(&1, "x-custom-secret", "fake-auth")
        )

      c = Ollixir.init(req)
      assert {:error, %ResponseError{status: ^status}} = Ollixir.version(c)
      assert_receive {:source, ^status, ["fake-auth"]}

      assert {:error, %ResponseError{status: ^status}} =
               Web.search(c, query: "test", base_url: base_url, api_key: "fake-web")

      assert_receive {:source, ^status, ["fake-auth"]}
    end

    refute_receive :redirect_replayed
  end

  test "cross-origin web requests ignore process-wide Req auth, params and plugins" do
    owner = self()

    url =
      receive_http(
        fn conn ->
          send(owner, {:captured, conn.req_headers, conn.query_string})

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ~s({"results":[]}))
        end,
        :web_target
      )

    req_defaults = Req.default_options()
    on_exit(fn -> Req.default_options(req_defaults) end)
    Req.default_options(auth: {:bearer, "fake-default"}, params: [token: "fake-query"])

    c = Ollixir.init(host: "http://127.0.0.1:1", api_key: "fake-local")
    assert {:ok, _} = Web.search(c, query: "test", base_url: url)
    assert_receive {:captured, headers, ""}
    refute List.keymember?(headers, "authorization", 0)
  end

  test "malformed hosts and duplicate native fields fail before the adapter" do
    adapter = fn _ -> flunk("adapter must not run") end

    for host <- [
          "ftp://example.test",
          "http://user:password@example.test",
          "http://host:abc",
          "http://host:",
          "http://host:65536",
          "http://[invalid]"
        ] do
      c = Ollixir.init(host: host, adapter: adapter)
      assert {:error, %RequestError{}} = Ollixir.version(c)
    end

    c = client(adapter)
    assert {:error, %RequestError{}} = Ollixir.generate(c, model: "m", model: "duplicate")

    assert {:error, %RequestError{}} =
             Ollixir.chat(c, model: "m", messages: [%{:role => "user", "role" => "system"}])

    assert {:error, %RequestError{}} =
             Ollixir.system_one(c,
               model: "m",
               state: "text",
               questions: [{"q", %{:type => "noul", "type" => "score"}}]
             )

    assert {:error, %RequestError{}} =
             OpenAI.responses(c, model: "m", input: [self()])
  end

  test "stream workers isolate a hard exit in enumerable and Task modes" do
    c = client(fn _ -> Process.exit(self(), :kill) end)
    assert {:ok, stream} = Ollixir.generate(c, model: "m", stream: true)
    assert_raise RequestError, ~r/worker stopped/, fn -> Enum.to_list(stream) end

    assert {:ok, task} = Ollixir.generate(c, model: "m", stream: self())
    assert {:error, %RequestError{reason: :killed}} = Task.await(task)
  end

  test "an adapter that stalls before a frame is cancelled" do
    owner = self()

    req =
      Req.new(
        base_url: "http://localhost",
        receive_timeout: 100,
        adapter: fn _ ->
          send(owner, {:started, self()})
          Process.sleep(:infinity)
        end
      )

    assert {:ok, stream} = Ollixir.generate(Ollixir.init(req), model: "m", stream: true)
    assert_raise RequestError, ~r/Timed out/, fn -> Enum.to_list(stream) end
    assert_receive {:started, worker}
    refute Process.alive?(worker)
  end

  test "early enumeration halt cancels a real HTTP stream held open by its server" do
    owner = self()

    url =
      receive_http(
        fn conn ->
          conn = Plug.Conn.send_chunked(conn, 200)
          {:ok, conn} = Plug.Conn.chunk(conn, ~s({"response":"first","done":false}) <> "\n")
          send(owner, {:connection, self()})

          receive do
            :finish -> conn
          end
        end,
        :blocking_stream
      )

    wrapped =
      Ollixir.init(host: url).req
      |> Req.Request.append_request_steps(
        observe: fn request ->
          send(owner, {:worker, self()})
          request
        end
      )

    assert {:ok, stream} = Ollixir.generate(Ollixir.init(wrapped), model: "m", stream: true)
    assert [%{"response" => "first"}] = Enum.take(stream, 1)
    assert_receive {:worker, worker}
    refute Process.alive?(worker)
    assert_receive {:connection, connection}
    send(connection, :finish)
  end

  test "actual multipart receiver reads translation fields and all file bytes" do
    owner = self()

    url =
      receive_http(
        fn conn ->
          conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart]))
          upload = conn.params["file"]

          send(
            owner,
            {conn.params["to_language"], upload.filename, upload.content_type,
             File.read!(upload.path)}
          )

          Plug.Conn.send_resp(conn, 200, "translated text")
        end,
        :multipart_target
      )

    wav =
      <<"RIFF", 36::little-32, "WAVEfmt ", 16::little-32, 1::little-16, 1::little-16,
        16_000::little-32, 32_000::little-32, 2::little-16, 16::little-16, "data", 0::little-32>>

    assert {:ok, "translated text"} =
             OpenAI.translation(Ollixir.init(host: url),
               model: "mock",
               file: {:binary, wav, "fixture.wav"},
               to_language: "en",
               response_format: "text"
             )

    assert_receive {"en", "fixture.wav", "audio/wav", ^wav}
  end
end
