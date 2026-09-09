defmodule Wotex.BACnet.Test.HealthPort do
  @moduledoc false

  @behaviour Wotex.BACnet.Client
  @impl Wotex.BACnet.Client
  def connect(_), do: {:ok, nil}
  @impl Wotex.BACnet.Client
  def request(_, _, _) do
    Process.sleep(20)
    {:ok, BACnet.Protocol.ApplicationTags.Encoding.create!({:boolean, false})}
  end

  @impl Wotex.BACnet.Client
  def disconnect(_), do: :ok
end
