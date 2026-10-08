defmodule Wotex.Zigbee.Binding do
  @moduledoc """
  Explicit, inert TI ZNP Bind and Unbind requests for one adopted source peer.

  The finite profile pins SDK 2.30.00.34, Monitor/Test SWRA198 revision 1.14,
  sections 3.12.1.14–15 and 3.12.2.13–14. Select a raw IEEE binding source,
  its current unicast route, source endpoint, cluster and either an IEEE
  destination/endpoint or group destination. Source IEEE identity is a
  defined MT field; caller correlation stays on the host.

  Use `Wotex.Zigbee.change_binding/4` only after consumer authorization,
  destination qualification and battery-policy review. Construction performs
  no binding, joining, reporting change or I/O. A binding response supplies
  only a source address and status, with no echoed binding fields or host
  transaction token. The owner retires each route/operation pair for its
  epoch rather than matching a delayed callback to a second request.
  """

  alias Wotex.Zigbee.{Error, Frame}

  @fields [
    :operation,
    :peer_ieee,
    :route_address,
    :source_endpoint,
    :cluster,
    :target,
    :correlation_id
  ]
  @enforce_keys @fields
  defstruct @fields

  @type target :: {:ieee, <<_::64>>, 1..240} | {:group, 0..0xFFF7}
  @type response :: %{operation: :bind | :unbind, source_address: 0..0xFFF7, status: byte()}
  @type t :: %__MODULE__{
          operation: :bind | :unbind,
          peer_ieee: <<_::64>>,
          route_address: 0..0xFFF7,
          source_endpoint: 1..240,
          cluster: 0..0xFFFF,
          target: target(),
          correlation_id: binary()
        }

  @doc """
  Builds a complete request with explicit operation and destination.

  All fields are required. `operation` is `:bind` or `:unbind`; `target` is
  `{:ieee, raw_eight_bytes, endpoint}` or `{:group, group_id}`. Raw IEEE bytes
  use the NCP wire order consistently with interview identity. Group IDs
  admit 0 through `0xFFF7` and carry no endpoint. `correlation_id` is 1–64
  opaque bytes and is never transmitted. Unknown and duplicate options fail.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    if Keyword.keyword?(options) and length(options) == length(@fields) and
         Enum.sort(Keyword.keys(options)) == Enum.sort(@fields) do
      request = struct!(__MODULE__, options)
      if valid?(request), do: {:ok, request}, else: failure(:invalid_value)
    else
      failure(:invalid_value)
    end
  end

  def new(_), do: failure(:invalid_value)

  @doc "Revalidates complete request fields, target layout and bounds after copying."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    map_size(request) == length(@fields) + 1 and
      Enum.all?(@fields, &Map.has_key?(request, &1)) and
      request.operation in [:bind, :unbind] and ieee?(request.peer_ieee) and
      in_range?(request.route_address, 0, 0xFFF7) and endpoint?(request.source_endpoint) and
      in_range?(request.cluster, 0, 0xFFFF) and target?(request.target) and
      is_binary(request.correlation_id) and byte_size(request.correlation_id) in 1..64
  end

  def valid?(_), do: false

  @doc """
  Encodes exactly one finite Bind/Unbind MT frame without dispatching it.

  Both target modes use a 23-byte MT payload. IEEE targets use address mode
  three; groups use mode one, the low two bytes of the eight-byte destination
  field and seven trailing zero bytes (six address bytes and endpoint zero).
  This follows the exact SDK Bind/Unbind parser; the revision 1.14 document's
  variable-width usage grid disagrees with that parser. There is no implicit
  destination, short-address binding mode or broadcast request.
  Ordinary `Wotex.Zigbee.Command` admission excludes these frames; use the
  explicit owner workflow with current source custody.
  """
  @spec frame(t()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def frame(request) do
    if valid?(request) do
      id = if request.operation == :bind, do: 0x21, else: 0x22

      prefix =
        <<request.route_address::little-16, request.peer_ieee::binary, request.source_endpoint,
          request.cluster::little-16>>

      {:ok,
       %Frame{
         type: :sreq,
         subsystem: 5,
         id: id,
         payload: <<prefix::binary, target_bytes(request.target)::binary>>
       }}
    else
      failure(:invalid_value)
    end
  end

  @doc "Decodes the complete three-byte source/status callback without inventing binding fields."
  @spec response(:bind | :unbind, binary()) :: {:ok, response()} | {:error, Error.t()}
  def response(operation, <<source::little-16, status>>)
      when operation in [:bind, :unbind] and source in 0..0xFFF7,
      do: {:ok, %{operation: operation, source_address: source, status: status}}

  def response(_, _), do: failure(:invalid_frame)

  defp target_bytes({:ieee, ieee, endpoint}), do: <<3, ieee::binary, endpoint>>
  defp target_bytes({:group, group}), do: <<1, group::little-16, 0::56>>
  defp target?({:ieee, ieee, endpoint}), do: ieee?(ieee) and endpoint?(endpoint)
  defp target?({:group, group}), do: in_range?(group, 0, 0xFFF7)
  defp target?(_), do: false
  defp ieee?(<<value::64>>), do: value not in [0, 0xFFFFFFFFFFFFFFFF]
  defp ieee?(_), do: false
  defp endpoint?(value), do: in_range?(value, 1, 240)
  defp in_range?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :binding}}
end
