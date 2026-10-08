defmodule Wotex.Zigbee.Command do
  @moduledoc """
  Finite, non-administrative TI ZNP commands admitted by this host profile.

  A successful SRSP says the NCP accepted a request. Later ZDO responses,
  AF confirms and attribute reports are separate events. No public raw MT
  command escape hatch exists: forming, erasing or restoring a network needs
  an independently specified and explicitly authorized administrative API.
  """

  alias Wotex.Zigbee.{Error, Frame}

  @doc "Requests the NCP's five-byte firmware version during startup."
  @spec version() :: Frame.t()
  def version, do: %Frame{type: :sreq, subsystem: 1, id: 2, payload: <<>>}

  @doc "Queries one unicast route's IEEE identity; the later response remains separate."
  @spec ieee_address(non_neg_integer()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def ieee_address(address) when is_integer(address) and address in 0..0xFFF7,
    do: {:ok, %Frame{type: :sreq, subsystem: 5, id: 1, payload: <<address::little-16, 0, 0>>}}

  def ieee_address(_), do: invalid()

  @doc "Requests the node descriptor of one known unicast route."
  @spec node_descriptor(non_neg_integer()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def node_descriptor(address) when is_integer(address) and address in 0..0xFFF7 do
    {:ok,
     %Frame{
       type: :sreq,
       subsystem: 5,
       id: 2,
       payload: <<address::little-16, address::little-16>>
     }}
  end

  def node_descriptor(_), do: invalid()

  @doc "Requests a device's active endpoints; the later ZDO response is an event."
  @spec active_endpoints(non_neg_integer()) :: {:ok, Frame.t()} | {:error, Error.t()}
  def active_endpoints(address) when is_integer(address) and address in 0..0xFFFE do
    {:ok,
     %Frame{
       type: :sreq,
       subsystem: 5,
       id: 5,
       payload: <<address::little-16, address::little-16>>
     }}
  end

  def active_endpoints(_), do: invalid()

  @doc "Requests one simple descriptor; its eventual response is a separate event."
  @spec simple_descriptor(non_neg_integer(), pos_integer()) ::
          {:ok, Frame.t()} | {:error, Error.t()}
  def simple_descriptor(address, endpoint)
      when is_integer(address) and address in 0..0xFFFE and is_integer(endpoint) and
             endpoint in 1..240 do
    {:ok,
     %Frame{
       type: :sreq,
       subsystem: 5,
       id: 4,
       payload: <<address::little-16, address::little-16, endpoint>>
     }}
  end

  def simple_descriptor(_, _), do: invalid()

  @doc """
  Admits one bounded AF data request with a caller-selected transaction ID.

  The NCP's SRSP and later AF_DATA_CONFIRM remain separate. `options` is
  limited to APS acknowledgement and APS security flags; radius is finite.
  """
  @spec data_request(
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          keyword()
        ) :: {:ok, Frame.t()} | {:error, Error.t()}
  def data_request(
        address,
        destination_endpoint,
        source_endpoint,
        cluster,
        transaction,
        data,
        options \\ []
      )

  def data_request(
        address,
        destination_endpoint,
        source_endpoint,
        cluster,
        transaction,
        data,
        options
      )
      when is_list(options) do
    if valid_options?(options) do
      build_data_request(
        address,
        destination_endpoint,
        source_endpoint,
        cluster,
        transaction,
        data,
        options
      )
    else
      invalid()
    end
  end

  def data_request(_, _, _, _, _, _, _), do: invalid()

  @doc "Checks complete ordinary commands against the finite non-administrative profile."
  @spec admitted?(term()) :: boolean()
  def admitted?(
        %Frame{type: :sreq, subsystem: 5, id: 1, payload: <<address::little-16, 0, 0>>} = frame
      ),
      do: match_frame(frame, ieee_address(address))

  def admitted?(
        %Frame{
          type: :sreq,
          subsystem: 5,
          id: id,
          payload: <<address::little-16, address::little-16>>
        } = frame
      )
      when id in [2, 5] do
    command = if id == 2, do: node_descriptor(address), else: active_endpoints(address)
    match_frame(frame, command)
  end

  def admitted?(
        %Frame{
          type: :sreq,
          subsystem: 5,
          id: 4,
          payload: <<address::little-16, address::little-16, endpoint>>
        } = frame
      ),
      do: match_frame(frame, simple_descriptor(address, endpoint))

  def admitted?(
        %Frame{
          type: :sreq,
          subsystem: 4,
          id: 1,
          payload:
            <<address::little-16, destination, source, cluster::little-16, transaction, flags,
              radius, length, data::binary>>
        } = frame
      )
      when byte_size(data) == length do
    command =
      data_request(address, destination, source, cluster, transaction, data,
        radius: radius,
        aps_ack: Bitwise.band(flags, 0x10) != 0,
        aps_security: Bitwise.band(flags, 0x40) != 0
      )

    match_frame(frame, command)
  end

  def admitted?(_), do: false

  defp match_frame(frame, {:ok, frame}), do: true
  defp match_frame(_, _), do: false

  defp build_data_request(
         address,
         destination_endpoint,
         source_endpoint,
         cluster,
         transaction,
         data,
         options
       ) do
    radius = Keyword.get(options, :radius, 5)
    aps_ack = Keyword.get(options, :aps_ack, true)
    aps_security = Keyword.get(options, :aps_security, true)

    checks = [
      valid_uint?(address, 0xFFFE),
      valid_endpoint?(destination_endpoint),
      valid_endpoint?(source_endpoint),
      valid_uint?(cluster, 0xFFFF),
      valid_uint?(transaction, 255),
      valid_payload?(data),
      valid_radius?(radius),
      is_boolean(aps_ack),
      is_boolean(aps_security)
    ]

    if Enum.all?(checks) do
      flags = if(aps_ack, do: 0x10, else: 0) + if aps_security, do: 0x40, else: 0

      {:ok,
       %Frame{
         type: :sreq,
         subsystem: 4,
         id: 1,
         payload:
           <<address::little-16, destination_endpoint, source_endpoint, cluster::little-16,
             transaction, flags, radius, byte_size(data), data::binary>>
       }}
    else
      invalid()
    end
  end

  defp valid_options?(options) do
    Keyword.keyword?(options) and
      Enum.all?(Keyword.keys(options), &(&1 in [:radius, :aps_ack, :aps_security])) and
      length(options) == length(Enum.uniq(Keyword.keys(options)))
  end

  defp valid_uint?(value, maximum), do: is_integer(value) and value in 0..maximum
  defp valid_endpoint?(value), do: is_integer(value) and value in 1..240
  defp valid_radius?(value), do: is_integer(value) and value in 1..30
  defp valid_payload?(value), do: is_binary(value) and byte_size(value) <= 128

  defp invalid, do: {:error, %Error{kind: :invalid_command, operation: :command}}
end
