defmodule Wotex.Zigbee.ZCL do
  @moduledoc """
  Bounded ZCL global attribute commands for the admitted Zigbee profile.

  `read_attributes/4` produces a client-to-server Read Attributes command.
  `decode_attributes/2` accepts Read Attributes Responses and Reports only,
  retaining source command, manufacturer code, direction, sequence, attribute
  ID, type and status. A failed read has no value; a valid ZCL null remains
  distinct from an unsupported type or malformed wire value. Manufacturer
  types remain opaque bytes for the consumer to interpret. This module does
  not assign Thing or product semantics to cluster and attribute numbers.

  The codec caps a frame at 128 bytes, 32 attributes and 64 bytes per string.
  Nested ZCL collections are deliberately outside this finite profile.
  """

  import Bitwise

  alias Wotex.Zigbee.Error

  @max_frame 128
  @max_attributes 32

  @type direction :: :client_to_server | :server_to_client
  @type attribute :: %{
          id: non_neg_integer(),
          status: :success | {:error, byte()},
          type: byte() | nil,
          value: term(),
          raw: binary() | nil
        }
  @type decoded :: %{
          command: :read_response | :report,
          manufacturer: non_neg_integer() | nil,
          direction: direction(),
          sequence: byte(),
          attributes: [attribute()]
        }

  @doc "Encodes at most 32 attribute IDs into a bounded global read request."
  @spec read_attributes([non_neg_integer()], byte(), direction(), non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, Error.t()}
  def read_attributes(ids, sequence, direction, manufacturer \\ nil)

  def read_attributes(ids, sequence, direction, manufacturer)
      when is_list(ids) and length(ids) in 1..@max_attributes and
             is_integer(sequence) and sequence in 0..255 and
             direction in [:client_to_server, :server_to_client] do
    if Enum.all?(ids, &(is_integer(&1) and &1 in 0..0xFFFF)) do
      with {:ok, header} <- header(0x00, sequence, direction, manufacturer) do
        payload = Enum.reduce(ids, <<>>, fn id, bytes -> <<bytes::binary, id::little-16>> end)
        {:ok, <<header::binary, payload::binary>>}
      end
    else
      invalid()
    end
  end

  def read_attributes(_, _, _, _), do: invalid()

  @doc "Decodes one finite Read Attributes Response or Report Attributes frame."
  @spec decode_attributes(binary(), pos_integer()) :: {:ok, decoded()} | {:error, Error.t()}
  def decode_attributes(bytes, max_attributes \\ @max_attributes)

  def decode_attributes(bytes, max_attributes)
      when is_binary(bytes) and byte_size(bytes) <= @max_frame and
             is_integer(max_attributes) and max_attributes in 1..@max_attributes do
    with {:ok, header, payload} <- parse_header(bytes),
         true <- header.command in [:read_response, :report],
         {:ok, attributes} <- parse_attributes(payload, header.command, max_attributes, []) do
      {:ok, Map.put(header, :attributes, attributes)}
    else
      _ -> invalid()
    end
  end

  def decode_attributes(_, _), do: invalid()

  defp header(command, sequence, direction, manufacturer) do
    direction_bit = if direction == :server_to_client, do: 0x08, else: 0

    case manufacturer do
      nil ->
        {:ok, <<direction_bit, sequence, command>>}

      code when is_integer(code) and code in 0..0xFFFF ->
        {:ok, <<0x04 ||| direction_bit, code::little-16, sequence, command>>}

      _ ->
        invalid()
    end
  end

  defp parse_header(<<control, rest::binary>>) when (control &&& 0xE3) == 0 do
    manufacturer = (control &&& 0x04) != 0
    direction = if (control &&& 0x08) == 0, do: :client_to_server, else: :server_to_client

    case {manufacturer, rest} do
      {false, <<sequence, command, payload::binary>>} ->
        parsed_header(nil, direction, sequence, command, payload)

      {true, <<code::little-16, sequence, command, payload::binary>>} ->
        parsed_header(code, direction, sequence, command, payload)

      _ ->
        invalid()
    end
  end

  defp parse_header(_), do: invalid()

  defp parsed_header(manufacturer, direction, sequence, command, payload) do
    kind =
      case command do
        0x01 -> :read_response
        0x0A -> :report
        _ -> :unsupported
      end

    {:ok, %{command: kind, manufacturer: manufacturer, direction: direction, sequence: sequence},
     payload}
  end

  defp parse_attributes(<<>>, _, _, []), do: invalid()
  defp parse_attributes(<<>>, _, _, attributes), do: {:ok, Enum.reverse(attributes)}
  defp parse_attributes(_, _, 0, _), do: invalid()

  defp parse_attributes(
         <<id::little-16, status, rest::binary>>,
         :read_response,
         remaining,
         attributes
       )
       when status != 0 do
    attribute = %{id: id, status: {:error, status}, type: nil, value: nil, raw: nil}
    parse_attributes(rest, :read_response, remaining - 1, [attribute | attributes])
  end

  defp parse_attributes(
         <<id::little-16, 0, type, rest::binary>>,
         :read_response,
         remaining,
         attributes
       ) do
    append_value(id, type, rest, :read_response, remaining, attributes)
  end

  defp parse_attributes(<<id::little-16, type, rest::binary>>, :report, remaining, attributes) do
    append_value(id, type, rest, :report, remaining, attributes)
  end

  defp parse_attributes(_, _, _, _), do: invalid()

  defp append_value(id, type, rest, command, remaining, attributes) do
    with {:ok, value, raw, tail} <- value(type, rest) do
      attribute = %{id: id, status: :success, type: type, value: value, raw: raw}
      parse_attributes(tail, command, remaining - 1, [attribute | attributes])
    end
  end

  defp value(0x10, <<value, rest::binary>>) when value in [0, 1],
    do: {:ok, value == 1, <<value>>, rest}

  defp value(0x20, <<value, rest::binary>>), do: {:ok, value, <<value>>, rest}

  defp value(0x21, <<value::little-16, rest::binary>>),
    do: {:ok, value, <<value::little-16>>, rest}

  defp value(0x23, <<value::little-32, rest::binary>>),
    do: {:ok, value, <<value::little-32>>, rest}

  defp value(0x28, <<value::signed-8, rest::binary>>),
    do: {:ok, value, <<value::signed-8>>, rest}

  defp value(0x29, <<value::little-signed-16, rest::binary>>),
    do: {:ok, value, <<value::little-signed-16>>, rest}

  defp value(type, <<length, rest::binary>>)
       when type in [0x41, 0x42] and length <= 64 and
              byte_size(rest) >= length do
    <<raw::binary-size(^length), tail::binary>> = rest
    {:ok, raw, <<length, raw::binary>>, tail}
  end

  defp value(0x41, <<0xFF, rest::binary>>), do: {:ok, :null, <<0xFF>>, rest}
  defp value(0x42, <<0xFF, rest::binary>>), do: {:ok, :null, <<0xFF>>, rest}

  defp value(type, rest) when type not in [0x10, 0x20, 0x21, 0x23, 0x28, 0x29, 0x41, 0x42],
    do: {:ok, {:unsupported, type}, rest, <<>>}

  defp value(_, _), do: invalid()

  defp invalid, do: {:error, %Error{kind: :invalid_frame, operation: :zcl}}
end
