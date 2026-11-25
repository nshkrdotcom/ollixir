# System One

`Ollixir.system_one/2` calls Ollama's non-streaming `POST /v1/systemone`
endpoint. It evaluates a state using a compatible decision model and a set of
named questions. It is not the same as native chat or JSON-schema generation.
Availability depends on the server, runner, and installed model.

```elixir
client = Ollixir.init()

{:ok, result} = Ollixir.system_one(client,
  model: "your-decision-model",
  state: "A customer reported a broken handle.",
  questions: [
    {"damaged", %{type: "noul", instructions: "Is the product damaged?"}},
    {"category", %{
      type: "choice",
      instructions: "Classify the report.",
      criteria: %{"damage" => "Physical damage", "other" => "Other"}
    }}
  ]
)

IO.inspect(result["answers"])
```

The state and instructions may be strings, JSON objects, or arrays. A list of
`{name, question}` pairs encodes as a JSON object in the supplied order. A map
is convenient if question order does not matter. Do not duplicate names.
Question types include `"noul"` (numeric probability), `"choice"` (categorical),
and `"score"` (ordered scoring criteria). For score questions, use a list of
criteria in the model's expected order. Choice and optional noul criteria are
objects; `Jason.OrderedObject.new/1` can preserve a specific criteria order.
The model/server validates the precise criteria and question constraints.

Optional `runner`, `keep_alive`, and `images` follow the native API. Images use
Ollixir's normal image encoding. Video is not supported by current local
runners; passing a reserved field does not make video inference available.

With `response_format: :struct`, the result is an
`Ollixir.Types.SystemOneResponse` with `model`, `answers`, `usage`, and
`prompt_eval_cached_count` fields. Answer objects remain provider-shaped maps;
`noul` is a number, not an Elixir boolean. Do not assume a particular answer or
confidence threshold without validating the model's behavior.

Invalid local inputs return `{:error, %Ollixir.RequestError{}}`; non-success
HTTP responses return `{:error, %Ollixir.ResponseError{}}`. There is no
`stream` option for System One.
