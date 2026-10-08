defmodule Wotex.Zigbee.ZDO do
  @moduledoc """
  Finite TI ZNP ZDO descriptor response decoding for device interviews.

  The identity and descriptor decoders retain the asynchronous responses to
  corresponding host requests. Source and described network
  addresses are retained separately; both are transient routes rather than
  durable IEEE identity. The IEEE callback has no separate source field and
  preserves raw EUI-64 bytes without authenticating them. Failed ZDO status has no invented endpoint or
  descriptor. Counts and descriptor lengths must match the complete payload.

  This codec does not perform joining, retrying, manufacturer interpretation
  or Thing admission. Consumers must correlate the response with their own
  interview and stable peer identity.
  """

  alias Wotex.Zigbee.Error

  @type ieee_response :: %{
          status: byte(),
          peer_ieee: <<_::64>>,
          network_address: non_neg_integer(),
          start_index: byte(),
          associated_count: byte(),
          associated_devices: [non_neg_integer()]
        }
  @type node_response :: %{
          source_address: non_neg_integer(),
          network_address: non_neg_integer(),
          status: byte(),
          descriptor: map() | nil,
          raw_descriptor: binary()
        }

  @type active_response :: %{
          source_address: non_neg_integer(),
          network_address: non_neg_integer(),
          status: byte(),
          endpoints: [byte()]
        }
  @type simple_response :: %{
          source_address: non_neg_integer(),
          network_address: non_neg_integer(),
          status: byte(),
          descriptor: map() | nil
        }

  @doc """
  Decodes the SWRA198 revision 1.14 IEEE response, preserving raw identity bytes.

  This revision places `StartIndex` before `NumAssocDev`; at most 35 associated
  routes are retained. A nonzero status never verifies the claimed IEEE identity.
  Later firmware layouts need a separately admitted profile.
  """
  @spec ieee_address(binary()) :: {:ok, ieee_response()} | {:error, Error.t()}
  def ieee_address(
        <<status, ieee::binary-size(8), network::little-16, start, count, devices::binary>>
      )
      when byte_size(devices) <= 70 and rem(byte_size(devices), 2) == 0 and
             div(byte_size(devices), 2) <= count and
             (count == 0 or start + div(byte_size(devices), 2) <= count) do
    {:ok,
     %{
       status: status,
       peer_ieee: ieee,
       network_address: network,
       start_index: start,
       associated_count: count,
       associated_devices: clusters(devices)
     }}
  end

  def ieee_address(_), do: invalid()

  @doc "Decodes one fixed-length node descriptor response, retaining all descriptor flag bytes."
  @spec node_descriptor(binary()) :: {:ok, node_response()} | {:error, Error.t()}
  def node_descriptor(<<source::little-16, status, network::little-16, raw::binary-size(13)>>) do
    descriptor = if status == 0, do: node_fields(raw), else: nil

    {:ok,
     %{
       source_address: source,
       network_address: network,
       status: status,
       descriptor: descriptor,
       raw_descriptor: raw
     }}
  end

  def node_descriptor(_), do: invalid()

  defp node_fields(
         <<logical, aps, mac, manufacturer::little-16, buffer, incoming::little-16,
           server::little-16, outgoing::little-16, capabilities>>
       ) do
    %{
      logical_flags: logical,
      logical_type: Bitwise.band(logical, 7),
      aps_flags_frequency: aps,
      mac_capabilities: mac,
      manufacturer_code: manufacturer,
      max_buffer_bytes: buffer,
      max_incoming_transfer_bytes: incoming,
      server_mask: server,
      max_outgoing_transfer_bytes: outgoing,
      descriptor_capabilities: capabilities
    }
  end

  @doc "Decodes one complete `ZDO_ACTIVE_EP_RSP` payload, including failure status."
  @spec active_endpoints(binary()) :: {:ok, active_response()} | {:error, Error.t()}
  def active_endpoints(<<source::little-16, status, network::little-16, count, endpoints::binary>>)
      when count <= 77 and byte_size(endpoints) == count do
    {:ok,
     %{
       source_address: source,
       network_address: network,
       status: status,
       endpoints: :binary.bin_to_list(endpoints)
     }}
  end

  def active_endpoints(_), do: invalid()

  @doc "Decodes one complete `ZDO_SIMPLE_DESC_RSP` payload with bounded cluster lists."
  @spec simple_descriptor(binary()) :: {:ok, simple_response()} | {:error, Error.t()}
  def simple_descriptor(
        <<source::little-16, status, network::little-16, length, descriptor::binary>>
      )
      when byte_size(descriptor) == length and length <= 72 do
    case {status, descriptor} do
      {0, _} ->
        with {:ok, parsed} <- parse_descriptor(descriptor) do
          {:ok,
           %{
             source_address: source,
             network_address: network,
             status: status,
             descriptor: parsed
           }}
        end

      {_, <<>>} ->
        {:ok, %{source_address: source, network_address: network, status: status, descriptor: nil}}

      _ ->
        invalid()
    end
  end

  def simple_descriptor(_), do: invalid()

  defp parse_descriptor(
         <<endpoint, profile::little-16, device::little-16, version, incoming_count, rest::binary>>
       )
       when endpoint in 1..240 and incoming_count <= 16 do
    incoming_bytes = incoming_count * 2

    case rest do
      <<incoming::binary-size(^incoming_bytes), outgoing_count, outgoing::binary>>
      when outgoing_count <= 16 and byte_size(outgoing) == outgoing_count * 2 ->
        {:ok,
         %{
           endpoint: endpoint,
           profile: profile,
           device: device,
           version: version,
           input_clusters: clusters(incoming),
           output_clusters: clusters(outgoing)
         }}

      _ ->
        invalid()
    end
  end

  defp parse_descriptor(_), do: invalid()

  defp clusters(bytes), do: for(<<cluster::little-16 <- bytes>>, do: cluster)
  defp invalid, do: {:error, %Error{kind: :invalid_frame, operation: :zdo}}
end
