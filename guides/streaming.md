# Streaming Responses

Ollama supports streaming for real-time response delivery. The Elixir client
provides two streaming modes to fit different use cases.

## Overview

| Mode | Option | Returns | Best For |
|------|--------|---------|----------|
| Enumerable | `stream: true` | `{:ok, enumerable}` | Scripts, one-off processing |
| Process | `stream: pid` | `{:ok, task}` | GenServers, LiveView |

## Enumerable Mode

With `stream: true`, the request starts when you enumerate the stream.

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "llama3.2",
  messages: messages,
  stream: true
)

# Process each chunk as it arrives
stream
|> Stream.each(fn chunk ->
  IO.write(chunk["message"]["content"] || "")
end)
|> Stream.run()
```

### Pros
- Simple enumeration with `Enum` or `Stream`
- Easy to compose with other Stream operations
- Works well in scripts and one-off tasks

Enumeration blocks the calling process while waiting for chunks. Use process
mode when a GenServer or LiveView must stay responsive.

### Collecting Results

```elixir
full_response = Enum.map_join(stream, fn chunk ->
  get_in(chunk, ["message", "content"]) || ""
end)
```

## Process Mode

When `stream: pid`, messages are sent to the specified process.

```elixir
{:ok, task} = Ollixir.chat(client,
  model: "llama3.2",
  messages: messages,
  stream: self()
)

# Messages arrive as:
# {task_pid, {:data, %{"message" => ..., "done" => false}}}
# {task_pid, {:data, %{"message" => ..., "done" => true}}}
# {task_ref, {:ok, %{"message" => %{"content" => full_response}, "done" => true}}}
```

### Pros
- Non-blocking for the caller
- Lets GenServer and LiveView callbacks return while the request runs

### Cons
- More setup required
- The returned task is linked to its caller. Handle chunk messages and the
  task result, and consume the receiver mailbox promptly.

## Phoenix LiveView Integration

Process mode is ideal for LiveView:

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView

  def handle_event("send", %{"message" => msg}, socket) do
    messages = socket.assigns.messages ++ [%{role: "user", content: msg}]

    {:ok, task} = Ollixir.chat(socket.assigns.client,
      model: "llama3.2",
      messages: messages,
      stream: self()
    )

    {:noreply, assign(socket,
      messages: messages,
      streaming: true,
      current_response: "",
      task: task
    )}
  end

  def handle_info({pid, {:data, chunk}}, %{assigns: %{task: %Task{pid: pid}}} = socket) do
    content = get_in(chunk, ["message", "content"]) || ""
    {:noreply, update(socket, :current_response, &(&1 <> content))}
  end

  def handle_info({ref, result}, %{assigns: %{task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, streaming: false, current_response: "", task: nil)

    case result do
      {:ok, %{"message" => %{"content" => content}}} ->
        message = %{role: "assistant", content: content}
        {:noreply, update(socket, :messages, &(&1 ++ [message]))}

      {:error, reason} ->
        {:noreply, assign(socket, error: Exception.message(reason))}
    end
  end
end
```

## Error Handling

### Enumerable Mode

```elixir
try do
  stream |> Stream.each(&process/1) |> Stream.run()
rescue
  e in [Ollixir.ConnectionError, Ollixir.RequestError, Ollixir.ResponseError] ->
    Logger.error("Stream error: #{e.message}")
end
```

### Process Mode

The linked task reports `{:error, reason}` on failure. In a script, use
`Task.await/2` for the result. In a callback, match the task reference as in
the LiveView example above.

## Typed Streaming (Optional)

When `response_format: :struct` is set, streaming chunks are delivered as
typed structs instead of maps:

```elixir
{:ok, stream} = Ollixir.chat(client,
  model: "llama3.2",
  messages: messages,
  stream: true,
  response_format: :struct
)
```

## Choosing a Mode

```
┌─────────────────────────────────────────┐
│ Are you in a GenServer/LiveView?        │
└────────────────┬────────────────────────┘
                 │
         ┌───────┴───────┐
         │ Yes           │ No
         ▼               ▼
    ┌────────────┐  ┌────────────┐
    │ Use        │  │ Use        │
    │ stream:    │  │ stream:    │
    │ self()     │  │ true       │
    └────────────┘  └────────────┘
```

## Framing and compatibility clients

Native Ollama uses newline-delimited JSON. Ollixir 0.2.0 buffers partial lines
across HTTP chunks and supports multiple JSON records per chunk. The native
PID task merges text, thinking, tool-call and logprob chunks in its final
response. Enumerable mode emits individual chunks and raises on stream errors.
Stopping enumeration early shuts down its worker. Native chat and generate
streams require a final `done: true` record, except for render-debug responses.

`Ollixir.OpenAI` and `Ollixir.Anthropic` use SSE for provider events. Their
PID tasks return `{:ok, :done}` after the stream's completion marker, or an
error if the connection closes first. SSE payloads arrive individually. Speech
streams raw binary chunks. See the
[OpenAI](openai-compatibility.md) and [Anthropic](anthropic-compatibility.md)
compatibility guides for complete examples.

Native inference streams must end with `done: true` (or a render-debug
result); pull, push and create must end with `status: "success"`. A truncated
stream raises during enumeration or returns an error from its PID task.
Native POST/DELETE requests and compatibility streams are not automatically
retried, because an interrupted request may already have changed server state.
Use explicit retries only when repeating the operation is safe.

Lazy enumeration requests one decoded frame at a time and cancels its worker
when the consumer halts or exits. Both stream modes use the configured
`receive_timeout` as the maximum wait for the next decoded frame or terminal
result. A PID receiver should consume its mailbox promptly. The returned
`Task` remains linked to its caller and forwards chunks to the receiver
without waiting for acknowledgements from that receiver.
