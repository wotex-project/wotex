# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Directory.Repository) do
  defmodule Wotex.Lab.Adapters.Directory.Clock do
    @moduledoc """
    Deterministic `Wotex.Directory.Clock` implementations.

    State `{:fixed, %DateTime{}}` always returns the same instant. State
    `{:agent, pid}` reads the instant held by an `Agent` so a test or host can
    advance simulated time explicitly with `advance/2`. Use
    `Wotex.Directory.Clock.System` for host-provided wall-clock time.

    The agent-backed variant isolates mutable simulated time within the
    consumer-owned process. `advance/2` applies an integer number of seconds,
    and the directory reads the resulting `DateTime` through the clock
    behavior. Neither variant consults system time, schedules expiry, or
    persists its state.

    These clocks support repeatable directory scenarios. A production host
    should select a clock whose lifecycle and time authority match its storage
    and deployment model.
    """

    @behaviour Wotex.Directory.Clock

    @doc "Starts an advancing clock agent at `start`."
    @spec start_link(DateTime.t()) :: Agent.on_start()
    def start_link(%DateTime{} = start), do: Agent.start_link(fn -> start end)

    @doc "Advances an agent-backed clock by `seconds`."
    @spec advance(pid(), integer()) :: :ok
    def advance(agent, seconds) when is_integer(seconds),
      do: Agent.update(agent, &DateTime.add(&1, seconds, :second))

    @impl Wotex.Directory.Clock
    def now({:fixed, %DateTime{} = instant}), do: {:ok, instant}
    def now({:agent, agent}) when is_pid(agent), do: {:ok, Agent.get(agent, & &1)}
    def now(_), do: {:error, :invalid_clock}
  end
end
