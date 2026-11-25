defmodule Ollixir.Release020NativeTest do
  use ExUnit.Case, async: true

  alias Ollixir.{RequestError, ResponseError}
  alias Ollixir.Types.{ChatResponse, Message, ShowManifestsResponse, SystemOneResponse}

  defp client(adapter) do
    Ollixir.init(Req.new(base_url: "http://ollama.test/proxy/api", adapter: adapter))
  end

  defp body(request), do: request.body |> IO.iodata_to_binary() |> Jason.decode!()

  defp json(request, data), do: {request, Req.Response.json(data)}

  test "chat retains new request fields and typed response metadata" do
    c =
      client(fn request ->
        assert request.url.path == "/proxy/api/chat"
        data = body(request)
        assert data["runner"] == "variant"
        assert data["shift"] == false
        assert data["truncate"] == true
        assert data["_debug_render_only"] == false
        refute Map.has_key?(data, "response_format")
        refute Map.has_key?(data, "think")
        assert [%{"thinking" => "reason", "tool_call_id" => "call-1"}] = data["messages"]

        json(request, %{
          "message" => %{
            "role" => "assistant",
            "tool_calls" => [
              %{"id" => "call-2", "function" => %{"name" => "lookup", "arguments" => %{}}}
            ]
          },
          "remote_host" => "https://example.test",
          "remote_model" => "remote",
          "prompt_eval_cached_count" => 12,
          "_debug_info" => %{"rendered" => "prompt"},
          "done" => true
        })
      end)

    assert {:ok,
            %ChatResponse{
              message: %Message{tool_calls: [call]},
              prompt_eval_cached_count: 12,
              remote_model: "remote",
              debug_info: %{"rendered" => "prompt"}
            }} =
             Ollixir.chat(c,
               model: "m",
               runner: "variant",
               truncate: true,
               shift: false,
               debug_render_only: false,
               response_format: :struct,
               messages: [
                 %{
                   "role" => "tool",
                   "content" => "answer",
                   "thinking" => "reason",
                   "tool_call_id" => "call-1"
                 }
               ]
             )

    assert call.id == "call-2"
  end

  test "generate sends explicit false thinking and new runner controls" do
    c =
      client(fn request ->
        assert request.url.path == "/proxy/api/generate"

        assert %{
                 "think" => false,
                 "runner" => "r",
                 "shift" => false,
                 "truncate" => false,
                 "_debug_render_only" => true
               } = body(request)

        json(request, %{"response" => "answer", "done" => true})
      end)

    assert {:ok, %{"response" => "answer"}} =
             Ollixir.generate(c,
               model: "m",
               prompt: "p",
               think: false,
               runner: "r",
               shift: false,
               truncate: false,
               _debug_render_only: true
             )
  end

  test "new create fields and model naming remain compatible" do
    c =
      client(fn request ->
        data = body(request)
        assert request.url.path == "/proxy/api/create"
        assert data["model"] == "custom" or data["name"] == "legacy"

        if data["model"] do
          assert data["draft_files"] == %{"draft.gguf" => "sha256:draft"}
          assert data["draft_quantize"] == "q4_K_M"
          assert data["requires"] == "0.40.18"
          assert data["info"] == %{"context" => 32}
          assert data["renderer"] == "renderer"
          assert data["parser"] == "parser"
        end

        assert data["stream"] == false
        json(request, %{"status" => "success"})
      end)

    assert {:ok, _} =
             Ollixir.create(c,
               model: "custom",
               from: "base",
               draft_files: %{"draft.gguf" => "sha256:draft"},
               draft_quantize: "q4_K_M",
               requires: "0.40.18",
               info: %{context: 32},
               renderer: "renderer",
               parser: "parser"
             )

    assert {:ok, _} = Ollixir.create(c, name: "legacy", from: "base")
    assert {:error, %RequestError{}} = Ollixir.create(c, model: "one", name: "two")
  end

  test "show all manifests uses a distinct typed response without stream" do
    c =
      client(fn request ->
        assert request.url.path == "/proxy/api/show"
        assert %{"model" => "m", "all_manifests" => true, "runner" => "r"} = body(request)
        refute Map.has_key?(body(request), "stream")

        json(request, %{
          "manifests" => [%{"runner" => "r", "details" => %{"family" => "test"}}],
          "license" => "MIT"
        })
      end)

    assert {:ok, %ShowManifestsResponse{manifests: [manifest], license: "MIT"}} =
             Ollixir.show_manifests(c, model: "m", runner: "r", response_format: :struct)

    assert manifest.runner == "r"
  end

  test "pull, push, and delete use supported model names and methods" do
    for {operation, path, method, params} <- [
          {:pull, "pull", :post, [model: "m", runner: "r"]},
          {:push, "push", :post, [name: "m"]},
          {:delete, "delete", :delete, [model: "m"]}
        ] do
      c =
        client(fn request ->
          assert request.method == method
          assert request.url.path == "/proxy/api/" <> path
          data = body(request)
          assert data["model"] == "m" or data["name"] == "m"
          if operation == :pull, do: assert(data["runner"] == "r")
          if operation == :delete, do: refute(Map.has_key?(data, "stream"))
          json(request, %{"status" => "success"})
        end)

      assert {:ok, _} = apply(Ollixir, operation, [c, params])
    end
  end

  test "multimodal embedding input encodes media exactly once" do
    bytes = <<0, 1, 2, 255>>
    encoded = Base.encode64(bytes)

    c =
      client(fn request ->
        assert request.url.path == "/proxy/api/embed"
        data = body(request)

        assert ["text", %{"text" => "caption", "image" => ^encoded, "audio" => ^encoded}] =
                 data["input"]

        assert data["runner"] == "r"
        refute Map.has_key?(data, "stream")
        json(request, %{"embeddings" => [[0.5], [0.7]]})
      end)

    assert {:ok, %{"embeddings" => [[0.5], [0.7]]}} =
             Ollixir.embed(c,
               model: "m",
               runner: "r",
               input: [
                 "text",
                 %{text: "caption", image: {:binary, bytes}, audio: {:base64, encoded}}
               ]
             )
  end

  test "invalid multimodal inputs and System One questions fail before HTTP" do
    c = client(fn _ -> flunk("validation must precede HTTP") end)

    for input <- [
          %{},
          %{video: "unsupported"},
          %{image: {:base64, "!"}},
          [42],
          %{text: 1},
          %{audio: {:file, "/nonexistent/ollixir-audio"}}
        ] do
      assert {:error, %RequestError{}} = Ollixir.embed(c, model: "m", input: input)
    end

    q = %{type: "noul", instructions: "Is it true?"}

    for questions <- [
          [],
          [{"same", q}, {"same", q}],
          %{"bad" => %{type: "unknown", instructions: "?"}},
          %{"bad" => %{type: "score", instructions: "?", criteria: []}},
          %{"bad" => %{type: "score", instructions: "?", criteria: %{"low" => "Low"}}},
          %{"bad" => %{type: "noul", instructions: "?", criteria: %{"maybe" => "Maybe"}}},
          %{"bad" => %{type: "choice", instructions: "?", criteria: %{" " => "Blank"}}}
        ] do
      assert {:error, %RequestError{}} =
               Ollixir.system_one(c, model: "m", state: "state", questions: questions)
    end

    assert {:error, %RequestError{field: :videos}} =
             Ollixir.system_one(c, model: "m", state: "state", questions: %{q: q}, videos: ["x"])
  end

  test "System One preserves ordered object questions and numeric answers" do
    c =
      client(fn request ->
        assert request.method == :post
        assert request.url.path == "/proxy/v1/systemone"
        raw = IO.iodata_to_binary(request.body)
        {z, _} = :binary.match(raw, "\"z_first\"")
        {a, _} = :binary.match(raw, "\"a_second\"")
        assert z < a
        data = body(request)
        assert is_map(data["questions"])
        assert data["questions"]["z_first"]["type"] == "noul"
        assert data["questions"]["a_second"]["criteria"] == ["low", "medium", "high"]
        assert data["runner"] == "r"
        refute Map.has_key?(data, "stream")
        refute Map.has_key?(data, "response_format")

        json(request, %{
          "model" => "m",
          "answers" => %{"z_first" => %{"noul" => 0.8}, "a_second" => %{"score" => 1.5}},
          "usage" => %{"input_tokens" => 5},
          "prompt_eval_cached_count" => 2
        })
      end)

    assert {:ok,
            %SystemOneResponse{
              answers: %{"z_first" => %{"noul" => 0.8}, "a_second" => %{"score" => 1.5}},
              usage: %{"input_tokens" => 5},
              prompt_eval_cached_count: 2
            }} =
             Ollixir.system_one(c,
               model: "m",
               runner: "r",
               state: %{text: "state"},
               questions: [
                 {"z_first", %{type: "noul", instructions: "True?"}},
                 {"a_second",
                  %{type: "score", instructions: "Rate", criteria: ["low", "medium", "high"]}}
               ],
               response_format: :struct
             )
  end

  test "server and account operations use sibling routes and correct methods" do
    routes = [
      {:heartbeat, [], :head, "/", true},
      {:version, [], :get, "/api/version", %{"version" => "0.40.18"}},
      {:status, [], :get, "/api/status", %{"cloud" => %{"disabled" => false}}},
      {:whoami, [], :post, "/api/me", %{"name" => "user"}},
      {:balance, [], :get, "/api/balance", %{"balance" => 1}},
      {:usage, [], :get, "/api/usage", %{"usage" => 1}},
      {:signout, [], :post, "/api/signout", true},
      {:disconnect, ["encoded-key"], :delete, "/api/user/keys/encoded-key", true},
      {:model_recommendations, [], :get, "/api/experimental/model-recommendations",
       %{"recommendations" => []}}
    ]

    for {operation, args, method, path, expected} <- routes do
      c =
        client(fn request ->
          assert request.method == method
          assert request.url.path == "/proxy" <> path

          if expected == true,
            do: {request, %Req.Response{status: 200, body: ""}},
            else: json(request, expected)
        end)

      assert {:ok, ^expected} = apply(Ollixir, operation, [c | args])
    end
  end

  test "account error preserves signin URL and HTTP status" do
    c =
      client(fn request ->
        {request,
         %Req.Response{
           status: 401,
           body: %{"error" => "not signed in", "signin_url" => "https://example.test/signin"}
         }}
      end)

    assert {:error,
            %ResponseError{status: 401, body: %{"signin_url" => "https://example.test/signin"}}} =
             Ollixir.whoami(c)
  end

  test "local experimental web operations keep configured proxy host" do
    for suffix <- ["", "/api", "/v1"] do
      c =
        Ollixir.init(
          base_url: "http://ollama.test/proxy" <> suffix,
          adapter: fn request ->
            assert request.url.host == "ollama.test"
            assert request.method == :post

            case request.url.path do
              "/proxy/api/experimental/web_search" ->
                assert body(request)["query"] == "test"
                json(request, %{"results" => []})

              "/proxy/api/experimental/web_fetch" ->
                assert body(request)["url"] == "https://example.test"
                json(request, %{"title" => "Example", "content" => "text"})
            end
          end
        )

      assert {:ok, %Ollixir.Web.SearchResponse{results: []}} =
               Ollixir.web_search_experimental(c, query: "test")

      assert {:ok, %Ollixir.Web.FetchResponse{content: "text"}} =
               Ollixir.web_fetch_experimental(c, url: "https://example.test")
    end
  end

  defp chunks(request, chunks) do
    Enum.reduce(chunks, {request, %Req.Response{status: 200, body: ""}}, fn chunk, acc ->
      {:cont, acc} = request.into.({:data, chunk}, acc)
      acc
    end)
  end

  test "NDJSON frames survive split and coalesced transport chunks" do
    c =
      client(fn request ->
        assert body(request)["stream"] == true

        chunks(request, [
          "{\"response\":\"a",
          "\",\"done\":false}\n{\"response\":\"b\",\"done\":false}\n",
          "{\"response\":\"\",\"done\":true}\n"
        ])
      end)

    assert {:ok, stream} = Ollixir.generate(c, model: "m", prompt: "p", stream: true)
    assert Enum.map(stream, & &1["response"]) == ["a", "b", ""]
    assert {:ok, task} = Ollixir.generate(c, model: "m", prompt: "p", stream: self())
    pid = task.pid
    assert_receive {^pid, {:data, %{"response" => "a"}}}
    assert {:ok, %{"response" => "ab", "done" => true}} = Task.await(task)
  end

  test "native in-stream errors are not silently treated as success" do
    c = client(fn request -> chunks(request, ["{\"error\":\"failure\"}\n"]) end)
    assert {:ok, stream} = Ollixir.generate(c, model: "m", prompt: "p", stream: true)
    assert_raise ResponseError, ~r/failure/, fn -> Enum.to_list(stream) end
  end

  test "native inference detects EOF after a complete but nonterminal record" do
    c =
      client(fn request -> chunks(request, ["{\"response\":\"partial\",\"done\":false}\r\n"]) end)

    assert {:ok, stream} = Ollixir.generate(c, model: "m", prompt: "p", stream: true)
    assert_raise RequestError, ~r/Incomplete NDJSON/, fn -> Enum.to_list(stream) end
  end

  test "halting native typed streaming stops its worker and drains buffered data" do
    owner = self()

    c =
      client(fn request ->
        send(owner, {:stream_worker, self()})
        chunks(request, ["{\"response\":\"first\",\"done\":false}\n{\"done\":true}\n"])
        Process.sleep(:infinity)
      end)

    assert {:ok, stream} =
             Ollixir.generate(c, model: "m", prompt: "p", stream: true, response_format: :struct)

    assert [%Ollixir.Types.GenerateResponse{response: "first"}] = Enum.take(stream, 1)
    assert_receive {:stream_worker, worker}
    refute Process.alive?(worker)
    refute_receive {^worker, {:data, _}}, 20
  end
end
