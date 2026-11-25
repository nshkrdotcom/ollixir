defmodule Ollixir.SSE do
  @moduledoc false

  # A transport chunk is not an SSE event. Keep an incomplete line and the
  # current event's data fields across callbacks. Split before JSON decoding,
  # so a UTF-8 character may safely straddle two chunks.
  def new do
    %{buffer: "", event: nil, data: [], terminal: false, seen: false, error: nil}
  end

  def feed(%{terminal: true} = state, _chunk), do: {[], state}
  def feed(%{error: error} = state, _chunk) when not is_nil(error), do: {[], state}

  def feed(state, chunk) when is_binary(chunk) do
    lines = :binary.split(state.buffer <> chunk, "\n", [:global])
    {buffer, lines} = List.pop_at(lines, -1)

    {events, state} =
      Enum.reduce_while(lines, {[], %{state | buffer: buffer}}, fn line, {events, state} ->
        case consume_line(trim_cr(line), state) do
          {:continue, state} -> {:cont, {events, state}}
          {:event, event, state} -> {:cont, {[event | events], state}}
          {:stop, state} -> {:halt, {events, %{state | buffer: ""}}}
        end
      end)

    {Enum.reverse(events), state}
  end

  def finish(%{error: error}) when not is_nil(error), do: {:error, error}
  def finish(%{terminal: true}), do: :ok
  def finish(%{buffer: "", data: [], seen: true}), do: {:error, :missing_terminal_event}
  def finish(%{seen: false}), do: {:error, :empty_or_incomplete_stream}
  def finish(_), do: {:error, :incomplete_event}

  defp trim_cr(<<>>), do: ""

  defp trim_cr(line) do
    if :binary.last(line) == 13 do
      binary_part(line, 0, byte_size(line) - 1)
    else
      line
    end
  end

  defp consume_line("", %{data: []} = state), do: {:continue, %{state | event: nil}}

  defp consume_line("", state) do
    payload = state.data |> Enum.reverse() |> Enum.join("\n")
    next = %{state | data: [], event: nil, seen: true}

    case payload do
      "[DONE]" ->
        {:stop, %{next | terminal: true}}

      _ ->
        case Jason.decode(payload) do
          {:ok, value} when is_map(value) -> {:event, {state.event, value}, next}
          _ -> {:stop, %{next | error: :invalid_event_json}}
        end
    end
  end

  defp consume_line(<<":", _::binary>>, state), do: {:continue, state}

  defp consume_line(line, state) do
    {field, value} =
      case :binary.split(line, ":") do
        [field, <<" ", value::binary>>] -> {field, value}
        [field, value] -> {field, value}
        [field] -> {field, ""}
      end

    case field do
      "event" -> {:continue, %{state | event: value}}
      "data" -> {:continue, %{state | data: [value | state.data]}}
      _ -> {:continue, state}
    end
  end
end
