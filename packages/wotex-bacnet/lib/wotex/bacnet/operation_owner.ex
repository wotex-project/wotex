defmodule Wotex.BACnet.OperationOwner do
  @moduledoc false

  use GenServer

  alias Wotex.BACnet.{BACstack, Error, StackOwner}

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    case GenServer.start(__MODULE__, {config, self()}) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc false
  @spec request(pid(), reference(), map(), integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(pid, generation, message, deadline) do
    GenServer.call(pid, {:request, generation, message, deadline}, :infinity)
  catch
    :exit, _ -> failure(:connection_closed, message)
  end

  @doc false
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid, :normal, 1100)
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def init({config, owner}) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       config: config,
       owner: Process.monitor(owner),
       client: Process.monitor(config.client),
       pending: %{}
     }}
  end

  @impl GenServer
  def handle_call({:request, generation, message, deadline}, from, state) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      generation != state.config.generation ->
        {:reply, {:error, Error.new(:connection_closed)}, state}

      remaining <= 0 ->
        {:reply, {:error, Error.new(:deadline_exceeded)}, state}

      map_size(state.pending) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        {:noreply, admit(state, from, message, deadline, remaining)}
    end
  end

  @impl GenServer
  def handle_info({:result, reference, result}, state) do
    case Map.pop(state.pending, reference) do
      {nil, _} ->
        {:noreply, state}

      {operation, pending} ->
        release(operation)
        expired = System.monotonic_time(:millisecond) >= operation.deadline
        reply = if expired, do: failure(:deadline_exceeded, operation.message), else: result
        GenServer.reply(operation.from, reply)
        next = %{state | pending: pending}
        if expired and state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
    end
  end

  def handle_info({:timeout, reference}, state) do
    case Map.pop(state.pending, reference) do
      {nil, _} ->
        {:noreply, state}

      {operation, pending} ->
        stop_worker(operation)
        GenServer.reply(operation.from, failure(:deadline_exceeded, operation.message))
        next = %{state | pending: pending}
        if state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
    end
  end

  def handle_info({:DOWN, reference, :process, _, _}, %{owner: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, _, _}, %{client: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, _, _}, state) do
    case Enum.find(state.pending, fn {_, op} -> reference in [op.caller, op.worker_monitor] end) do
      nil ->
        {:noreply, state}

      {key, operation} ->
        stop_worker(operation)

        if reference == operation.worker_monitor,
          do: GenServer.reply(operation.from, failure(:connection_closed, operation.message))

        next = %{state | pending: Map.delete(state.pending, key)}
        if state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
    end
  end

  def handle_info({:EXIT, _, _}, state), do: {:stop, :normal, state}
  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    Enum.each(state.pending, fn {_, operation} ->
      stop_worker(operation)
      GenServer.reply(operation.from, failure(:connection_closed, operation.message))
    end)

    if state.config.owned_stack, do: StackOwner.close(state.config.owned_stack)
    :ok
  end

  defp admit(state, from, message, deadline, remaining) do
    receiver = self()
    reference = make_ref()
    caller = Process.monitor(elem(from, 0))

    {worker, monitor} =
      spawn_monitor(fn ->
        result = BACstack.exchange(state.config, message, deadline)
        send(receiver, {:result, reference, result})
      end)

    operation = %{
      from: from,
      caller: caller,
      worker: worker,
      worker_monitor: monitor,
      message: message,
      deadline: deadline,
      timer: Process.send_after(self(), {:timeout, reference}, remaining)
    }

    %{state | pending: Map.put(state.pending, reference, operation)}
  end

  defp failure(code, %{type: :write_property}),
    do: {:error, %{Error.new(code) | effect: :unknown}}

  defp failure(code, _), do: {:error, Error.new(code)}

  defp stop_worker(operation) do
    Process.exit(operation.worker, :kill)
    release(operation)
  end

  defp release(operation) do
    Process.cancel_timer(operation.timer)
    Process.demonitor(operation.caller, [:flush])
    Process.demonitor(operation.worker_monitor, [:flush])
  end
end
