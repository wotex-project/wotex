defmodule Wotex.BACnet.Test.IntegrationClient do
  @moduledoc false

  @behaviour Wotex.BACnet.Client

  @impl Wotex.BACnet.Client
  def connect(options) do
    {:ok, pid} = Agent.start_link(fn -> options end)
    send(Keyword.fetch!(options, :observer), {:native_opened, pid})
    {:ok, pid}
  end

  @impl Wotex.BACnet.Client
  def request(pid, command, timeout) do
    options = Agent.get(pid, & &1)
    send(Keyword.fetch!(options, :observer), {:native_request, pid, command, timeout})
    Keyword.fetch!(options, :reply)
  end

  @impl Wotex.BACnet.Client
  def disconnect(pid) do
    observer = Agent.get(pid, &Keyword.fetch!(&1, :observer))
    Agent.stop(pid)
    send(observer, {:native_closed, pid})
    :ok
  end
end
