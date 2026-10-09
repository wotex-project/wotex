defmodule Wotex.Zigbee.Network do
  @moduledoc """
  Finite, inert coordinator and network metadata for the pinned TI ZNP backend.

  The profile uses SDK 2.30.00.34, SWRA198 revision 1.14 sections 3.10.1.1
  and 3.12.1.48, resolved against the exact SDK parsers. Device information
  retains raw IEEE identity, route, capability bits, state and up to 64
  associated routes. Network information retains route, state, PAN/extended
  PAN, parent addresses and channel. Uninitialized and unknown reported
  values remain visible; decoding establishes no usable or secure network.

  Use `Wotex.Zigbee.inspect_network/2` for explicit owner-backed inspection.
  This profile never reads keys or counters, forms a network, opens joining
  or changes configuration. Metadata is distinct from qualified credential
  custody, backup continuity, radio authentication and physical reachability.
  """

  alias Wotex.Zigbee.{Error, Frame}

  @type phase :: :device_info | :network_info
  @type device_info :: %{
          status: byte(),
          coordinator_ieee: <<_::64>>,
          network_address: 0..65_535,
          capabilities: byte(),
          device_state: byte(),
          associated_routes: [0..65_535]
        }
  @type network_info :: %{
          network_address: 0..65_535,
          device_state: byte(),
          pan_id: 0..65_535,
          parent_address: 0..65_535,
          extended_pan_id: <<_::64>>,
          parent_ieee: <<_::64>>,
          channel: byte()
        }

  @doc "Builds one empty-payload metadata query without performing serial I/O."
  @spec frame(phase()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def frame(:device_info), do: {:ok, %Frame{type: :sreq, subsystem: 7, id: 0, payload: <<>>}}
  def frame(:network_info), do: {:ok, %Frame{type: :sreq, subsystem: 5, id: 0x50, payload: <<>>}}
  def frame(_), do: failure(:invalid_command)

  @doc """
  Decodes the complete device-info response, preserving status and associated routes.

  The exact layout has a 14-byte fixed prefix followed by two bytes per
  associated route. The finite profile admits at most 64 routes, with order,
  duplicates and reserved address values unchanged. Failed status does not
  become successful identity evidence. Truncation and trailing bytes fail.
  """
  @spec device_info(binary()) :: {:ok, device_info()} | {:error, Error.t()}
  def device_info(
        <<status, ieee::binary-size(8), address::little-16, capabilities, state, count,
          routes::binary>>
      )
      when count <= 64 and byte_size(routes) == count * 2 do
    {:ok,
     %{
       status: status,
       coordinator_ieee: ieee,
       network_address: address,
       capabilities: capabilities,
       device_state: state,
       associated_routes: for(<<route::little-16 <- routes>>, do: route)
     }}
  end

  def device_info(_), do: failure(:invalid_frame)

  @doc """
  Decodes the exact 24-byte SDK network-info response without inventing a status.

  The SDK includes one device-state byte after the short address and one
  channel byte at the end. Revision 1.14's grid omits that state and describes
  a two-byte channel; this profile follows the pinned source, with no fallback.
  Reserved/uninitialized PANs, addresses, identities and channels remain raw
  evidence and are not silently normalized into a commissioned network.
  """
  @spec network_info(binary()) :: {:ok, network_info()} | {:error, Error.t()}
  def network_info(
        <<address::little-16, state, pan::little-16, parent::little-16,
          extended_pan::binary-size(8), parent_ieee::binary-size(8), channel>>
      ),
      do:
        {:ok,
         %{
           network_address: address,
           device_state: state,
           pan_id: pan,
           parent_address: parent,
           extended_pan_id: extended_pan,
           parent_ieee: parent_ieee,
           channel: channel
         }}

  def network_info(_), do: failure(:invalid_frame)

  defp failure(kind), do: {:error, %Error{kind: kind, operation: :network}}
end
