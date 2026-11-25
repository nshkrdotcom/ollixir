# Run with: mix run examples/live/run.exs -- COMMAND
# See examples/README.md for commands and required environment variables.

unless Code.ensure_loaded?(Ollixir) do
  Mix.install([{:ollixir, path: Path.expand("../..", __DIR__)}])
end

alias Ollixir.{Anthropic, OpenAI}

client = Ollixir.init()
model = fn -> System.fetch_env!("OLLIXIR_EXAMPLE_MODEL") end
image = fn -> {:file, System.fetch_env!("OLLIXIR_EXAMPLE_IMAGE")} end
audio = fn -> {:file, System.fetch_env!("OLLIXIR_EXAMPLE_AUDIO")} end
messages = [%{role: "user", content: "Name a capital city in one sentence."}]

show = fn
  {:ok, value} -> IO.inspect(value)
  {:error, error} -> raise error
end

consume = fn
  {:ok, stream} -> Enum.each(stream, &IO.inspect/1)
  {:error, error} -> raise error
end

case Enum.drop_while(System.argv(), &(&1 == "--")) do
  ["system-one" | args] when args in [[], ["image"]] ->
    questions = [
      {"z_choice",
       %{
         type: "choice",
         instructions: "Which label applies to the customer message?",
         criteria:
           Jason.OrderedObject.new([
             {"z_refund", "The customer requests a refund"},
             {"a_other", "Any other request"}
           ])
       }},
      {"a_noul", %{type: "noul", instructions: "Is the customer asking for a refund?"}},
      {"m_score",
       %{
         type: "score",
         instructions: "How clearly does the customer state the request?",
         criteria: ["Unclear", "Clear"]
       }}
    ]

    params = [model: model.(), state: "Please refund my purchase.", questions: questions]
    params = if args == ["image"], do: Keyword.put(params, :images, [image.()]), else: params
    show.(Ollixir.system_one(client, params))

  ["embed"] ->
    show.(
      Ollixir.embed(client,
        model: model.(),
        input: ["A short caption", %{image: image.()}, %{audio: audio.()}],
        response_format: :struct
      )
    )

  ["manifests"] ->
    show.(Ollixir.show_manifests(client, model: model.(), response_format: :struct))

    case System.get_env("OLLIXIR_EXAMPLE_RUNNER") do
      nil -> :ok
      runner -> show.(Ollixir.show(client, model: model.(), runner: runner))
    end

  ["account"] ->
    for operation <- [:version, :status, :whoami] do
      case apply(Ollixir, operation, [client]) do
        {:ok, value} -> IO.inspect(value, label: to_string(operation))
        {:error, error} -> IO.puts("#{operation}: #{Exception.message(error)}")
      end
    end

  [web, url] when web in ["local-web", "hosted-web"] ->
    case web do
      "local-web" ->
        show.(Ollixir.web_search_experimental(client, query: "Elixir documentation"))
        show.(Ollixir.web_fetch_experimental(client, url: url))

      "hosted-web" ->
        key = System.fetch_env!("OLLAMA_API_KEY")
        show.(Ollixir.web_search(client, query: "Elixir documentation", api_key: key))
        show.(Ollixir.web_fetch(client, url: url, api_key: key))
    end

  ["responses"] ->
    consume.(OpenAI.responses(client, model: model.(), input: messages, stream: true))

  ["compact"] ->
    show.(OpenAI.compact(client, model: model.(), input: messages))

  ["openai-chat"] ->
    consume.(OpenAI.chat(client, model: model.(), messages: messages, stream: true))

  [operation] when operation in ["transcription", "translation"] ->
    opts = [
      model: model.(),
      file: System.fetch_env!("OLLIXIR_EXAMPLE_AUDIO"),
      response_format: "text"
    ]

    case operation do
      "transcription" -> show.(OpenAI.transcription(client, opts))
      "translation" -> show.(OpenAI.translation(client, Keyword.put(opts, :to_language, "en")))
    end

  ["speech", destination] ->
    {:ok, bytes} = OpenAI.speech(client, model: model.(), input: "Hello!", response_format: "wav")
    File.write!(destination, bytes, [:exclusive])

  ["anthropic"] ->
    consume.(
      Anthropic.messages(client,
        model: model.(),
        messages: messages,
        max_tokens: 64,
        stream: true
      )
    )

  _ ->
    raise ArgumentError, "Choose a command from the 0.2.0 examples in examples/README.md"
end
