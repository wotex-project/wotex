defmodule Wotex.CoAP.TestExecution do
  @moduledoc false

  @behaviour Wotex.CoAP.Execution
  use GenServer

  @spec start(map()) :: {:ok, pid()}
  def start(input), do: GenServer.start_link(__MODULE__, input)

  @impl GenServer
  def init(input), do: {:ok, Map.merge(%{now: 0, timers: %{}, owners: %{}, order: 0}, input)}

  @spec snapshot(pid()) :: map()
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl Wotex.CoAP.Execution
  def now_ms(pid), do: GenServer.call(pid, :now)

  @impl Wotex.CoAP.Execution
  def initial_mid(pid), do: GenServer.call(pid, :initial_mid)

  @impl Wotex.CoAP.Execution
  def message_id(pid, _), do: GenServer.call(pid, {:take, :mids})

  @impl Wotex.CoAP.Execution
  def token(pid), do: GenServer.call(pid, {:take, :tokens})

  @impl Wotex.CoAP.Execution
  def schedule(pid, owner, event, delay), do: GenServer.call(pid, {:schedule, owner, event, delay})

  @impl Wotex.CoAP.Execution
  def cancel(pid, reference), do: GenServer.call(pid, {:cancel, reference})

  @spec advance(pid(), non_neg_integer()) :: non_neg_integer()
  def advance(pid, time), do: GenServer.call(pid, {:advance, time})

  @spec elapse(pid(), non_neg_integer()) :: :ok
  def elapse(pid, time), do: GenServer.call(pid, {:elapse, time})

  @impl GenServer
  def handle_call(:snapshot, _, state), do: {:reply, state, state}
  def handle_call(:now, _, state), do: {:reply, state.now, state}
  def handle_call(:initial_mid, _, state), do: {:reply, List.first(state.mids), state}

  def handle_call({:elapse, time}, _, state) when time >= state.now,
    do: {:reply, :ok, %{state | now: time}}

  def handle_call({:take, key}, _, state) do
    case Map.fetch!(state, key) do
      [value | remaining] -> {:reply, value, Map.put(state, key, remaining)}
      [] -> {:reply, :exhausted, state}
    end
  end

  def handle_call({:schedule, owner, event, delay}, _, state) do
    reference = make_ref()
    owners = Map.put_new_lazy(state.owners, owner, fn -> Process.monitor(owner) end)
    timer = %{owner: owner, event: event, at: state.now + delay, order: state.order}

    {:reply, reference,
     %{
       state
       | owners: owners,
         order: state.order + 1,
         timers: Map.put(state.timers, reference, timer)
     }}
  end

  def handle_call({:cancel, reference}, _, state) do
    case Map.pop(state.timers, reference) do
      {nil, _} ->
        {:reply, false, state}

      {timer, remaining} ->
        {:reply, max(0, timer.at - state.now), cleanup_owners(%{state | timers: remaining})}
    end
  end

  def handle_call({:advance, time}, _, state) do
    {ready, pending} = Enum.split_with(state.timers, fn {_, timer} -> timer.at <= time end)

    ready =
      ready
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(&{&1.at, &1.order})

    Enum.each(ready, &send(&1.owner, &1.event))
    {:reply, length(ready), cleanup_owners(%{state | now: time, timers: Map.new(pending)})}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, owner, _}, state) do
    if state.owners[owner] == monitor,
      do:
        {:noreply,
         %{
           state
           | owners: Map.delete(state.owners, owner),
             timers: Map.reject(state.timers, fn {_, timer} -> timer.owner == owner end)
         }},
      else: {:noreply, state}
  end

  defp cleanup_owners(state) do
    owners =
      Map.reject(state.owners, fn {owner, monitor} ->
        if Enum.any?(state.timers, fn {_, timer} -> timer.owner == owner end),
          do: false,
          else:
            (
              Process.demonitor(monitor, [:flush])
              true
            )
      end)

    %{state | owners: owners}
  end
end
