defmodule Wotex.BACnet.Test.DiscoveryClock do
  @moduledoc false

  use Agent

  @doc false
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: Agent.start_link(fn -> %{now: 0, timers: %{}} end)
  @doc false
  @spec now(pid()) :: integer()
  def now(clock), do: Agent.get(clock, & &1.now)
  @doc false
  @spec timers(pid()) :: non_neg_integer()
  def timers(clock), do: Agent.get(clock, &map_size(&1.timers))

  @doc false
  @spec schedule(pid(), pid(), term(), non_neg_integer()) :: reference()
  def schedule(clock, pid, message, delay) do
    ref = make_ref()

    Agent.update(clock, fn state ->
      %{state | timers: Map.put(state.timers, ref, {state.now + delay, pid, message})}
    end)

    ref
  end

  @doc false
  @spec cancel(pid(), reference()) :: :ok
  def cancel(clock, ref), do: Agent.update(clock, &%{&1 | timers: Map.delete(&1.timers, ref)})

  @doc false
  @spec advance(pid(), integer()) :: :ok
  def advance(clock, now) do
    due =
      Agent.get_and_update(clock, fn state ->
        {due, pending} =
          Enum.split_with(state.timers, fn {_, {deadline, _, _}} -> deadline <= now end)

        {due, %{state | now: now, timers: Map.new(pending)}}
      end)

    Enum.each(due, fn {_, {_, pid, message}} -> send(pid, message) end)
  end
end
