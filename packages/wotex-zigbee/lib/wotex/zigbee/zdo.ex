defmodule Wotex.Zigbee.ZDO do
  @moduledoc """
  Finite TI ZNP ZDO descriptor response decoding for device interviews.

  `active_endpoints/1` and `simple_descriptor/1` decode the asynchronous
  responses to the corresponding host requests. Source and described network
  addresses are retained separately; both are transient routes rather than
  durable IEEE identity. Failed ZDO status has no invented endpoint or
  descriptor. Counts and descriptor lengths must match the complete payload.

  This codec does not perform joining, retrying, manufacturer interpretation
  or Thing admission. Consumers must correlate the response with their own
  interview and stable peer identity.
  """

  alias Wotex.Zigbee.Error

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
