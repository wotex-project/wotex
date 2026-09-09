defmodule Wotex.BLE.RuntimeClient do
  @moduledoc false

  @behaviour Wotex.BLE.Client

  @impl Wotex.BLE.Client
  def connect(options) do
    receiver = Keyword.fetch!(options, :test_pid)
    send(receiver, {:runtime_client, :open, Keyword.fetch!(options, :timeout)})
    Process.sleep(Keyword.get(options, :connect_delay, 0))
    {:ok, %{receiver: receiver, reply: Keyword.fetch!(options, :peer_reply)}}
  end

  @impl Wotex.BLE.Client
  def request(handle, message, timeout) do
    send(handle.receiver, {:runtime_client, :request, message, timeout})
    {:ok, handle.reply}
  end

  @impl Wotex.BLE.Client
  def disconnect(handle) do
    send(handle.receiver, {:runtime_client, :close})
    :ok
  end
end
