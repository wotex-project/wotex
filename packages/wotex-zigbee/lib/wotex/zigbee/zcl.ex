defmodule Wotex.Zigbee.ZCL do
  @moduledoc """
  Bounded ZCL global attribute commands for the admitted Zigbee profile.

  `read_attributes/4` produces a global Read Attributes command in the selected
  direction. `decode_attributes/3` accepts Read Attributes Responses and
  Reports only, retaining source command, manufacturer code, direction, sequence, attribute
  ID, type and status. A failed read has no value; a valid ZCL null remains
  distinct from an unsupported type or malformed wire value. Manufacturer
  types remain opaque bytes for the consumer to interpret. This module does
  not assign Thing or product semantics to cluster and attribute numbers.

  The codec caps a frame at 128 bytes, 32 attributes and 64 bytes per string.
  Nested ZCL collections are deliberately outside this finite profile.
  Boolean, uint8/16/32, int8/16 and short-string non-values follow ZCL
  document 07-5123 revision 8. Numeric attributes whose adopted definition
  admits the full range require explicit `decode_attributes/3` policy.
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

  @doc """
  Decodes one finite Read Attributes Response or Report Attributes frame.

  Standard non-values become `:null`, with their original wire bytes in
  `:raw`. The optional `full_range_ids` list selects at most 32 distinct
  numeric attribute IDs whose adopted definition uses the full range,
  including the otherwise reserved non-value. Those records retain their
  integer value. Selection for a successful nonnumeric record is refused.
  The caller owns the cluster and manufacturer context that justifies this policy.

  An unsupported type has unknown width in this finite profile. Its `:raw`
  retains the entire remaining payload, and no further record boundaries are
  inferred from that opaque tail.
  """
  @spec decode_attributes(binary(), pos_integer(), [non_neg_integer()]) ::
          {:ok, decoded()} | {:error, Error.t()}
  def decode_attributes(bytes, max_attributes \\ @max_attributes, full_range_ids \\ [])

  def decode_attributes(bytes, max_attributes, full_range_ids)
      when is_binary(bytes) and byte_size(bytes) <= @max_frame and
             is_integer(max_attributes) and max_attributes in 1..@max_attributes and
             is_list(full_range_ids) and length(full_range_ids) <= @max_attributes do
    with true <- full_range_ids?(full_range_ids),
         {:ok, header, payload} <- parse_header(bytes),
         true <- header.command in [:read_response, :report],
         {:ok, attributes} <-
           parse_attributes(payload, header.command, max_attributes, full_range_ids, []) do
      {:ok, Map.put(header, :attributes, attributes)}
    else
      _ -> invalid()
    end
  end

  def decode_attributes(_, _, _), do: invalid()

  defp full_range_ids?(ids),
    do:
      Enum.all?(ids, &(is_integer(&1) and &1 in 0..0xFFFF)) and
        length(ids) == length(Enum.uniq(ids))

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

  defp parse_attributes(<<>>, _, _, _, []), do: invalid()
  defp parse_attributes(<<>>, _, _, _, attributes), do: {:ok, Enum.reverse(attributes)}
  defp parse_attributes(_, _, 0, _, _), do: invalid()

  defp parse_attributes(
         <<id::little-16, status, rest::binary>>,
         :read_response,
         remaining,
         full_range_ids,
         attributes
       )
       when status != 0 do
    attribute = %{id: id, status: {:error, status}, type: nil, value: nil, raw: nil}
    parse_attributes(rest, :read_response, remaining - 1, full_range_ids, [attribute | attributes])
  end

  defp parse_attributes(
         <<id::little-16, 0, type, rest::binary>>,
         :read_response,
         remaining,
         full_range_ids,
         attributes
       ) do
    append_value(id, type, rest, :read_response, remaining, full_range_ids, attributes)
  end

  defp parse_attributes(
         <<id::little-16, type, rest::binary>>,
         :report,
         remaining,
         full_range_ids,
         attributes
       ) do
    append_value(id, type, rest, :report, remaining, full_range_ids, attributes)
  end

  defp parse_attributes(_, _, _, _, _), do: invalid()

  defp append_value(id, type, rest, command, remaining, full_range_ids, attributes) do
    with {:ok, value, raw, tail} <- value(type, rest, id in full_range_ids) do
      attribute = %{id: id, status: :success, type: type, value: value, raw: raw}
      parse_attributes(tail, command, remaining - 1, full_range_ids, [attribute | attributes])
    end
  end

  defp value(type, _, true) when type not in [0x20, 0x21, 0x23, 0x28, 0x29], do: invalid()

  defp value(0x10, <<0xFF, rest::binary>>, false), do: {:ok, :null, <<0xFF>>, rest}

  defp value(0x10, <<value, rest::binary>>, false) when value in [0, 1],
    do: {:ok, value == 1, <<value>>, rest}

  defp value(0x20, <<value, rest::binary>>, full),
    do: numeric(value, 0xFF, full, <<value>>, rest)

  defp value(0x21, <<value::little-16, rest::binary>>, full),
    do: numeric(value, 0xFFFF, full, <<value::little-16>>, rest)

  defp value(0x23, <<value::little-32, rest::binary>>, full),
    do: numeric(value, 0xFFFFFFFF, full, <<value::little-32>>, rest)

  defp value(0x28, <<value::signed-8, rest::binary>>, full),
    do: numeric(value, -128, full, <<value::signed-8>>, rest)

  defp value(0x29, <<value::little-signed-16, rest::binary>>, full),
    do: numeric(value, -32_768, full, <<value::little-signed-16>>, rest)

  defp value(type, <<length, rest::binary>>, false)
       when type in [0x41, 0x42] and length <= 64 and
              byte_size(rest) >= length do
    <<raw::binary-size(^length), tail::binary>> = rest
    {:ok, raw, <<length, raw::binary>>, tail}
  end

  defp value(0x41, <<0xFF, rest::binary>>, false), do: {:ok, :null, <<0xFF>>, rest}
  defp value(0x42, <<0xFF, rest::binary>>, false), do: {:ok, :null, <<0xFF>>, rest}

  defp value(type, rest, false) when type not in [0x10, 0x20, 0x21, 0x23, 0x28, 0x29, 0x41, 0x42],
    do: {:ok, {:unsupported, type}, rest, <<>>}

  defp value(_, _, _), do: invalid()

  defp numeric(value, non_value, full, raw, rest),
    do: {:ok, if(not full and value == non_value, do: :null, else: value), raw, rest}

  defp invalid, do: {:error, %Error{kind: :invalid_frame, operation: :zcl}}
end
