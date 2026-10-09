defmodule Wotex.Zigbee.Event do
  @moduledoc """
  One bounded asynchronous ZNP indication from an untrusted network source.

  AF confirmations identify a local transaction and endpoint; incoming AF
  messages preserve source address, cluster, link quality and the NCP's
  reported security flag. That flag is metadata, not consumer authorization
  or independent cryptographic attestation. Active-endpoint and simple
  descriptor, IEEE identity, node and Bind/Unbind ZDO replies have typed payloads;
  uncatalogued AREQs stay opaque.

  The owner stamps `owner_epoch`, `received_at_ms` and `owner_sequence` when
  observing a frame. Pure `from_frame/1` leaves them nil. The bounded sequence
  orders observations even in the same millisecond. These fields support route
  custody fencing and do not authenticate network origin or radio freshness.
  """

  alias Wotex.Zigbee.{Binding, Frame, PermitJoin, ZDO}

  @enforce_keys [:kind, :subsystem, :id, :payload]
  defstruct [
    :kind,
    :subsystem,
    :id,
    :payload,
    :status,
    :endpoint,
    :transaction,
    :source_address,
    :source_endpoint,
    :cluster,
    :link_quality,
    :security_used,
    :zdo,
    :owner_epoch,
    :received_at_ms,
    :owner_sequence
  ]

  @type t :: %__MODULE__{
          kind:
            :aps_confirm
            | :af_incoming
            | :zdo_ieee_address
            | :zdo_node_descriptor
            | :zdo_active_endpoints
            | :zdo_simple_descriptor
            | :zdo_bind
            | :zdo_unbind
            | :zdo_permit_join
            | :permit_join_indication
            | :zdo_indication
            | :malformed_indication
            | :unknown_indication,
          subsystem: 0..31,
          id: 0..255,
          payload: binary(),
          status: byte() | nil,
          endpoint: byte() | nil,
          transaction: byte() | nil,
          source_address: non_neg_integer() | nil,
          source_endpoint: byte() | nil,
          cluster: non_neg_integer() | nil,
          link_quality: byte() | nil,
          security_used: boolean() | nil,
          owner_epoch: reference() | nil,
          received_at_ms: integer() | nil,
          owner_sequence: pos_integer() | nil,
          zdo:
            ZDO.active_response()
            | ZDO.simple_response()
            | ZDO.ieee_response()
            | ZDO.node_response()
            | Binding.response()
            | PermitJoin.response()
            | PermitJoin.indication()
            | nil
        }

  @doc "Classifies one AREQ, preserving unknown command bytes without decoding them."
  @spec from_frame(Frame.t()) :: t()
  def from_frame(
        %Frame{type: :areq, subsystem: 4, id: 0x80, payload: <<status, endpoint, transaction>>} =
          frame
      ) do
    %__MODULE__{
      kind: :aps_confirm,
      subsystem: 4,
      id: 0x80,
      payload: frame.payload,
      status: status,
      endpoint: endpoint,
      transaction: transaction
    }
  end

  def from_frame(%Frame{
        type: :areq,
        subsystem: 4,
        id: 0x81,
        payload:
          <<_::little-16, cluster::little-16, source::little-16, source_endpoint,
            destination_endpoint, _, quality, security, _::little-32, transaction, length,
            data::binary>>
      })
      when byte_size(data) == length do
    %__MODULE__{
      kind: :af_incoming,
      subsystem: 4,
      id: 0x81,
      payload: data,
      endpoint: destination_endpoint,
      transaction: transaction,
      source_address: source,
      source_endpoint: source_endpoint,
      cluster: cluster,
      link_quality: quality,
      security_used: security != 0
    }
  end

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0x84} = frame),
    do: zdo_event(frame, :zdo_simple_descriptor, ZDO.simple_descriptor(frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0x81} = frame),
    do: zdo_event(frame, :zdo_ieee_address, ZDO.ieee_address(frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0x82} = frame),
    do: zdo_event(frame, :zdo_node_descriptor, ZDO.node_descriptor(frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0x85} = frame),
    do: zdo_event(frame, :zdo_active_endpoints, ZDO.active_endpoints(frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0xA1} = frame),
    do: zdo_event(frame, :zdo_bind, Binding.response(:bind, frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0xA2} = frame),
    do: zdo_event(frame, :zdo_unbind, Binding.response(:unbind, frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0xB6} = frame),
    do: zdo_event(frame, :zdo_permit_join, PermitJoin.response(frame.payload))

  def from_frame(%Frame{type: :areq, subsystem: 5, id: 0xCB} = frame) do
    case PermitJoin.indication(frame.payload) do
      {:ok, indication} ->
        %__MODULE__{
          kind: :permit_join_indication,
          subsystem: 5,
          id: 0xCB,
          payload: frame.payload,
          zdo: indication
        }

      {:error, _} ->
        zdo_event(frame, :permit_join_indication, {:error, nil})
    end
  end

  def from_frame(%Frame{type: :areq, subsystem: 5} = frame),
    do: %__MODULE__{kind: :zdo_indication, subsystem: 5, id: frame.id, payload: frame.payload}

  def from_frame(%Frame{type: :areq, subsystem: 4, id: id} = frame)
      when id in [0x80, 0x81],
      do: %__MODULE__{kind: :malformed_indication, subsystem: 4, id: id, payload: frame.payload}

  def from_frame(%Frame{type: :areq} = frame),
    do: %__MODULE__{
      kind: :unknown_indication,
      subsystem: frame.subsystem,
      id: frame.id,
      payload: frame.payload
    }

  defp zdo_event(frame, kind, {:ok, response}),
    do: %__MODULE__{
      kind: kind,
      subsystem: 5,
      id: frame.id,
      payload: frame.payload,
      status: response.status,
      source_address: Map.get(response, :source_address),
      zdo: response
    }

  defp zdo_event(frame, _, {:error, _}),
    do: %__MODULE__{
      kind: :malformed_indication,
      subsystem: 5,
      id: frame.id,
      payload: frame.payload
    }
end
