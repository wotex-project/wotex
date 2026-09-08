defmodule Wotex.BACnet.StackClient do
  @moduledoc false

  use GenServer
  alias BACnet.Protocol.{APDU, NPCI}
  alias BACnet.Stack.{Client, SegmentsStore}
  alias Wotex.BACnet.{Error, Tags}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @impl GenServer
  def init(opts), do: Client.init(opts)
  @impl GenServer
  def handle_call(message, from, state), do: Client.handle_call(message, from, state)
  @impl GenServer
  def handle_cast(message, state), do: Client.handle_cast(message, state)

  @impl GenServer
  def handle_info(
        {:bacnet_transport, _protocol, source,
         {:apdu, _bvlc, %NPCI{source: nil}, <<48, id, 12, bytes::binary>>}, _portal},
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

  def handle_info(
        {:bacnet_transport, protocol, source,
         {:apdu, bvlc, %NPCI{source: nil} = npci,
          <<3::4, 1::1, _::3, id, _, _, 12, _::binary>> = bytes}, portal},
        state
      ) do
    if Map.has_key?(state.apdu_timers, {source, nil, id}) do
      segment(bytes, source, id, {protocol, bvlc, npci, portal}, state)
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:bacnet_transport, _, source,
         {:apdu, _, %NPCI{source: nil}, <<3::4, 1::1, _::3, id, _::binary>>}, _},
        state
      ),
      do: complete(source, id, {:error, Error.new(:response_mismatch)}, state)

  # This client profile has no segmented incoming request service. Keep unrelated
  # traffic out of the store even when the SDK would assemble it before dispatch.
  def handle_info(
        {:bacnet_transport, _, _, {:apdu, _, _, <<kind::4, 1::1, _::3, _::binary>>}, _},
        state
      )
      when kind in [0, 3] do
    {:noreply, state}
  end

  def handle_info(message, state), do: Client.handle_info(message, state)

  defp segment(bytes, source, id, {protocol, bvlc, npci, portal}, state) do
    case APDU.decode(bytes) do
      {:incomplete, incomplete} ->
        case SegmentsStore.segment(
               state.segments_store,
               incomplete,
               state.transport_mod,
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

      _ ->
        complete(source, id, {:error, Error.new(:invalid_response)}, state)
    end
  end

  defp complete(source, id, result, state) do
    case Map.pop(state.apdu_timers, {source, nil, id}) do
      {nil, _} ->
        {:noreply, state}

      {timer, pending} ->
        Process.cancel_timer(timer.timer)
        SegmentsStore.cancel(state.segments_store, source, id)
        GenServer.reply(timer.call_ref, result)
        {:noreply, %{state | apdu_timers: pending}}
    end
  end
end
