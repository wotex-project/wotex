defmodule Wotex.BACnet.InvokeIds do
  @moduledoc """
  Allocates and temporarily retires confirmed-service invoke identifiers.

  The pinned SDK wrapper uses this pure state to choose among the 256 byte-sized
  identifiers while excluding pending calls and retired identifiers. Exhaustion
  returns `:busy` instead of reusing a live identifier. Retired identifiers
  remain unavailable for 60,000 milliseconds of caller-supplied monotonic time.

  State belongs to one `Wotex.BACnet.StackClient` process. This local quarantine
  reduces late-response collisions; it does not replace source, service, or
  session correlation and does not persist across a restarted client.
  """

  @doc false
  @spec new() :: %{next: 0, retired: %{}}
  def new, do: %{next: 0, retired: %{}}

  @doc false
  @spec allocate(map(), map(), integer()) :: {:ok, byte(), map()} | :busy
  def allocate(state, pending, now) do
    retired = Map.reject(state.retired, fn {_, expires} -> expires <= now end)
    occupied = MapSet.new(pending, fn {{_, _, id}, _} -> id end)

    id =
      Enum.find(0..255, fn offset ->
        id = rem(state.next + offset, 256)
        not Map.has_key?(retired, id) and not MapSet.member?(occupied, id)
      end)

    if id do
      id = rem(state.next + id, 256)
      {:ok, id, %{state | next: rem(id + 1, 256), retired: retired}}
    else
      :busy
    end
  end

  @doc false
  @spec retire(map(), byte(), integer()) :: map()
  def retire(state, id, now), do: %{state | retired: Map.put(state.retired, id, now + 60_000)}
end
