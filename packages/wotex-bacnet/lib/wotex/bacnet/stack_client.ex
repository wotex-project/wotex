defmodule Wotex.BACnet.StackClient do
  @moduledoc """
  Hosts the pinned BACstack client with bounded Wotex ownership extensions.

  This wrapper delegates ordinary SDK behavior while adding capability
  negotiation, monitored exchanges, invoke-ID retirement, and explicit COV and
  discovery registrations. Confirmed service capacity is bounded. Absolute
  deadline and caller-liveness checks run at final admission before a wrapped
  send, including sends that were queued while the process was paused.

  Direct incoming APDUs use the tag decoder that preserves CharacterString
  selectors; COV reports follow the scoped filter and reassembly path in
  `Wotex.BACnet.StackCOV`. Owner loss retires or removes the associated work.

  The wrapper is created and owned explicitly. Borrowing a raw BACstack Client
  does not install these extensions or authorize mutation of its internals.
  This module depends on the pinned SDK's callback state contract and requires
  compatibility review when that dependency changes.
  """

  use GenServer
  alias BACnet.Protocol.{APDU, NPCI}
  alias BACnet.Protocol.APDU.UnconfirmedServiceRequest
  alias BACnet.Stack.{Client, SegmentsStore}
  alias Wotex.BACnet.{Error, IngressTransport, InvokeIds, StackCOV, Tags}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @impl GenServer
  def init(opts) do
    with {:ok, sdk} <- Client.init(Map.put(opts, :disable_invoke_id_management, true)) do
      ingress =
        if sdk.transport_mod == IngressTransport,
          do: %{pid: sdk.transport_pid, generation: IngressTransport.generation(sdk.transport_pid)}

      {:ok,
       %{sdk: sdk, cov: StackCOV.new(), calls: %{}, invoke_ids: InvokeIds.new(), ingress: ingress}}
    end
  end

  @doc false
  @spec verify(pid(), pos_integer()) :: :ok | {:error, Error.t()}
  def verify(client, timeout) do
    case capabilities(client, timeout) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec capabilities(pid(), pos_integer()) ::
          {:ok, [:cov | :discovery | :bounded_ingress]} | {:error, Error.t()}
  def capabilities(client, timeout) do
    case GenServer.call(client, {:wotex_client, :capabilities}, timeout) do
      {:wotex_client, 1, :cov} ->
        {:ok, [:cov]}

      {:wotex_client, 2, [:cov, :discovery]} ->
        {:ok, [:cov, :discovery]}

      {:wotex_client, 3, [:cov, :discovery, :bounded_ingress]} ->
        {:ok, [:cov, :discovery, :bounded_ingress]}

      _ ->
        {:error, Error.new(:unsupported_stack_client)}
    end
  catch
    :exit, _ -> {:error, Error.new(:unsupported_stack_client)}
  end

  @doc false
  @spec ingress(pid(), pos_integer()) :: {:ok, map()} | {:error, Error.t()}
  def ingress(client, timeout) do
    with {__MODULE__, :init, 1} <- :proc_lib.translate_initial_call(client),
         %{pid: transport, generation: generation} = proof <-
           GenServer.call(client, {:wotex_client, :ingress}, timeout),
         :ok <- IngressTransport.verify(transport, client, generation, timeout) do
      {:ok, proof}
    else
      _ -> {:error, Error.new(:unbounded_receive_policy)}
    end
  catch
    :exit, _ -> {:error, Error.new(:unbounded_receive_policy)}
  end

  @doc false
  @spec exchange(
          pid(),
          term(),
          APDU.ConfirmedServiceRequest.t() | APDU.UnconfirmedServiceRequest.t(),
          keyword(),
          integer()
        ) :: term()
  def exchange(client, destination, apdu, options, deadline) do
    GenServer.call(
      client,
      {:wotex_client, :exchange, destination, apdu, options, deadline},
      :infinity
    )
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc false
  @spec discovery_send(pid(), term(), UnconfirmedServiceRequest.t(), integer(), pid(), pid()) ::
          term()
  def discovery_send(client, destination, apdu, deadline, caller, listener) do
    GenServer.call(
      client,
      {:wotex_client, :discovery_send, destination, apdu, deadline, caller, listener},
      :infinity
    )
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @impl GenServer
  def handle_call({:wotex_client, :capabilities}, _, %{ingress: %{}} = state),
    do: {:reply, {:wotex_client, 3, [:cov, :discovery, :bounded_ingress]}, state}

  def handle_call({:wotex_client, :capabilities}, _, state),
    do: {:reply, {:wotex_client, 2, [:cov, :discovery]}, state}

  def handle_call({:wotex_client, :ingress}, _, state), do: {:reply, state.ingress, state}

  def handle_call(
        {:wotex_client, :discovery_send, destination,
         %APDU.UnconfirmedServiceRequest{service: :who_is} = apdu, deadline, caller, listener},
        from,
        state
      )
      when is_integer(deadline) and is_pid(caller) and is_pid(listener) do
    if Process.alive?(caller) and Process.alive?(listener) and
         listener in state.sdk.notification_receiver,
       do: handle_call({:wotex_client, :exchange, destination, apdu, [], deadline}, from, state),
       else: {:reply, rejected(:connection_closed), state}
  end

  def handle_call({:wotex_client, :discovery_send, _, _, _, _, _}, _, state),
    do: {:reply, rejected(:invalid_request), state}

  def handle_call({:wotex_client, :register_discovery, deadline}, {owner, _} = from, state)
      when is_integer(deadline) do
    cond do
      now() >= deadline -> {:reply, rejected(:deadline_exceeded), state}
      not Process.alive?(owner) -> {:reply, rejected(:connection_closed), state}
      true -> delegate(Client.handle_call({:subscribe, owner}, from, state.sdk), state)
    end
  end

  def handle_call({:wotex_client, :unregister_discovery}, {owner, _} = from, state),
    do: delegate(Client.handle_call({:unsubscribe, owner}, from, state.sdk), state)

  def handle_call({:wotex_client, :register_cov, request, destination, deadline}, from, state)
      when is_integer(deadline) do
    if now() < deadline,
      do: handle_call({:wotex_client, :register_cov, request, destination}, from, state),
      else: {:reply, rejected(:deadline_exceeded), state}
  end

  def handle_call({:wotex_client, :settle, pids}, _, state)
      when is_list(pids) and length(pids) <= 2 do
    next =
      Enum.reduce(pids, state, fn pid, current ->
        if is_pid(pid) and not Process.alive?(pid), do: settle(current, pid), else: current
      end)

    {:reply, :ok, next}
  end

  def handle_call({:wotex_client, :register_cov, request, destination}, {owner, _}, state) do
    {reply, cov} = StackCOV.register(state.cov, owner, request, destination, state.sdk)
    {:reply, reply, %{state | cov: cov}}
  end

  def handle_call({:wotex_client, :unregister_cov}, {owner, _}, state),
    do: {:reply, :ok, %{state | cov: StackCOV.remove(state.cov, owner, state.sdk)}}

  def handle_call({:reply, ref, data, opts} = message, from, state) do
    if Map.has_key?(state.cov.replies, ref) do
      {reply, cov} = StackCOV.reply(state.cov, ref, data, elem(from, 0), opts, state.sdk)
      {:reply, reply, %{state | cov: cov}}
    else
      delegate(Client.handle_call(message, from, state.sdk), state)
    end
  end

  def handle_call({:wotex_client, :exchange, destination, apdu, opts, deadline}, from, state)
      when is_integer(deadline) do
    cond do
      now() >= deadline -> {:reply, rejected(:deadline_exceeded), state}
      not Process.alive?(elem(from, 0)) -> {:reply, rejected(:connection_closed), state}
      true -> handle_call({:send, destination, apdu, opts}, from, state)
    end
  end

  def handle_call({:send, destination, %APDU.ConfirmedServiceRequest{} = apdu, opts}, from, state) do
    cond do
      not Process.alive?(elem(from, 0)) ->
        {:reply, rejected(:connection_closed), state}

      map_size(state.sdk.apdu_timers) >= 64 ->
        {:reply, rejected(:busy), state}

      true ->
        send_confirmed(destination, apdu, opts, from, state)
    end
  end

  def handle_call(message, from, state),
    do: delegate(Client.handle_call(message, from, state.sdk), state)

  @impl GenServer
  def handle_cast(message, state), do: delegate(Client.handle_cast(message, state.sdk), state)

  @impl GenServer
  def handle_info(
        {:wotex_bacnet_datagram, generation, receipt,
         {:bacnet_transport, {:bacnet_ipv4, IngressTransport}, _, frame, portal} = message},
        %{ingress: %{pid: transport, generation: generation}, sdk: %{transport_portal: portal}} =
          state
      )
      when is_reference(receipt) do
    result =
      case frame do
        {:apdu, _, _, bytes} when is_binary(bytes) and byte_size(bytes) <= 1476 ->
          handle_info(message, state)

        _ ->
          {:noreply, state}
      end

    send(transport, {:wotex_bacnet_consumed, generation, receipt})
    result
  end

  def handle_info({:wotex_bacnet_datagram, _, _, _}, state), do: {:noreply, state}

  def handle_info({:wotex_cov_expire, kind, ref}, state),
    do: {:noreply, %{state | cov: StackCOV.expire(state.cov, kind, ref, state.sdk)}}

  def handle_info({:apdu_timer, {_, _, id} = key} = message, state) do
    result = Client.handle_info(message, state.sdk)

    ids =
      if Map.has_key?(state.sdk.apdu_timers, key),
        do: InvokeIds.retire(state.invoke_ids, id, now()),
        else: state.invoke_ids

    delegate(result, %{state | invoke_ids: ids})
  end

  def handle_info({:DOWN, reference, :process, pid, _} = message, state) do
    state = %{state | cov: StackCOV.down(state.cov, reference, pid, state.sdk)}
    state = cancel_calls(state, reference)
    delegate(Client.handle_info(message, state.sdk), state)
  end

  def handle_info(
        {:bacnet_transport, protocol, source, {:apdu, bvlc, %NPCI{source: nil} = npci, bytes},
         portal},
        state
      )
      when byte_size(bytes) <= 1476 do
    if StackCOV.service?(bytes) do
      cov = StackCOV.receive(state.cov, source, bytes, {protocol, bvlc, npci, portal}, state.sdk)
      {:noreply, %{state | cov: cov}}
    else
      receive_apdu({:bacnet_transport, protocol, source, {:apdu, bvlc, npci, bytes}, portal}, state)
    end
  end

  def handle_info({:bacnet_transport, _, _, {:apdu, _, _, bytes}, _} = message, state) do
    if StackCOV.service?(bytes), do: {:noreply, state}, else: receive_apdu(message, state)
  end

  def handle_info(message, state), do: receive_apdu(message, state)

  defp send_confirmed(destination, apdu, opts, from, state) do
    case InvokeIds.allocate(state.invoke_ids, state.sdk.apdu_timers, now()) do
      {:ok, id, ids} ->
        delegate(
          Client.handle_call(
            {:send, destination, %{apdu | invoke_id: id}, opts},
            from,
            state.sdk
          ),
          %{state | invoke_ids: ids}
        )

      :busy ->
        {:reply, rejected(:busy), state}
    end
  end

  defp receive_apdu(
         {:bacnet_transport, _, source,
          {:apdu, _, %NPCI{source: nil}, <<48, id, 12, bytes::binary>>}, _},
         state
       ) do
    result =
      case Tags.decode(bytes) do
        {:ok, tags} ->
          {:ok,
           %APDU.ComplexACK{
             invoke_id: id,
             sequence_number: nil,
             proposed_window_size: nil,
             service: :read_property,
             payload: tags
           }}

        error ->
          error
      end

    complete(source, id, result, state)
  end

  defp receive_apdu(
         {:bacnet_transport, protocol, source,
          {:apdu, bvlc, %NPCI{source: nil} = npci,
           <<3::4, 1::1, _::3, id, _, _, 12, _::binary>> = bytes}, portal},
         state
       ) do
    if Map.has_key?(state.sdk.apdu_timers, {source, nil, id}) do
      segment(bytes, source, id, {protocol, bvlc, npci, portal}, state)
    else
      {:noreply, state}
    end
  end

  defp receive_apdu(
         {:bacnet_transport, _, source,
          {:apdu, _, %NPCI{source: nil}, <<3::4, 1::1, _::3, id, _::binary>>}, _},
         state
       ),
       do: complete(source, id, {:error, Error.new(:response_mismatch)}, state)

  # Only matched COV requests enter request assembly. Keep other segmented
  # traffic out of the store before the SDK dispatches it.
  defp receive_apdu(
         {:bacnet_transport, _, _, {:apdu, _, _, <<kind::4, 1::1, _::3, _::binary>>}, _},
         state
       )
       when kind in [0, 3] do
    {:noreply, state}
  end

  defp receive_apdu(message, state), do: delegate(Client.handle_info(message, state.sdk), state)

  defp segment(bytes, source, id, {protocol, bvlc, npci, portal}, state) do
    {:incomplete, incomplete} = APDU.decode(bytes)

    case SegmentsStore.segment(
           state.sdk.segments_store,
           incomplete,
           state.sdk.transport_mod,
           portal,
           source
         ) do
      {:ok, complete} ->
        handle_info(
          {:bacnet_transport, protocol, source, {:apdu, bvlc, npci, complete}, portal},
          state
        )

      :incomplete ->
        {:noreply, state}

      {:error, _, _} ->
        complete(source, id, {:error, Error.new(:segmented_response_error)}, state)
    end
  end

  defp complete(source, id, result, state) do
    case Map.pop(state.sdk.apdu_timers, {source, nil, id}) do
      {nil, _} ->
        {:noreply, state}

      {timer, pending} ->
        Process.cancel_timer(timer.timer)
        SegmentsStore.cancel(state.sdk.segments_store, source, id)
        GenServer.reply(timer.call_ref, result)
        {:noreply, sync_calls(%{state | sdk: %{state.sdk | apdu_timers: pending}})}
    end
  end

  defp delegate({:reply, reply, sdk}, state), do: {:reply, reply, sync_calls(%{state | sdk: sdk})}
  defp delegate({:noreply, sdk}, state), do: {:noreply, sync_calls(%{state | sdk: sdk})}

  defp sync_calls(state) do
    current = Map.keys(state.sdk.apdu_timers)

    kept =
      Map.new(state.calls, fn {key, monitor} ->
        if key not in current, do: Process.demonitor(monitor, [:flush])
        {key, monitor}
      end)
      |> Map.take(current)

    calls =
      Map.new(state.sdk.apdu_timers, fn {key, timer} ->
        {key, Map.get_lazy(kept, key, fn -> Process.monitor(elem(timer.call_ref, 0)) end)}
      end)

    %{state | calls: calls}
  end

  defp settle(state, pid) do
    state = %{state | cov: StackCOV.remove(state.cov, pid, state.sdk)}

    Enum.reduce(state.sdk.apdu_timers, state, fn {key, timer}, current ->
      if elem(timer.call_ref, 0) == pid,
        do: cancel_calls(current, current.calls[key]),
        else: current
    end)
  end

  defp cancel_calls(state, reference) do
    case Enum.find(state.calls, fn {_, monitor} -> monitor == reference end) do
      nil ->
        state

      {{source, _, id} = key, _} ->
        {timer, pending} = Map.pop(state.sdk.apdu_timers, key)
        if timer, do: Process.cancel_timer(timer.timer)
        SegmentsStore.cancel(state.sdk.segments_store, source, id)

        sync_calls(%{
          state
          | sdk: %{state.sdk | apdu_timers: pending},
            invoke_ids: InvokeIds.retire(state.invoke_ids, id, now())
        })
    end
  end

  defp rejected(code), do: {:error, Error.new(code, nil, %{dispatch: :not_started})}

  defp now, do: System.monotonic_time(:millisecond)
end
