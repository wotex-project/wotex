defmodule Wotex.Runtime.SubscriptionOpening do
  @moduledoc """
  Keeps subscription establishment interruptible while a consumer callback runs.

  A Runtime subscription explicitly starts this guardian with its own PID and
  a callback. The guardian monitors that owner and runs the callback in a linked,
  monitored worker. Only the matching owner and reference may claim a completed
  result or cancel the attempt. Cancellation returns an unclaimed result, when
  available, so the subscription can clean up its original transport handle.

  After the callback returns, the worker remains as a link endpoint for any
  transport it started, without retaining the callback closure. Abnormal linked
  transport exits are reported to the subscription. Owner death or cancellation
  terminates the worker; the subscription owns transport-specific cleanup.
  Status formatting omits callback state and result contents.

  This is an implementation component of `Wotex.Runtime.Subscription`.
  Consumers start subscriptions through the ConsumedThing child specification
  rather than using guardian handles as an application API.
  """

  use GenServer

  @doc false
  @spec start(pid(), (-> term())) :: {:ok, map()} | {:error, term()}
  def start(owner, function) do
    reference = make_ref()

    case GenServer.start(__MODULE__, {owner, reference, function}) do
      {:ok, pid} -> {:ok, %{pid: pid, reference: reference, monitor: Process.monitor(pid)}}
      error -> {:error, error}
    end
  end

  @doc false
  @spec claim(map()) :: term()
  def claim(opening), do: call(opening, :claim)

  @doc false
  @spec cancel(map()) :: term()
  def cancel(opening), do: call(opening, :cancel)

  @impl GenServer
  def init({owner, reference, function}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)
    guardian = self()

    {worker, worker_monitor} =
      :erlang.spawn_opt(fn -> run(guardian, reference, function) end, [:link, :monitor])

    {:ok,
     %{
       owner: owner,
       reference: reference,
       monitor: monitor,
       worker: worker,
       worker_monitor: worker_monitor,
       result: :pending,
       claimed?: false
     }}
  end

  @impl GenServer
  def handle_call(
        {reference, :claim},
        {owner, _ignored_1},
        %{reference: reference, owner: owner, claimed?: false, result: result} = state
      )
      when result != :pending do
    {:reply, result, %{state | result: nil, claimed?: true}}
  end

  def handle_call(
        {reference, :cancel},
        {owner, _ignored_2},
        %{reference: reference, owner: owner} = state
      ) do
    state = stop_worker(state)
    result = if state.claimed? or state.result == :pending, do: :none, else: state.result
    {:reply, result, %{state | result: nil, claimed?: true}}
  end

  def handle_call(_ignored_3, _ignored_4, state), do: {:reply, :none, state}

  @impl GenServer
  def handle_info(
        {:opening_result, reference, result},
        %{reference: reference, claimed?: false, result: :pending} = state
      ) do
    send(state.owner, {:wotex_opening, reference, :ready})
    {:noreply, %{state | result: result}}
  end

  def handle_info({:opening_transport_down, reference}, %{reference: reference} = state) do
    send(state.owner, {:wotex_opening, reference, :transport_down})
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _ignored_5, _ignored_6}, %{monitor: monitor} = state),
    do: {:stop, :normal, stop_worker(state)}

  def handle_info(
        {:DOWN, monitor, :process, _ignored_7, _ignored_8},
        %{worker_monitor: monitor} = state
      ) do
    send(state.owner, {:wotex_opening, state.reference, :transport_down})
    {:noreply, %{state | worker: nil, worker_monitor: nil}}
  end

  def handle_info(_ignored_9, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{claimed?: state.claimed?, pending?: state.result == :pending}}
      {:message, _ignored_10} -> {:message, :redacted}
      {:reason, _ignored_11} -> {:reason, :redacted}
      {:log, _ignored_12} -> {:log, []}
      entry -> entry
    end)
  end

  defp run(guardian, reference, function) do
    result = function.()
    Process.flag(:trap_exit, true)
    send(guardian, {:opening_result, reference, result})
    proxy(guardian, reference)
  end

  # The callback may have linked a transport to its calling process. Keep that
  # link endpoint alive without retaining the callback or ExecutionContext.
  defp proxy(guardian, reference) do
    :erlang.garbage_collect()

    receive do
      {:EXIT, ^guardian, _ignored_13} ->
        exit(:shutdown)

      {:EXIT, _ignored_14, :normal} ->
        proxy(guardian, reference)

      {:EXIT, _ignored_15, _ignored_16} ->
        send(guardian, {:opening_transport_down, reference})
        proxy(guardian, reference)

      _ignored_17 ->
        proxy(guardian, reference)
    end
  end

  defp stop_worker(%{worker: nil} = state), do: state

  defp stop_worker(state) do
    Process.exit(state.worker, :kill)
    monitor = state.worker_monitor

    receive do
      {:DOWN, ^monitor, :process, _ignored_18, _ignored_19} -> :ok
    after
      100 -> Process.demonitor(monitor, [:flush])
    end

    reference = state.reference

    result =
      receive do
        {:opening_result, ^reference, result} -> result
      after
        0 -> state.result
      end

    %{state | worker: nil, worker_monitor: nil, result: result}
  end

  defp call(opening, operation) do
    GenServer.call(opening.pid, {opening.reference, operation}, 1000)
  catch
    :exit, _ignored_20 -> :none
  end
end
