defmodule Wotex.Zigbee.ChannelMigration do
  @moduledoc """
  An explicit channel change and bounded Basic-response observation cohort.

  The consumer selects the expected coordinator and network, a different
  channel, a qualified settling delay and 1–32 peers with current route custody
  and Basic server endpoints. The pinned SDK broadcasts to `0xFFFD` and sends
  a local copy; its reply exposes only the local send status. Sleepy devices
  are not guaranteed to receive that broadcast.

  `Wotex.Zigbee.migrate_channel/5` checks fresh metadata and consumer credential
  authorization, waits once, checks the new local channel and probes each
  peer once. The consumer must qualify firmware network-manager support,
  update-ID headroom, administrative pacing and the settling delay. This
  value contains no keys and performs no I/O, authorization or recovery.
  """

  alias Wotex.Zigbee.{Error, Frame, PermitJoin}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [
    :coordinator_ieee,
    :extended_pan_id,
    :pan_id,
    :channel,
    :target_channel,
    :settle_ms,
    :peer_timeout_ms,
    :peers,
    :correlation_id
  ]
  defstruct @enforce_keys

  @type peer :: %{
          peer_ieee: <<_::64>>,
          route_address: 1..0xFFF7,
          source_endpoint: 1..240,
          destination_endpoint: 1..240
        }
  @type t :: %__MODULE__{
          coordinator_ieee: <<_::64>>,
          extended_pan_id: <<_::64>>,
          pan_id: 0..65_534,
          channel: 11..26,
          target_channel: 11..26,
          settle_ms: 1..30_000,
          peer_timeout_ms: 1..60_000,
          peers: [peer()],
          correlation_id: binary()
        }

  @doc "Builds an inert, explicitly bounded migration request and observation cohort."
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

  @doc "Checks the complete request, exact peer shapes and distinct identities/routes."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    map_size(request) == 10 and Enum.all?(@enforce_keys, &Map.has_key?(request, &1)) and
      PermitJoin.valid?(network_request(request, request.channel)) and
      in_range?(request.target_channel, 11, 26) and request.target_channel != request.channel and
      in_range?(request.settle_ms, 1, 30_000) and
      in_range?(request.peer_timeout_ms, 1, 60_000) and
      Wotex.Zigbee.PeerProbe.Policy.valid?(request.peers, request.coordinator_ieee)
  end

  def valid?(_), do: false

  @doc "Builds the eleven-byte pinned MT broadcast channel-change request."
  @spec frame(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def frame(request) do
    if valid?(request) do
      mask = Bitwise.bsl(1, request.target_channel)

      {:ok,
       %Frame{
         type: :sreq,
         subsystem: 5,
         id: 0x37,
         payload: <<0xFFFD::little-16, 0x0F, mask::little-32, 0xFE, 0, 0::little-16>>
       }}
    else
      invalid()
    end
  end

  @doc "Compares complete coordinator metadata with the selected original or target channel."
  @spec matches_snapshot?(t(), Snapshot.t(), :before | :after) :: boolean()
  def matches_snapshot?(request, snapshot, phase) when phase in [:before, :after] do
    if valid?(request) do
      channel = if phase == :before, do: request.channel, else: request.target_channel
      PermitJoin.matches_snapshot?(network_request(request, channel), snapshot)
    else
      false
    end
  end

  def matches_snapshot?(_, _, _), do: false

  defp network_request(request, channel),
    do: %PermitJoin{
      coordinator_ieee: request.coordinator_ieee,
      extended_pan_id: request.extended_pan_id,
      pan_id: request.pan_id,
      channel: channel,
      duration_s: 0,
      tc_significance: 1,
      correlation_id: request.correlation_id
    }

  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp invalid, do: {:error, %Error{kind: :invalid_value, operation: :channel_migration}}
end
