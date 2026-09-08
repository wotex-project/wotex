defmodule Wotex.BACnet.Test.BlockingClient do
  @moduledoc false

  use GenServer

  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(receiver), do: GenServer.start_link(__MODULE__, receiver)

  @impl GenServer
  def init(receiver), do: {:ok, receiver}

  @impl GenServer
  def handle_call({:send, destination, apdu, options}, from, receiver) do
    send(receiver, {:pending_apdu, from, destination, apdu, options})
    {:noreply, receiver}
  end
end
