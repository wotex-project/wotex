defmodule Wotex.BACnet.Test.DiscoveryPeer do
  @moduledoc false

  use GenServer
  alias Wotex.BACnet.Error

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  @doc false
  @spec snapshot(pid()) :: map()
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl GenServer
  def init(options), do: {:ok, %{options: options, listeners: %{}, sent: [], actions: []}}

  @impl GenServer
  def handle_call({:wotex_client, :capabilities}, _, state),
    do:
      {:reply, Keyword.get(state.options, :capabilities, {:wotex_client, 2, [:cov, :discovery]}),
       state}

  def handle_call(:snapshot, _, state) do
    snapshot = %{state | sent: Enum.reverse(state.sent), actions: Enum.reverse(state.actions)}
    {:reply, snapshot, state}
  end

  def handle_call({:wotex_client, :register_discovery, _}, {owner, _}, state) do
    if state.options[:register_error] do
      {:reply, :rejected, state}
    else
      ref = Process.monitor(owner)

      state = %{
        state
        | listeners: Map.put(state.listeners, owner, ref),
          actions: [:register | state.actions]
      }

      if state.options[:register_pending], do: {:noreply, state}, else: {:reply, :ok, state}
    end
  end

  def handle_call({:wotex_client, :unregister_discovery}, {owner, _}, state) do
    cond do
      state.options[:unregister_pending] ->
        {:noreply, state}

      state.options[:unregister_error] ->
        {:reply, :rejected, state}

      true ->
        if ref = state.listeners[owner], do: Process.demonitor(ref, [:flush])

        {:reply, :ok,
         %{
           state
           | listeners: Map.delete(state.listeners, owner),
             actions: [:unregister | state.actions]
         }}
    end
  end

  def handle_call(
        {:wotex_client, :discovery_send, destination, apdu, deadline, caller, listener},
        {worker, _},
        state
      ) do
    sent = %{
      destination: destination,
      apdu: apdu,
      deadline: deadline,
      registered: map_size(state.listeners) == 1 and Map.has_key?(state.listeners, listener),
      caller_alive: Process.alive?(caller),
      worker: worker,
      worker_alive: Process.alive?(worker)
    }

    send(state.options[:owner], {:discovery_peer_send, self(), sent})

    result =
      if state.options[:send_error],
        do: {:error, Error.new(:transport_error)},
        else: Keyword.get(state.options, :send_result, :ok)

    state = %{state | sent: [sent | state.sent], actions: [:send | state.actions]}
    if state.options[:send_pending], do: {:noreply, state}, else: {:reply, result, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    listeners =
      if state.listeners[pid] == ref, do: Map.delete(state.listeners, pid), else: state.listeners

    {:noreply, %{state | listeners: listeners}}
  end
end
