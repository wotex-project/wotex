defmodule Wotex.Zigbee.Freshness.Observation do
  @moduledoc false

  alias Wotex.Zigbee.{Error, Event, ZCL}
  alias Wotex.Zigbee.Freshness.Policy
  alias Wotex.Zigbee.ZCL.{PollControl, Value}

  @max_time 0x7FFFFFFFFFFFFFFF
  @max_sequence 0xFFFFFFFFFFFFFFFF
  @event_fields Map.keys(%Event{kind: nil, subsystem: nil, id: nil, payload: nil})

  @doc false
  @spec valid_event?(term()) :: boolean()
  def valid_event?(%Event{} = event) do
    complete?(event, @event_fields) and source_fields?(event) and
      owner_fields?(event) and metadata_fields?(event)
  end

  def valid_event?(_), do: false

  defp source_fields?(event) do
    event.kind == :af_incoming and
      event.subsystem == 4 and event.id == 0x81 and is_binary(event.payload) and
      byte_size(event.payload) <= 128 and endpoint?(event.source_endpoint) and
      endpoint?(event.endpoint) and in_range?(event.source_address, 0, 0xFFF7) and
      in_range?(event.cluster, 0, 0xFFFF)
  end

  defp owner_fields?(event) do
    is_reference(event.owner_epoch) and
      in_range?(event.owner_sequence, 1, @max_sequence) and
      in_range?(event.received_at_ms, -@max_time, @max_time)
  end

  defp metadata_fields?(event) do
    event.status == nil and event.zdo == nil and optional_byte?(event.transaction) and
      optional_byte?(event.link_quality) and
      (event.security_used == nil or is_boolean(event.security_used))
  end

  @doc false
  @spec decode(Event.t()) :: {:ok, map()} | {:error, Error.t()}
  def decode(event) do
    case ZCL.decode_attributes(event.payload) do
      {:ok, %{command: :report} = report} -> {:ok, report}
      {:ok, _} -> failure(:unsupported_profile)
      _ -> checkin(event)
    end
  end

  @doc false
  @spec build(Policy.t(), binary(), Event.t(), map()) :: map() | nil
  def build(policy, peer, event, message) do
    if source_matches?(policy, peer, event) and header_matches?(policy, message) do
      receipt(policy, peer, event, message)
    end
  end

  @doc false
  @spec valid_receipt?(term(), Policy.t()) :: boolean()
  def valid_receipt?(receipt, policy) when is_map(receipt) do
    complete?(receipt, [:peer_ieee, :event, :disposition, :records]) and
      valid_event?(receipt.event) and
      case decode(receipt.event) do
        {:ok, message} ->
          receipt == build(policy, receipt.peer_ieee, receipt.event, message)

        _ ->
          false
      end
  end

  def valid_receipt?(_, _), do: false

  @doc false
  @spec eligible?(map()) :: boolean()
  def eligible?(receipt), do: receipt.disposition in [:value, :null, :checkin]

  defp checkin(%{cluster: 0x0020} = event) do
    case PollControl.decode(event.payload) do
      {:ok, %{command: :checkin} = message} -> {:ok, message}
      _ -> failure(:invalid_frame)
    end
  end

  defp checkin(_), do: failure(:invalid_frame)

  defp source_matches?(policy, peer, event),
    do:
      policy.peer_ieee == peer and policy.remote_endpoint == event.source_endpoint and
        policy.local_endpoint == event.endpoint and policy.cluster == event.cluster

  defp header_matches?(%{kind: :checkin}, %{command: :checkin}), do: true

  defp header_matches?(%{kind: :report} = policy, %{command: :report} = message),
    do: policy.direction == message.direction and policy.manufacturer == message.manufacturer

  defp header_matches?(_, _), do: false

  defp receipt(%{kind: :checkin}, peer, event, _),
    do: %{peer_ieee: peer, event: event, disposition: :checkin, records: []}

  defp receipt(policy, peer, event, message) do
    records = Enum.filter(message.attributes, &(&1.id == policy.attribute_id))

    if records != [] do
      disposition = disposition(records, message.attributes, policy.type)
      records = interpret(records, disposition, policy.full_range)
      disposition = if disposition == :null and policy.full_range, do: :value, else: disposition

      %{
        peer_ieee: peer,
        event: event,
        disposition: disposition,
        records: records
      }
    end
  end

  defp disposition([_, _ | _], _, _), do: :ambiguous
  defp disposition([%{value: {:unsupported, _}}], _, _), do: :unsupported

  defp disposition([record], all, expected_type) do
    cond do
      record.type != expected_type -> :wrong_type
      Enum.any?(all, &match?({:unsupported, _}, &1.value)) -> :opaque_tail
      record.value == :null -> :null
      true -> :value
    end
  end

  defp interpret([record], disposition, true) when disposition in [:value, :null] do
    {:ok, value, _, <<>>} = Value.decode(record.type, record.raw, true)
    [%{record | value: value}]
  end

  defp interpret(records, _, _), do: records

  defp complete?(map, keys),
    do: map_size(map) == length(keys) and Enum.all?(keys, &Map.has_key?(map, &1))

  defp endpoint?(value), do: in_range?(value, 1, 240)
  defp optional_byte?(nil), do: true
  defp optional_byte?(value), do: in_range?(value, 0, 255)
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :freshness}}
end
