defmodule Wotex.BACnet.StackCOV do
  @moduledoc """
  Tracks COV filters, confirmations, and assemblies inside the SDK wrapper.

  Registration binds a live listener to an explicit destination and validated
  request. Up to 64 filters and 64 concurrent assemblies are retained, with
  bounded pending confirmation contexts. Incoming reports must match source,
  subscriber identifier, initiating device, monitored object, and confirmation
  mode before they reach a listener.

  Confirmed replies are bound to their listener and invoke ID. Reassembly keeps
  COV source identity separate, rejects inconsistent headers, and applies the
  pinned SDK's 32-segment ceiling with a one-second assembly lifetime. Listener
  death removes its filters, reply contexts, and unshared assemblies. All state
  belongs to `Wotex.BACnet.StackClient`, never to a borrowed raw SDK client's
  private state.
  """

  alias BACnet.Protocol.APDU
  alias BACnet.Stack.SegmentsStore
  alias Wotex.BACnet.{COV, COVRequest, COVSegmentTransport, Error, Tags}

  @doc false
  @spec new() :: %{filters: %{}, replies: %{}, assemblies: %{}, next_identifier: 1}
  def new, do: %{filters: %{}, replies: %{}, assemblies: %{}, next_identifier: 1}

  @doc false
  @spec register(map(), pid(), term(), term(), map()) :: {term(), map()}
  def register(state, owner, request, destination, sdk) do
    cond do
      not is_pid(owner) or not Process.alive?(owner) or
        COVRequest.validate(request) != :ok or not valid_destination?(sdk, destination) ->
        {{:error, Error.new(:invalid_subscription)}, state}

      Map.has_key?(state.filters, owner) ->
        {{:error, Error.new(:invalid_subscription)}, state}

      map_size(state.filters) >= 64 ->
        {{:error, Error.new(:busy)}, state}

      state.next_identifier > 4_294_967_295 ->
        {{:error, Error.new(:identifier_exhausted)}, state}

      true ->
        filter = %{
          request: request,
          destination: destination,
          identifier: state.next_identifier,
          monitor: Process.monitor(owner)
        }

        {{:ok, filter.identifier},
         %{
           state
           | filters: Map.put(state.filters, owner, filter),
             next_identifier: filter.identifier + 1
         }}
    end
  end

  @doc false
  @spec down(map(), reference(), pid(), map()) :: map()
  def down(state, reference, owner, sdk) do
    case state.filters[owner] do
      %{monitor: ^reference} -> remove(state, owner, sdk)
      _ -> state
    end
  end

  @doc false
  @spec remove(map(), pid(), map()) :: map()
  def remove(state, owner, sdk) do
    case Map.pop(state.filters, owner) do
      {nil, _} ->
        state

      {filter, filters} ->
        Process.demonitor(filter.monitor, [:flush])
        state = %{state | filters: filters}

        state =
          Enum.reduce(state.replies, state, fn {ref, reply}, acc ->
            if reply.owner == owner, do: expire(acc, :reply, ref, sdk), else: acc
          end)

        if Enum.any?(filters, fn {_, f} -> f.destination == filter.destination end) do
          state
        else
          remove_assemblies(state, filter.destination, sdk)
        end
    end
  end

  @doc false
  @spec service?(binary()) :: boolean()
  def service?(<<0::4, 0::1, _::3, _, _, 1, _::binary>>), do: true
  def service?(<<0::4, 1::1, _::3, _, _, _, _, 1, _::binary>>), do: true
  def service?(<<16, 2, _::binary>>), do: true
  def service?(_), do: false

  @doc false
  @spec receive(map(), term(), binary(), tuple(), map()) :: map()
  def receive(state, source, <<0::4, 1::1, _::3, _, id, _::binary>> = bytes, route, sdk) do
    key = {source, id}

    cond do
      not Enum.any?(state.filters, fn {_, f} -> f.destination == source end) -> state
      not Map.has_key?(state.assemblies, key) and map_size(state.assemblies) >= 64 -> state
      true -> assemble(state, key, bytes, route, sdk)
    end
  end

  def receive(state, source, bytes, route, sdk) do
    with {:ok, apdu} <- decode(bytes),
         {:ok, report} <- COV.notification(apdu),
         {owner, _} <-
           Enum.find(state.filters, fn {_, filter} ->
             filter.destination == source and
               COV.matches?(report, filter.request, filter.identifier)
           end) do
      deliver(state, owner, source, report, apdu, route, sdk)
    else
      _ -> state
    end
  end

  @doc false
  @spec reply(map(), reference(), term(), pid(), keyword(), map()) :: {term(), map()}
  def reply(state, ref, %APDU.SimpleACK{} = ack, owner, [], sdk) do
    context = state.replies[ref]

    cond do
      not Process.alive?(context.owner) or now() >= context.deadline ->
        {{:error, :app_timeout}, expire(state, :reply, ref, sdk)}

      context.owner == owner and ack.invoke_id == context.invoke_id and
          ack.service == :confirmed_cov_notification ->
        result = sdk.transport_mod.send(context.portal, context.source, ack, [])
        {result, expire(state, :reply, ref, sdk)}

      true ->
        {{:error, Error.new(:invalid_cov_acknowledgment)}, state}
    end
  end

  def reply(state, _, _, _, _, _),
    do: {{:error, Error.new(:invalid_cov_acknowledgment)}, state}

  @doc false
  @spec expire(map(), :reply | :assembly, term(), map()) :: map()
  def expire(state, :reply, ref, _) do
    case Map.pop(state.replies, ref) do
      {nil, _} ->
        state

      {reply, replies} ->
        Process.cancel_timer(reply.timer)
        %{state | replies: replies}
    end
  end

  def expire(state, :assembly, {source, id} = key, sdk) do
    case Map.pop(state.assemblies, key) do
      {nil, _} ->
        state

      {entry, assemblies} ->
        Process.cancel_timer(entry.timer)
        SegmentsStore.cancel(sdk.segments_store, scoped_source(sdk, source), id)
        %{state | assemblies: assemblies}
    end
  end

  defp remove_assemblies(state, destination, sdk) do
    Enum.reduce(state.assemblies, state, fn {{source, _} = key, _}, acc ->
      if source == destination, do: expire(acc, :assembly, key, sdk), else: acc
    end)
  end

  defp assemble(state, {source, id} = key, bytes, route, sdk) do
    with {:incomplete, incomplete} <- APDU.decode(bytes),
         true <- incomplete.sequence_number < 32,
         header <- normalized_header(bytes),
         true <- matching_header?(state.assemblies[key], header) do
      incomplete = %{incomplete | header: header}

      result =
        SegmentsStore.segment(
          sdk.segments_store,
          incomplete,
          COVSegmentTransport,
          elem(route, 3),
          scoped_source(sdk, source)
        )

      case result do
        {:ok, bytes} ->
          receive(expire(state, :assembly, key, sdk), source, bytes, route, sdk)

        :incomplete ->
          assemblies =
            Map.put_new_lazy(state.assemblies, key, fn ->
              %{
                timer: Process.send_after(self(), {:wotex_cov_expire, :assembly, key}, 1000),
                header: header
              }
            end)

          %{state | assemblies: assemblies}

        {:error, _, _} ->
          expire(state, :assembly, key, sdk)
      end
    else
      _ ->
        SegmentsStore.cancel(sdk.segments_store, scoped_source(sdk, source), id)
        expire(state, :assembly, key, sdk)
    end
  end

  # BACstack 0.0.1 omits the maxima octet in a reconstructed request header.
  # Keep it and the accepted-response flag explicit across every segment.
  defp normalized_header(<<0::4, 1::1, _::1, accepted::1, _::1, maxima, id, _::binary>>),
    do: <<0::4, 0::2, accepted::1, 0::1, maxima, id, 1>>

  defp matching_header?(nil, _), do: true
  defp matching_header?(%{header: header}, header), do: true
  defp matching_header?(_, _), do: false

  defp decode(<<flags, maxima, id, 1, bytes::binary>>) when flags in [0, 2] do
    with {:ok, apdu} <- APDU.decode(<<flags, maxima, id, 1>>),
         {:ok, tags} <- Tags.decode(bytes),
         do: {:ok, %{apdu | parameters: tags}}
  end

  defp decode(<<16, 2, bytes::binary>>) do
    with {:ok, tags} <- Tags.decode(bytes),
         do:
           {:ok,
            %APDU.UnconfirmedServiceRequest{
              service: :unconfirmed_cov_notification,
              parameters: tags
            }}
  end

  defp decode(_), do: :error

  defp deliver(state, owner, source, report, apdu, {_, bvlc, npci, portal}, sdk) do
    filter = state.filters[owner]

    if available?(owner, filter.request.max_queue_length) and map_size(state.replies) < 1024 do
      ref = make_ref()
      send(owner, {:bacnet_client, ref, apdu, {source, bvlc, npci}, self()})

      if report.confirmed do
        reply = %{
          owner: owner,
          source: source,
          invoke_id: report.invoke_id,
          portal: portal,
          deadline: now() + 1000,
          timer: Process.send_after(self(), {:wotex_cov_expire, :reply, ref}, 1000)
        }

        %{state | replies: Map.put(state.replies, ref, reply)}
      else
        state
      end
    else
      send(owner, {:wotex_cov_error, :slow_consumer})
      remove(state, owner, sdk)
    end
  end

  defp available?(owner, maximum) do
    case Process.info(owner, :message_queue_len) do
      {:message_queue_len, length} -> length < maximum
      nil -> false
    end
  end

  defp valid_destination?(sdk, destination) do
    sdk.transport_mod.is_valid_destination(destination)
  rescue
    _ -> false
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp scoped_source(sdk, source), do: {:cov, sdk.transport_mod, source}
end
