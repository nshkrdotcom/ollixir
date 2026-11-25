defmodule Ollixir.StreamWorker do
  @moduledoc false

  alias Ollixir.{ConnectionError, RequestError, ResponseError}

  def enumerable(work, req) do
    timeout = req.options[:receive_timeout] || 60_000

    Stream.resource(
      fn -> start(work, self()) end,
      &next(&1, timeout),
      &close/1
    )
  end

  def task(work, destination, req) do
    owner = self()
    timeout = req.options[:receive_timeout] || 60_000

    Task.async(fn ->
      owner_ref = Process.monitor(owner)
      state = start(work, self())

      try do
        relay(state, destination, owner_ref, timeout)
      after
        close(state)
        Process.demonitor(owner_ref, [:flush])
      end
    end)
  end

  defp relay({pid, monitor, token, _} = state, destination, owner_ref, timeout) do
    receive do
      {^token, {:data, value}} ->
        send(destination, {self(), {:data, value}})
        send(pid, {token, :continue})
        relay(state, destination, owner_ref, timeout)

      {^token, result} ->
        result

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, stopped(reason)}

      {:DOWN, ^owner_ref, :process, _, _} ->
        {:error, stopped(:owner_down)}
    after
      timeout -> {:error, timeout_error()}
    end
  end

  def emit({owner, token}, value) do
    send(owner, {token, {:data, value}})

    receive do
      {^token, :continue} -> :ok
    end
  end

  defp start(work, owner) do
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        worker = self()
        spawn(fn -> watch_owner(owner, worker) end)
        send(owner, {token, work.({owner, token})})
      end)

    {pid, monitor, token, false}
  end

  defp watch_owner(owner, worker) do
    owner_ref = Process.monitor(owner)
    worker_ref = Process.monitor(worker)

    receive do
      {:DOWN, ^owner_ref, :process, ^owner, _} -> Process.exit(worker, :kill)
      {:DOWN, ^worker_ref, :process, ^worker, _} -> :ok
    end
  end

  defp next({pid, monitor, token, acknowledge?}, timeout) do
    if acknowledge?, do: send(pid, {token, :continue})

    receive do
      {^token, {:data, value}} ->
        {[value], {pid, monitor, token, true}}

      {^token, {:ok, _}} ->
        {:halt, {pid, monitor, token, false}}

      {^token, {:error, error}} ->
        raise error

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        raise stopped(reason)
    after
      timeout -> raise timeout_error()
    end
  end

  defp stopped(reason),
    do: RequestError.exception(message: "Stream worker stopped", reason: reason)

  defp timeout_error,
    do: RequestError.exception(message: "Timed out waiting for a stream frame", reason: :timeout)

  defp close({pid, monitor, token, _acknowledge?}) do
    # Wait for the worker to stop before purging messages it already sent.
    # Use a new monitor because next/2 may have consumed the first DOWN.
    cleanup = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^cleanup, :process, ^pid, _} -> :ok
    end

    Process.demonitor(monitor, [:flush])

    receive do
      {^token, _} -> :ok
    after
      0 -> :ok
    end
  end

  def run(fun) do
    fun.()
  rescue
    error in [ConnectionError, RequestError, ResponseError] ->
      {:error, error}

    error ->
      {:error,
       RequestError.exception(
         message: "Stream request failed",
         reason: {:exception, error.__struct__}
       )}
  catch
    kind, _reason ->
      {:error, RequestError.exception(message: "Stream worker stopped", reason: kind)}
  end
end
