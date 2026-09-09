defmodule Wotex.BACnet.Test.COVPort do
  @moduledoc false

  @behaviour Wotex.BACnet.Client
  @impl Wotex.BACnet.Client
  def connect(options), do: {:ok, options[:mode]}
  @impl Wotex.BACnet.Client
  def request(_, _, _), do: {:error, :not_supported}
  @impl Wotex.BACnet.Client
  def disconnect(_), do: :ok
  @impl Wotex.BACnet.Client
  def subscribe(:malformed_handle, _, _, _), do: {:ok, %{}}
  def subscribe(:malformed_success, _, _, _), do: :ok
  def subscribe(:exception, _, _, _), do: raise("private-credential-canary")
  @impl Wotex.BACnet.Client
  def unsubscribe(_, _, _), do: {:ok, :invalid}
end
