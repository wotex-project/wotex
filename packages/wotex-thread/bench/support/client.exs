defmodule Wotex.Thread.Bench.Client do
  @moduledoc false

  # An in-process `Wotex.Thread.Client` that answers the four read-only
  # management requests from prepared values, so the benchmarks measure the
  # package's mapping and validation around a client call and not a daemon
  # socket. It never starts a process or performs I/O.

  @behaviour Wotex.Thread.Client

  @values %{state: "leader", version: "OPENTHREAD/1.4.0; POSIX", network_name: "wotex-bench"}

  @impl Wotex.Thread.Client
  def connect(_), do: {:ok, :bench}

  @impl Wotex.Thread.Client
  def request(_, %{type: :rloc16}, _), do: {:ok, 0x4400}
  def request(_, %{type: type}, _), do: {:ok, Map.fetch!(@values, type)}

  @impl Wotex.Thread.Client
  def disconnect(_), do: :ok
end
