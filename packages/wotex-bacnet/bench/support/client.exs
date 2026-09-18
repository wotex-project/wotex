defmodule Wotex.BACnet.Bench.Client do
  @moduledoc false

  # A pure in-process `Wotex.BACnet.Client`: the handle is the value a read
  # returns, and every write is acknowledged. No process, socket or timer is
  # involved, so a benchmark measures only the package's own admission,
  # mapping, validation and Runtime result construction.

  @behaviour Wotex.BACnet.Client

  @impl Wotex.BACnet.Client
  def connect(opts), do: {:ok, Keyword.fetch!(opts, :reply)}

  @impl Wotex.BACnet.Client
  def request(reply, %{type: :read_property}, _), do: {:ok, reply}
  def request(_, %{type: :write_property}, _), do: {:ok, :written}

  @impl Wotex.BACnet.Client
  def disconnect(_), do: :ok
end
