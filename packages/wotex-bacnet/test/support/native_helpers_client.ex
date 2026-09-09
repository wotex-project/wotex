defmodule Wotex.BACnet.Test.NativeHelpersClient do
  @moduledoc false

  @behaviour Wotex.BACnet.Client

  @impl Wotex.BACnet.Client
  def connect(options), do: {:ok, options}

  @impl Wotex.BACnet.Client
  def request(options, request, _), do: answer(options, request)

  @impl Wotex.BACnet.Client
  def read_properties(options, requests, _), do: answer(options, requests)

  @impl Wotex.BACnet.Client
  def disconnect(_), do: :ok

  defp answer(options, request) do
    send(Keyword.fetch!(options, :owner), {:native_helper_call, request})
    Process.sleep(Keyword.get(options, :delay_ms, 0))
    Keyword.fetch!(options, :result)
  end
end
