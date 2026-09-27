defmodule Wotex.Zigbee.DataRequest do
  @moduledoc """
  Bounded AF data request with a durable peer identity and caller correlation.

  `peer_ieee` is the eight raw EUI-64 bytes established by the consumer's
  interview. `route_address` is the current 16 bit network address; it can
  change after rejoin. The caller must establish and maintain that mapping.
  The host does not infer it from a label, route or untrusted report.

  `correlation_id` is caller-chosen opaque context. Neither it nor
  `peer_ieee` is transmitted in the ZNP `AF_DATA_REQUEST`; the NCP receives
  only the finite route, endpoints, cluster, transaction, flags and payload.
  Retain this value to correlate the immediate NCP reply with later APS and
  application indications. An NCP acceptance is not a physical effect.

  This value has no credential field. Network and link keys remain in the
  consumer's explicit coordinator custody, outside public requests and errors.
  Product interpretation and authorization also stay with the consumer.
  """

  alias Wotex.Zigbee.Error

  @enforce_keys [
    :peer_ieee,
    :route_address,
    :destination_endpoint,
    :source_endpoint,
    :cluster,
    :transaction,
    :correlation_id,
    :data
  ]
  defstruct [
    :peer_ieee,
    :route_address,
    :destination_endpoint,
    :source_endpoint,
    :cluster,
    :transaction,
    :correlation_id,
    :data,
    radius: 5,
    aps_ack: true,
    aps_security: true
  ]

  @type t :: %__MODULE__{
          peer_ieee: <<_::64>>,
          route_address: 0..0xFFFE,
          destination_endpoint: 1..240,
          source_endpoint: 1..240,
          cluster: 0..0xFFFF,
          transaction: byte(),
          correlation_id: binary(),
          data: binary(),
          radius: 1..30,
          aps_ack: boolean(),
          aps_security: boolean()
        }

  @allowed ~w(peer_ieee route_address destination_endpoint source_endpoint cluster transaction correlation_id data radius aps_ack aps_security)a

  @doc "Builds a finite request and rejects missing, duplicate or unknown fields."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    if Keyword.keyword?(options) and Enum.all?(Keyword.keys(options), &(&1 in @allowed)) and
         length(options) == length(Enum.uniq(Keyword.keys(options))) do
      request = struct(__MODULE__, options)
      if valid?(request), do: {:ok, request}, else: invalid()
    else
      invalid()
    end
  end

  def new(_), do: invalid()

  @doc "Checks a request again after a caller has copied or modified its struct."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    valid_target?(request) and valid_transfer?(request)
  end

  def valid?(_), do: false

  defp valid_target?(request) do
    valid_ieee?(request.peer_ieee) and
      in_range?(request.route_address, 0, 0xFFFE) and
      in_range?(request.destination_endpoint, 1, 240) and
      in_range?(request.source_endpoint, 1, 240) and
      in_range?(request.cluster, 0, 0xFFFF)
  end

  defp valid_transfer?(request) do
    in_range?(request.transaction, 0, 255) and
      is_binary(request.correlation_id) and
      byte_size(request.correlation_id) in 1..64 and
      is_binary(request.data) and byte_size(request.data) <= 128 and
      in_range?(request.radius, 1, 30) and
      is_boolean(request.aps_ack) and is_boolean(request.aps_security)
  end

  defp valid_ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp valid_ieee?(_), do: false

  defp in_range?(value, minimum, maximum),
    do: is_integer(value) and value >= minimum and value <= maximum

  defp invalid, do: {:error, %Error{kind: :invalid_command, operation: :request}}
end
