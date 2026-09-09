defmodule Wotex.BACnet.Test.IntegrationClient do
  @moduledoc false

  @behaviour Wotex.BACnet.Client

  @impl Wotex.BACnet.Client
  def connect(options) do
    Process.sleep(Keyword.get(options, :connect_delay, 0))
    {:ok, pid} = Agent.start_link(fn -> options end)
    send(Keyword.fetch!(options, :observer), {:native_opened, pid})
    {:ok, pid}
  end

  @impl Wotex.BACnet.Client
  def request(pid, command, timeout) do
    options = Agent.get(pid, & &1)
    send(Keyword.fetch!(options, :observer), {:native_request, pid, command, timeout})
    Process.sleep(Keyword.get(options, :request_delay, 0))
    Keyword.fetch!(options, :reply)
  end

  @impl Wotex.BACnet.Client
  def disconnect(pid) do
    options = Agent.get(pid, & &1)
    observer = Keyword.fetch!(options, :observer)
    Process.sleep(Keyword.get(options, :close_delay, 0))
    Agent.stop(pid)
    send(observer, {:native_closed, pid})
    Keyword.get(options, :close_reply, :ok)
  end
end
