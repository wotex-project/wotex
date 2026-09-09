defmodule Wotex.BACnet.Test.COVFaultClient do
  @moduledoc false

  use GenServer

  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(receiver), do: GenServer.start_link(__MODULE__, receiver)
  @impl GenServer
  def init(receiver), do: {:ok, receiver}
  @impl GenServer
  def handle_call(request, from, receiver) do
    send(receiver, {:fault_call, self(), request, from})
    {:noreply, receiver}
  end
end
