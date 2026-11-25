defmodule Ollixir.ProtocolTest do
  use ExUnit.Case, async: true

  alias Ollixir.{Anthropic, OpenAI, RequestError, ResponseError}

  defp client(adapter, base \\ "http://ollama.test/proxy/api"),
    do: OpenAI.init(Req.new(base_url: base, adapter: adapter))

  defp body(request), do: request.body |> IO.iodata_to_binary() |> Jason.decode!()
  defp json(request, data), do: {request, Req.Response.json(data)}

  test "all OpenAI JSON endpoints preserve provider fields and route prefixes" do
    for {operation, path, params} <- [
          {:chat_completions, "chat/completions",
           %{
             model: "m",
             messages: [%{role: "user", content: "hello"}],
             response_format: %{type: "json_object"},
             stream_options: %{include_usage: true}
           }},
          {:completions, "completions", %{model: "m", prompt: "hello", max_tokens: 2}},
          {:embeddings, "embeddings", %{model: "m", input: ["hello"], encoding_format: "base64"}},
          {:responses, "responses",
           %{model: "m", input: "hello", previous_response_id: "previous"}},
          {:responses_compact, "responses/compact",
           %{model: "m", input: [%{role: "user", content: "hello"}]}}
        ] do
      expected = params |> Jason.encode!() |> Jason.decode!()

      c =
        client(fn request ->
          assert request.method == :post
          assert request.url.path == "/proxy/v1/" <> path
          assert body(request) == expected
          json(request, %{"object" => "provider.response"})
        end)

      assert {:ok, %{"object" => "provider.response"}} = apply(OpenAI, operation, [c, params])
    end
  end

  test "stable provider converters accept empty and omitted inputs where applicable" do
    c =
      client(fn request ->
        expected = %{
          "/proxy/v1/completions" => "prompt",
          "/proxy/v1/embeddings" => "input",
          "/proxy/v1/responses" => "input"
        }

        field = Map.fetch!(expected, request.url.path)
        json(request, %{"value" => Map.get(body(request), field, "omitted")})
      end)

    assert {:ok, %{"value" => ""}} = OpenAI.completions(c, model: "m", prompt: "")
    assert {:ok, %{"value" => ""}} = OpenAI.embeddings(c, model: "m", input: "")
    assert {:ok, %{"value" => "omitted"}} = OpenAI.responses(c, model: "m", instructions: "hello")
  end

  test "models routes and base URL namespace handling" do
    for base <- [
          "http://ollama.test/proxy",
          "http://ollama.test/proxy/api",
          "http://ollama.test/proxy/v1"
        ] do
      c =
        client(
          fn request ->
            assert request.method == :get

            assert request.url.path in [
                     "/proxy/v1/models",
                     "/proxy/v1/models/model:tag",
                     "/proxy/v1/models/model%3Atag"
                   ]

            json(request, %{"data" => []})
          end,
          base
        )

      assert {:ok, _} = OpenAI.models(c)
      assert {:ok, _} = OpenAI.retrieve_model(c, "model:tag")
    end
  end

  test "Anthropic messages preserve content blocks, tools, and authentication" do
    params = [
      model: "m",
      max_tokens: 16,
      system: "system",
      messages: [%{role: "user", content: [%{type: "text", text: "hello"}]}],
      tools: [%{name: "lookup", input_schema: %{type: "object"}}]
    ]

    c =
      Anthropic.init(
        base_url: "http://ollama.test/proxy/v1",
        api_key: "test-key",
        adapter: fn request ->
          assert request.url.path == "/proxy/v1/messages"
          assert Req.Request.get_header(request, "x-api-key") == ["test-key"]
          assert body(request) == params |> Map.new() |> Jason.encode!() |> Jason.decode!()

          json(request, %{"type" => "message", "content" => [%{"type" => "text", "text" => "hi"}]})
        end
      )

    assert {:ok, %{"type" => "message", "content" => [%{"text" => "hi"}]}} =
             Anthropic.messages(c, params)
  end

  test "OpenAI explicit bearer authentication" do
    c =
      OpenAI.init(
        base_url: "http://ollama.test",
        api_key: "test-key",
        adapter: fn request ->
          assert Req.Request.get_header(request, "authorization") == ["Bearer test-key"]
          json(request, %{"data" => []})
        end
      )

    assert {:ok, _} = OpenAI.models(c)
  end

  defp chunks(request, chunks, status \\ 200) do
    Enum.reduce_while(chunks, {request, %Req.Response{status: status, body: ""}}, fn chunk, acc ->
      request.into.({:data, chunk}, acc)
    end)
  end

  test "SSE requires the route's terminal event and ignores frames after it" do
    wrong = client(fn request -> chunks(request, ["data: [DONE]\n\n"]) end)

    assert {:ok, stream} =
             Anthropic.messages(wrong, model: "m", messages: [], max_tokens: 16, stream: true)

    assert_raise RequestError, fn -> Enum.to_list(stream) end

    complete =
      client(fn request ->
        chunks(request, [
          "data: {\"type\":\"response.incomplete\"}\n\ndata: invalid-late-json\n\n"
        ])
      end)

    assert {:ok, stream} = OpenAI.responses(complete, model: "m", input: "hi", stream: true)
    assert Enum.to_list(stream) == [%{"type" => "response.incomplete"}]
  end

  test "SSE supports fragmented UTF-8, CRLF, comments, multiline data, and DONE" do
    data =
      ": heartbeat\r\nevent: message\r\ndata: {\"text\":\r\ndata: \"caf" <>
        <<195, 169>> <> "\"}\r\n\r\ndata: {\"done\":true}\n\ndata: [DONE]\n\n"

    c =
      client(fn request ->
        assert body(request)["stream"] == true
        chunks(request, for(<<byte <- data>>, do: <<byte>>))
      end)

    assert {:ok, stream} = OpenAI.chat(c, model: "m", messages: [], stream: true)
    assert Enum.to_list(stream) == [%{"text" => "caf" <> <<195, 169>>}, %{"done" => true}]
  end

  test "Anthropic SSE preserves event payloads and PID completion" do
    c =
      client(fn request ->
        chunks(request, [
          "event: message_start\ndata: {\"type\":\"message_start\"}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
        ])
      end)

    assert {:ok, task} =
             Anthropic.messages(c, model: "m", max_tokens: 1, messages: [], stream: self())

    pid = task.pid
    assert_receive {^pid, {:data, %{"type" => "message_start"}}}
    assert_receive {^pid, {:data, %{"type" => "message_stop"}}}
    assert {:ok, :done} = Task.await(task)
  end

  test "SSE can halt early and leaves no worker data messages" do
    owner = self()

    c =
      client(fn request ->
        send(owner, {:stream_worker, self()})
        chunks(request, ["data: {\"n\":1}\n\ndata: {\"n\":2}\n\n"])
        Process.sleep(:infinity)
      end)

    assert {:ok, stream} = OpenAI.responses(c, model: "m", input: "hello", stream: true)
    assert Enum.take(stream, 1) == [%{"n" => 1}]
    assert_receive {:stream_worker, worker}
    refute Process.alive?(worker)
    refute_receive {_pid, {:data, _}}, 20
  end

  test "HTTP errors, nested SSE errors, and invalid events retain failure semantics" do
    c = client(fn request -> chunks(request, ["{\"error\":{\"message\":\"denied\"}}"], 401) end)
    assert {:ok, stream} = OpenAI.chat(c, model: "m", messages: [], stream: true)
    assert_raise ResponseError, ~r/denied/, fn -> Enum.to_list(stream) end

    c =
      client(fn request ->
        chunks(request, [
          "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"bad stream\"}}\n\n"
        ])
      end)

    assert {:ok, stream} =
             Anthropic.messages(c, model: "m", max_tokens: 1, messages: [], stream: true)

    assert_raise ResponseError, ~r/bad stream/, fn -> Enum.to_list(stream) end

    c = client(fn request -> chunks(request, ["data: {broken}\n\n"]) end)
    assert {:ok, stream} = OpenAI.responses(c, model: "m", input: "hello", stream: true)
    assert_raise RequestError, fn -> Enum.to_list(stream) end
  end

  test "Req Plug adapter handles terminal and truncated SSE and Responses errors" do
    for {payload, expected} <- [
          {"event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n", :done},
          {"data: {\"type\":\"response.in_progress\"}\n\n", :incomplete},
          {"data: {\"type\":\"response.in_progress\"", :incomplete},
          {"event: response.failed\ndata: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"failed inference\"}}}\n\n",
           :failed}
        ] do
      c =
        OpenAI.init(
          base_url: "http://ollama.test",
          plug: fn conn ->
            assert conn.request_path == "/v1/responses"

            conn
            |> Plug.Conn.put_resp_content_type("text/event-stream")
            |> Plug.Conn.send_resp(200, payload)
          end
        )

      assert {:ok, stream} = OpenAI.responses(c, model: "m", input: "hello", stream: true)

      case expected do
        :done ->
          assert Enum.to_list(stream) == [%{"type" => "response.completed"}]

        :incomplete ->
          assert_raise RequestError, fn -> Enum.to_list(stream) end

        :failed ->
          assert_raise ResponseError, ~r/failed inference/, fn -> Enum.to_list(stream) end
      end
    end
  end

  test "Req Finch adapter receives SSE bytes and preserves streamed HTTP errors" do
    c = OpenAI.init("http://127.0.0.1:4000")
    assert {:ok, stream} = OpenAI.chat(c, model: "m", messages: [], stream: true)
    assert Enum.to_list(stream) == [%{"text" => "café"}]

    assert {:ok, stream} = OpenAI.chat(c, model: "unauthorized", messages: [], stream: true)
    assert_raise ResponseError, ~r/HTTP 401: access denied/, fn -> Enum.to_list(stream) end
  end

  test "multipart audio file and scalar fields are encoded with a closing boundary" do
    audio = <<0, 1, 2, 255>>

    for {operation, route} <- [
          {:audio_transcriptions, "transcriptions"},
          {:audio_translations, "translations"}
        ] do
      c =
        client(fn request ->
          assert request.url.path == "/proxy/v1/audio/" <> route

          ["multipart/form-data; boundary=" <> boundary] =
            Req.Request.get_header(request, "content-type")

          data = IO.iodata_to_binary(request.body)
          assert :binary.match(data, "name=\"model\"\r\n\r\nm\r\n") != :nomatch
          assert :binary.match(data, "filename=\"sample.wav\"") != :nomatch
          assert :binary.match(data, "Content-Type: audio/wav\r\n") != :nomatch
          assert :binary.match(data, audio) != :nomatch
          assert :binary.match(data, "--" <> boundary <> "--\r\n") != :nomatch
          assert :binary.match(data, "name=\"language\"\r\n\r\nes\r\n") != :nomatch

          if operation == :audio_translations do
            assert :binary.match(data, "name=\"to_language\"\r\n\r\nen\r\n") != :nomatch
          end

          json(request, %{"text" => "hello"})
        end)

      params = [
        model: "m",
        file: {:binary, audio, "sample.wav"},
        response_format: "json",
        language: "es"
      ]

      params =
        if operation == :audio_translations, do: params ++ [to_language: "en"], else: params

      assert {:ok, %{"text" => "hello"}} =
               apply(OpenAI, operation, [c, params])
    end
  end

  test "speech returns and streams unmodified audio bytes without wire stream flag" do
    bytes = <<0, 1, 2, 255>>

    c =
      client(fn request ->
        assert request.url.path == "/proxy/v1/audio/speech"
        refute Map.has_key?(body(request), "stream")

        if is_function(request.into) do
          chunks(request, [<<0, 1>>, <<2, 255>>])
        else
          {request,
           %Req.Response{status: 200, body: bytes, headers: %{"content-type" => ["audio/wav"]}}}
        end
      end)

    assert {:ok, ^bytes} = OpenAI.speech(c, model: "m", input: "hello")
    assert {:ok, stream} = OpenAI.speech(c, model: "m", input: "hello", stream: true)
    assert IO.iodata_to_binary(Enum.to_list(stream)) == bytes
  end

  test "invalid requests fail locally" do
    c = client(fn _ -> flunk("must not request") end)
    assert {:error, %RequestError{}} = OpenAI.chat(c, messages: [])
    assert {:error, %RequestError{}} = OpenAI.embeddings(c, model: "m", input: "x", stream: true)

    assert {:error, %RequestError{}} =
             OpenAI.transcription(c, model: "m", file: "/nonexistent/ollixir.wav")

    assert {:error, %RequestError{}} = Anthropic.messages(c, model: "m", messages: [])
  end
end
