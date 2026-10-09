defmodule Wotex.Zigbee.PermitJoin do
  @moduledoc """
  An explicit, finite permit-join request for the pinned TI coordinator.

  The consumer selects the expected coordinator IEEE, extended PAN, PAN and
  channel, a duration of 0–254 seconds and the TCSignificance wire byte.
  Zero requests closure; 255, remote targets and broadcasts are outside this
  local-coordinator profile. Construction performs no I/O or authorization.

  `Wotex.Zigbee.permit_join/4` obtains fresh metadata and calls the consumer's
  credential custody port before dispatch. Keys and counters remain in that
  custody. NCP admission, uncorrelated management responses and local change
  indications are separate observations. No admission proves that joining
  opened or closed, enrolled a peer or used an install code securely.
  """

  alias Wotex.Zigbee.{Error, Frame}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [
    :coordinator_ieee,
    :extended_pan_id,
    :pan_id,
    :channel,
    :duration_s,
    :tc_significance,
    :correlation_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          coordinator_ieee: <<_::64>>,
          extended_pan_id: <<_::64>>,
          pan_id: 0..65_534,
          channel: 11..26,
          duration_s: 0..254,
          tc_significance: 0 | 1,
          correlation_id: binary()
        }
  @type response :: %{source_address: 0..65_535, status: byte()}
  @type indication :: %{duration_s: byte()}

  @doc "Builds an inert request with an explicit expected network and finite duration."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    if Keyword.keyword?(options) and length(options) == length(@enforce_keys) and
         Enum.sort(Keyword.keys(options)) == Enum.sort(@enforce_keys) do
      request = struct(__MODULE__, options)
      if valid?(request), do: {:ok, request}, else: failure(:invalid_value)
    else
      failure(:invalid_value)
    end
  end

  @doc "Revalidates every field, rejecting copied values with foreign or missing fields."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    map_size(request) == 8 and Enum.all?(@enforce_keys, &Map.has_key?(request, &1)) and
      identity?(request.coordinator_ieee) and identity?(request.extended_pan_id) and
      in_range?(request.pan_id, 0, 65_534) and in_range?(request.channel, 11, 26) and
      in_range?(request.duration_s, 0, 254) and request.tc_significance in [0, 1] and
      is_binary(request.correlation_id) and byte_size(request.correlation_id) in 1..64
  end

  def valid?(_), do: false

  @doc "Builds the exact five-byte MT request for address mode 2 and coordinator address 0."
  @spec frame(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def frame(request) do
    if valid?(request) do
      {:ok,
       %Frame{
         type: :sreq,
         subsystem: 5,
         id: 0x36,
         payload: <<2, 0::little-16, request.duration_s, request.tc_significance>>
       }}
    else
      failure(:invalid_value)
    end
  end

  @doc "Checks expected identity against complete matching coordinator metadata, without granting authority."
  @spec matches_snapshot?(t(), Snapshot.t()) :: boolean()
  def matches_snapshot?(request, snapshot) do
    if valid?(request) and Snapshot.valid?(snapshot) and snapshot.outcome == :observed and
         snapshot.consistency == :matching do
      [%{value: device}, %{value: network}] = snapshot.readings

      device.coordinator_ieee == request.coordinator_ieee and device.network_address == 0 and
        device.device_state == 9 and Bitwise.band(device.capabilities, 1) == 1 and
        network.extended_pan_id == request.extended_pan_id and network.pan_id == request.pan_id and
        network.channel == request.channel
    else
      false
    end
  end

  @doc "Decodes a raw management response; it carries no duration or transaction token."
  @spec response(binary()) :: {:ok, response()} | {:error, Error.t()}
  def response(<<source::little-16, status>>),
    do: {:ok, %{source_address: source, status: status}}

  def response(_), do: failure(:invalid_frame)

  @doc "Decodes a local change indication, preserving even an unsupported reported duration."
  @spec indication(binary()) :: {:ok, indication()} | {:error, Error.t()}
  def indication(<<duration>>), do: {:ok, %{duration_s: duration}}
  def indication(_), do: failure(:invalid_frame)

  defp identity?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp identity?(_), do: false
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :permit_join}}
end
