defmodule OllixirReleaseLive do
  import ExUnit.Assertions

  alias Ollixir.{Anthropic, HuggingFace, OpenAI, ResponseError}

  def main(profile) do
    client =
      Ollixir.init(
        host: System.fetch_env!("OLLIXIR_RELEASE_LIVE_HOST"),
        api_key: nil,
        receive_timeout: 300_000
      )

    assert %{"version" => "0.40.18"} = ok(Ollixir.version(client))
    assert ok(Ollixir.heartbeat(client)) == true

    output = System.fetch_env!("LIVE_OUTPUT")
    File.mkdir_p!(output)

    failures =
      for {name, check} <- checks(profile, client, output), reduce: [] do
        failures ->
          IO.puts("RUN  #{name}")

          try do
            check.()
            IO.puts("PASS #{name}")
            failures
          rescue
            error ->
              detail =
                if profile in ["cloud", "push"],
                  do: inspect(error.__struct__),
                  else: Exception.message(error)

              IO.puts(:stderr, "FAIL #{name} — #{detail}")
              [name | failures]
          end
      end

    if failures != [] do
      IO.puts(:stderr, "Failed checks: #{Enum.join(Enum.reverse(failures), ", ")}")
      System.halt(1)
    end

    IO.puts("PASS #{profile} profile")
  end

  defp checks("check", c, output) do
    [
      {"Inventory, discovery, native and OpenAI model metadata", fn -> discovery(c, output) end},
      {"Native generate, NDJSON and Task chat", fn -> native(c) end},
      {"Native thinking", fn -> thinking(c) end},
      {"Native JSON format", fn -> structured(c) end},
      {"Native tool call and result history", fn -> tools(c) end},
      {"Fill-in-the-middle", fn -> fim(c) end},
      {"Text and legacy embeddings, OpenAI base64 embeddings", fn -> embeddings(c) end},
      {"Disposable create, streamed progress, copy, load, unload, delete and blob",
       fn -> models(c) end},
      {"OpenAI chat, completions, Responses and compact, Anthropic Messages",
       fn -> compatibility(c) end},
      {"Native vision", fn -> vision(c) end},
      {"System One ordered text questions", fn -> decision(c) end},
      {"System One image input", fn -> decision_image(c) end},
      {"Speech WAV/PCM and audio fixtures", fn -> speech(c, output) end},
      {"Transcription JSON/text/verbose and SSE", fn -> transcription(c, output) end},
      {"French-to-English translation", fn -> translation(c, output) end},
      {"Mixed text, image and audio embeddings", fn -> mixed(c, output) end},
      {"Missing native and OpenAI models produce HTTP errors", fn -> errors(c) end},
      {"Cloud-disabled account discovery", fn -> disabled_account(c) end}
    ]
  end

  defp checks("registry", c, _) do
    [
      {"Ollama registry pull",
       fn ->
         assert %{"status" => "success"} =
                  c
                  |> Ollixir.pull(model: model("EMBED"), stream: true)
                  |> ok()
                  |> Enum.to_list()
                  |> List.last()
       end}
    ]
  end

  defp checks("hf", c, _) do
    [
      {"Hugging Face pull, chat and generate",
       fn ->
         repo = "bartowski/Llama-3.2-1B-Instruct-GGUF"
         opts = [quantization: "IQ4_XS", keep_alive: 0, options: %{num_predict: 32}]

         assert %{"status" => "success"} =
                  c
                  |> HuggingFace.pull(repo, quantization: "IQ4_XS", stream: true)
                  |> ok()
                  |> Enum.to_list()
                  |> List.last()

         text!(get_in(ok(HuggingFace.chat(c, repo, messages(), opts)), ["message", "content"]))
         text!(ok(HuggingFace.generate(c, repo, "Hello", opts))["response"])
       end}
    ]
  end

  defp checks("cloud", c, _) do
    [
      {"Signed-in account, quota and recommendations",
       fn ->
         assert is_map(ok(Ollixir.whoami(c)))
         assert is_map(ok(Ollixir.balance(c)))
         assert is_map(ok(Ollixir.usage(c)))
         assert is_map(ok(Ollixir.model_recommendations(c)))
       end},
      {"Signed-in server web proxy",
       fn ->
         search!(ok(Ollixir.web_search_experimental(c, query: "Elixir programming language")))
         fetch!(ok(Ollixir.web_fetch_experimental(c, url: "https://elixir-lang.org/")))
       end},
      {"Direct hosted web",
       fn ->
         key = System.fetch_env!("OLLAMA_API_KEY")

         search!(
           ok(
             Ollixir.web_search(c,
               query: "Elixir programming language",
               base_url: "https://ollama.com/api",
               api_key: key
             )
           )
         )

         fetch!(
           ok(
             Ollixir.web_fetch(c,
               url: "https://elixir-lang.org/",
               base_url: "https://ollama.com/api",
               api_key: key
             )
           )
         )
       end}
    ]
  end

  defp checks("push", c, _) do
    [
      {"Authorized disposable registry push",
       fn ->
         target = System.fetch_env!("LIVE_PUSH_TARGET")
         assert Regex.match?(~r/\A[a-z0-9_.-]+\/ollixir-audit-[a-z0-9-]+:[a-z0-9_.-]+\z/, target)
         assert absent?(c, target)

         try do
           assert ok(Ollixir.copy(c, source: model("TEXT"), destination: target)) == true

           assert %{"status" => "success"} =
                    c
                    |> Ollixir.push(model: target, stream: true)
                    |> ok()
                    |> Enum.to_list()
                    |> List.last()
         after
           delete_if_present(c, target)
         end
       end}
    ]
  end

  defp discovery(c, output) do
    models = ok(Ollixir.list(c))["models"]
    assert is_list(models) and models != []

    File.write!(
      Path.join(output, "inventory.json"),
      Jason.encode!(%{ollama: "0.40.18", models: models}, pretty: true)
    )

    assert is_list(ok(Ollixir.ps(c))["models"])
    assert is_map(ok(Ollixir.show(c, model: model("TEXT"))))

    assert %Ollixir.Types.ShowManifestsResponse{manifests: [_ | _]} =
             ok(Ollixir.show_manifests(c, model: model("TEXT"), response_format: :struct))

    assert [_ | _] = ok(OpenAI.models(c))["data"]
    assert is_map(ok(OpenAI.model(c, model("TEXT"))))
  end

  defp native(c) do
    opts = [
      model: model("TEXT"),
      prompt: "Say hello in a short sentence.",
      think: false,
      keep_alive: 0,
      options: %{num_predict: 48}
    ]

    assert %{"done" => true, "response" => response} = ok(Ollixir.generate(c, opts))
    text!(response)

    frames = c |> Ollixir.generate(opts ++ [stream: true]) |> ok() |> Enum.to_list()
    assert List.last(frames)["done"]
    text!(Enum.map_join(frames, & &1["response"]))

    task =
      ok(
        Ollixir.chat(c,
          model: model("TEXT"),
          messages: messages(),
          think: false,
          keep_alive: 0,
          options: %{num_predict: 48},
          stream: self()
        )
      )

    assert %{"done" => true, "message" => %{"content" => content}} = ok(Task.await(task, 360_000))
    text!(content)
    pid = task.pid
    assert_receive {^pid, {:data, %{"message" => _}}}
    drain(pid)
  end

  defp thinking(c) do
    answer =
      ok(
        Ollixir.generate(c,
          model: model("TEXT"),
          prompt: "What is 2 plus 2? Give the answer briefly.",
          think: true,
          keep_alive: 0,
          options: %{num_predict: 1024}
        )
      )

    text!(answer["thinking"], "Expected thinking text")

    text!(
      answer["response"],
      "Expected a final answer after thinking (done_reason: #{inspect(answer["done_reason"])})"
    )
  end

  defp structured(c) do
    opts = [model: model("TEXT"), keep_alive: 0, options: %{num_predict: 128}]

    data =
      ok(
        Ollixir.generate(
          c,
          opts ++
            [
              prompt: ~s(Return a JSON object with key "city" and value "Paris".),
              format: "json",
              think: false
            ]
        )
      )

    assert %{"city" => city} = Jason.decode!(data["response"])
    assert String.downcase(city) == "paris"
  end

  defp tools(c) do
    opts = [model: model("TEXT"), keep_alive: 0, options: %{num_predict: 256}]
    history = [%{role: "user", content: "Use the lookup tool to find the temperature in Paris."}]

    tool = %{
      type: "function",
      function: %{
        name: "lookup",
        description: "Read the current temperature for a city",
        parameters: %{type: "object", properties: %{city: %{type: "string"}}, required: ["city"]}
      }
    }

    chat = opts ++ [tools: [tool], think: false]

    assert %{
             "message" =>
               %{
                 "tool_calls" => [%{"function" => %{"name" => "lookup", "arguments" => args}} | _]
               } = message
           } =
             ok(Ollixir.chat(c, chat ++ [messages: history]))

    assert is_map(args)
    result = %{role: "tool", tool_name: "lookup", content: "Paris is 18 degrees Celsius."}

    text!(
      get_in(
        ok(Ollixir.chat(c, opts ++ [think: false, messages: history ++ [message, result]])),
        [
          "message",
          "content"
        ]
      )
    )
  end

  defp fim(c) do
    response =
      ok(
        Ollixir.generate(c,
          model: model("FIM"),
          prompt: "def add(a, b):\n    ",
          suffix: "\n\nprint(add(1, 2))",
          keep_alive: 0,
          options: %{num_predict: 32}
        )
      )

    text!(response["response"])
  end

  defp embeddings(c) do
    opts = [model: model("EMBED"), keep_alive: 0]

    assert %Ollixir.Types.EmbedResponse{embeddings: vectors} =
             ok(Ollixir.embed(c, opts ++ [input: ["one", "two"], response_format: :struct]))

    vectors!(vectors, 2)
    assert Enum.at(vectors, 0) != Enum.at(vectors, 1)

    assert %{"embedding" => vector} =
             ok(apply(Ollixir, :embeddings, [c, opts ++ [prompt: "one"]]))

    vectors!([vector], 1)

    assert %{"data" => [%{"embedding" => base64}]} =
             ok(OpenAI.embed(c, model: model("EMBED"), input: "one", encoding_format: "base64"))

    assert {:ok, <<_, _, _, _, _::binary>>} = Base.decode64(base64)
  end

  defp models(c) do
    name = "ollixir-audit-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
    copy = name <> "-copy"
    bytes = "fixture " <> name
    digest = Ollixir.Blob.digest(bytes)
    assert ok(Ollixir.check_blob(c, digest)) == false
    assert ok(Ollixir.create_blob(c, {:binary, bytes})) == digest
    assert ok(Ollixir.check_blob(c, digest)) == true
    assert absent?(c, name) and absent?(c, copy)

    try do
      assert %{"status" => "success"} =
               c
               |> Ollixir.create(
                 model: name,
                 from: model("TEXT"),
                 system: "Answer briefly.",
                 stream: true
               )
               |> ok()
               |> Enum.to_list()
               |> List.last()

      assert ok(Ollixir.copy(c, source: name, destination: copy)) == true
      assert ok(Ollixir.preload(c, model: copy, keep_alive: "2m")) == true
      assert Enum.any?(ok(Ollixir.ps(c))["models"], &(&1["name"] in [copy, copy <> ":latest"]))
      assert ok(Ollixir.unload(c, model: copy)) == true
      assert ok(Ollixir.delete(c, model: copy)) == true
      assert absent?(c, copy)
      assert ok(Ollixir.delete(c, model: name)) == true
      assert absent?(c, name)
    after
      delete_if_present(c, copy)
      delete_if_present(c, name)
    end
  end

  defp compatibility(c) do
    model = model("TEXT")
    opts = [model: model, messages: messages(), max_tokens: 64, think: false]
    assert [_ | _] = ok(OpenAI.chat(c, opts))["choices"]
    assert [_ | _] = c |> OpenAI.chat(opts ++ [stream: true]) |> ok() |> Enum.to_list()

    assert [_ | _] =
             c
             |> OpenAI.completions(model: model, prompt: "Hello", max_tokens: 24, stream: true)
             |> ok()
             |> Enum.to_list()

    response = [model: model, input: messages(), max_output_tokens: 96, think: false]
    assert is_map(ok(OpenAI.responses(c, response)))
    events = c |> OpenAI.responses(response ++ [stream: true]) |> ok() |> Enum.to_list()
    assert List.last(events)["type"] in ["response.completed", "response.incomplete"]
    assert is_map(ok(OpenAI.compact(c, model: model, input: messages())))

    events =
      c
      |> Anthropic.messages(model: model, messages: messages(), max_tokens: 64, stream: true)
      |> ok()
      |> Enum.to_list()

    assert List.last(events)["type"] == "message_stop"
  end

  defp vision(c) do
    response =
      ok(
        Ollixir.chat(c,
          model: model("VISION"),
          keep_alive: 0,
          options: %{num_predict: 48},
          messages: [%{role: "user", content: "Describe this image.", images: [{:file, image()}]}]
        )
      )

    text!(get_in(response, ["message", "content"]))
  end

  defp decision(c) do
    questions = [
      {"z_choice",
       %{
         type: "choice",
         instructions: "Classify this request.",
         criteria: Jason.OrderedObject.new([{"z_refund", "Refund"}, {"a_other", "Other"}])
       }},
      {"a_noul", %{type: "noul", instructions: "Is a refund requested?"}},
      {"m_score",
       %{
         type: "score",
         instructions: "How clear is the request?",
         criteria: ["Unclear", "Clear", "Very clear"]
       }}
    ]

    state = "Please refund my purchase."

    assert %{
             "answers" => %{
               "z_choice" => %{"choice" => choice},
               "a_noul" => %{"noul" => probability},
               "m_score" => %{"score" => _}
             },
             "usage" => %{"input_tokens" => tokens}
           } =
             ok(
               Ollixir.system_one(c,
                 model: model("DECISION"),
                 state: state,
                 questions: questions,
                 keep_alive: 0
               )
             )

    assert choice in ["z_refund", "a_other"]
    assert is_number(probability) and probability >= 0 and probability <= 1
    assert tokens > 0
  end

  defp decision_image(c) do
    assert %{"answers" => %{"image" => %{"noul" => probability}}} =
             ok(
               Ollixir.system_one(c,
                 model: model("DECISION_IMAGE"),
                 state: "A repository illustration",
                 images: [{:file, image()}],
                 keep_alive: 0,
                 questions: [
                   {"image", %{type: "noul", instructions: "Is there lettering in the image?"}}
                 ]
               )
             )

    assert is_number(probability) and probability >= 0 and probability <= 1
  end

  defp speech(c, output) do
    english = Path.join(output, "speech-english.wav")
    french = Path.join(output, "speech-french.wav")
    File.rm(english)
    File.rm(french)
    sample(c, model("SPEECH"), model("SPEECH_VOICE"), "The capital of France is Paris.", english)

    sample(
      c,
      model("SPEECH_FR"),
      model("SPEECH_FR_VOICE"),
      "La capitale de la France est Paris.",
      french
    )
  end

  defp transcription(c, output) do
    opts = [
      model: model("ASR"),
      file: fixture(output, "english.wav", "LIVE_ENGLISH_WAV"),
      language: "en"
    ]

    assert %{"text" => text} = ok(OpenAI.transcription(c, opts))
    assert contains_paris?(text)
    assert contains_paris?(ok(OpenAI.transcription(c, opts ++ [response_format: "text"])))

    assert %{"text" => text, "segments" => [_ | _]} =
             ok(OpenAI.transcription(c, opts ++ [response_format: "verbose_json"]))

    assert contains_paris?(text)

    events = OpenAI.transcription(c, opts ++ [stream: true]) |> ok() |> Enum.to_list()
    assert %{"type" => "transcript.text.done", "text" => text} = List.last(events)
    assert contains_paris?(text)
  end

  defp translation(c, output) do
    french = fixture(output, "french.wav", "LIVE_FRENCH_WAV")

    assert %{"text" => translation} =
             ok(
               OpenAI.translation(c,
                 model: model("ASR"),
                 file: french,
                 language: "fr",
                 to_language: "en"
               )
             )

    assert contains_paris?(translation) and
             String.contains?(String.downcase(translation), "capital of")
  end

  defp sample(c, model, voice, text, path) do
    assert <<"RIFF", _::binary-size(4), "WAVE", _::binary>> =
             ok(OpenAI.speech(c, model: model, voice: voice, input: text, response_format: "wav"))

    pcm =
      c
      |> OpenAI.speech(
        model: model,
        voice: voice,
        input: text,
        response_format: "pcm",
        stream: true
      )
      |> ok()
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    size = byte_size(pcm)
    assert size > 0 and rem(size, 2) == 0

    # Stable speech PCM is 24 kHz, signed 16-bit mono. Record the known
    # sizes, since the server's streaming WAV header cannot know them.
    File.write!(
      path,
      <<"RIFF", 36 + size::little-32, "WAVEfmt ", 16::little-32, 1::little-16, 1::little-16,
        24_000::little-32, 48_000::little-32, 2::little-16, 16::little-16, "data",
        size::little-32, pcm::binary>>
    )
  end

  defp mixed(c, output) do
    path = fixture(output, "english.wav", "LIVE_ENGLISH_WAV")

    assert %{"embeddings" => vectors} =
             ok(
               Ollixir.embed(c,
                 model: model("MULTIMODAL"),
                 keep_alive: 0,
                 input: ["A caption", %{image: {:file, image()}}, %{audio: {:file, path}}]
               )
             )

    vectors!(vectors, 3)
  end

  defp fixture(output, filename, variable) do
    independent = Path.join(output, filename)
    generated = Path.join(output, "speech-" <> filename)

    path =
      System.get_env(variable) || if(File.regular?(independent), do: independent, else: generated)

    assert File.regular?(path), "Missing audio fixture. Fix the speech check or set #{variable}."
    path
  end

  defp errors(c) do
    name = "ollixir-audit-nonexistent-model:latest"

    assert {:error, %ResponseError{status: 404}} =
             Ollixir.generate(c, model: name, prompt: "Hello")

    assert {:error, %ResponseError{status: 404}} = OpenAI.model(c, name)
  end

  defp disabled_account(c) do
    assert %{"cloud" => %{"disabled" => true}} = ok(Ollixir.status(c))
    assert {:error, %ResponseError{status: status}} = Ollixir.whoami(c)
    assert status in [401, 503]
  end

  defp absent?(c, name) do
    case Ollixir.show(c, model: name) do
      {:error, %ResponseError{status: 404}} -> true
      {:ok, _} -> false
      error -> ok(error)
    end
  end

  defp delete_if_present(c, name) do
    unless absent?(c, name), do: assert(ok(Ollixir.delete(c, model: name)) == true)
  end

  defp vectors!(vectors, count) do
    assert length(vectors) == count
    assert Enum.all?(vectors, fn vector -> vector != [] and Enum.all?(vector, &is_number/1) end)
    assert length(Enum.uniq(Enum.map(vectors, &length/1))) == 1
  end

  defp search!(%{results: [first | _]}), do: text!(first.url)
  defp search!(_), do: flunk("Expected at least one web search result")
  defp fetch!(page), do: text!(page.content)

  defp contains_paris?(text),
    do: is_binary(text) and String.contains?(String.downcase(text), "paris")

  defp text!(text, message \\ "Expected nonempty text"),
    do: assert(is_binary(text) and String.trim(text) != "", message)

  defp model(role), do: System.fetch_env!("LIVE_" <> role)
  defp image, do: System.get_env("LIVE_IMAGE", Path.expand("../../assets/ollixir.png", __DIR__))
  defp messages, do: [%{role: "user", content: "Say hello in one sentence."}]

  defp drain(pid) do
    receive do
      {^pid, {:data, _}} -> drain(pid)
    after
      0 -> :ok
    end
  end

  defp ok({:ok, value}), do: value
  defp ok({:error, error}) when is_exception(error), do: raise(error)
  defp ok(other), do: flunk("Expected successful response, got #{inspect(other)}")
end

[profile] = Enum.reject(System.argv(), &(&1 == "--"))
OllixirReleaseLive.main(profile)
