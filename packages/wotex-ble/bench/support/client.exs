defmodule Wotex.BLE.Bench.Client do
  @moduledoc false

  # A pure in-process `Wotex.BLE.Client`: the handle is the attribute value a
  # read returns, and every write is acknowledged. No process, Port or D-Bus
  # call is involved, so a benchmark measures only the package's own
  # admission, mapping, value conversion and Runtime result construction.

  @behaviour Wotex.BLE.Client

  @impl Wotex.BLE.Client
  def connect(opts), do: {:ok, Keyword.fetch!(opts, :reply)}

  @impl Wotex.BLE.Client
  def request(reply, %{type: :read}, _), do: {:ok, reply}
  def request(_, %{type: :write}, _), do: {:ok, :written}

  @impl Wotex.BLE.Client
  def disconnect(_), do: :ok
end
