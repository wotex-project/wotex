defmodule Wotex.Zigbee.KeyRotation do
  @moduledoc """
  An explicit network-key update, switch and bounded observation request.

  The consumer selects the expected network, current and next key sequence,
  qualified distribution/switch delays and a Basic-response cohort. Keys stay
  in consumer custody and enter only a one-use private serial-write callback.
  This profile uses broadcast destination `0xFFFD`, never an implicit fallback,
  counter reset, re-enrollment or sequence wrap.

  A distribution failure can still replace the coordinator's alternate key.
  A switch send failure can still schedule its local switch. Results preserve
  those uncertainties; later Basic responses do not identify the network key
  that protected them. Exact firmware, sequence/counter continuity, distribution
  policy and independent activation evidence require consumer qualification.
  """

  alias Wotex.Zigbee.{ChannelMigration, Error, PermitJoin}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [
    :coordinator_ieee,
    :extended_pan_id,
    :pan_id,
    :channel,
    :current_sequence,
    :next_sequence,
    :distribution_ms,
    :settle_ms,
    :peer_timeout_ms,
    :peers,
    :correlation_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          coordinator_ieee: <<_::64>>,
          extended_pan_id: <<_::64>>,
          pan_id: 0..65_534,
          channel: 11..26,
          current_sequence: 0..254,
          next_sequence: 1..255,
          distribution_ms: 1..30_000,
          settle_ms: 1..30_000,
          peer_timeout_ms: 1..60_000,
          peers: [ChannelMigration.peer()],
          correlation_id: binary()
        }

  @doc "Builds an inert rotation request with no key bytes and no sequence wrap."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    if Keyword.keyword?(options) and length(options) == length(@enforce_keys) and
         Enum.sort(Keyword.keys(options)) == Enum.sort(@enforce_keys) do
      request = struct(__MODULE__, options)
      if valid?(request), do: {:ok, request}, else: invalid()
    else
      invalid()
    end
  end

  @doc "Revalidates exact fields, network/cohort bounds, delays and the next sequence."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    map_size(request) == 12 and Enum.all?(@enforce_keys, &Map.has_key?(request, &1)) and
      in_range?(request.current_sequence, 0, 254) and
      request.next_sequence === request.current_sequence + 1 and
      in_range?(request.distribution_ms, 1, 30_000) and
      in_range?(request.settle_ms, 1, 30_000) and
      in_range?(request.peer_timeout_ms, 1, 60_000) and
      PermitJoin.valid?(network_request(request)) and
      Wotex.Zigbee.PeerProbe.Policy.valid?(request.peers, request.coordinator_ieee)
  end

  def valid?(_), do: false

  @doc "Checks the expected commissioned network; metadata carries no key-sequence proof."
  @spec matches_snapshot?(t(), Snapshot.t()) :: boolean()
  def matches_snapshot?(request, snapshot) do
    valid?(request) and
      PermitJoin.matches_snapshot?(
        %PermitJoin{
          coordinator_ieee: request.coordinator_ieee,
          extended_pan_id: request.extended_pan_id,
          pan_id: request.pan_id,
          channel: request.channel,
          duration_s: 0,
          tc_significance: 1,
          correlation_id: request.correlation_id
        },
        snapshot
      )
  end

  defp network_request(request),
    do: %PermitJoin{
      coordinator_ieee: request.coordinator_ieee,
      extended_pan_id: request.extended_pan_id,
      pan_id: request.pan_id,
      channel: request.channel,
      duration_s: 0,
      tc_significance: 1,
      correlation_id: request.correlation_id
    }

  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp invalid, do: {:error, %Error{kind: :invalid_value, operation: :key_rotation}}
end
