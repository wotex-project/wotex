defmodule Wotex.OPCUA.Binary.DataValue do
  @moduledoc """
  Preserves OPC UA DataValue presence, status and exact timestamp metadata.

  `Wotex.OPCUA.Binary` delegates DataValue encoding and decoding to this pure
  helper. Every semantic value declares `has_value` and an unsigned StatusCode;
  a present value contains an explicit Variant. Absent data and a present null
  Variant are distinct. Bad and Uncertain statuses remain valid decoded data;
  the service adapter separately decides whether an operation succeeds.

  Timestamps retain signed 64-bit ticks of 100 ns since the OPC UA epoch.
  Optional fractions count 10 ps intervals and require their matching timestamp
  on encode. Decoding clamps fractions at 9999 and consumes but omits orphan
  fractions as required by Part 6. A complete value consumes at most 1 MiB,
  including metadata, with an exact unconsumed tail. Unknown keys, reserved mask
  bits and malformed values return structured errors without transport or SDK
  activity.
  """

  import Bitwise
  alias Wotex.OPCUA.{Binary, Error}
  alias Wotex.OPCUA.Binary.Variant

  @limit 1_048_576
  @fields [
    {:source_timestamp, 4, :int64, nil},
    {:source_picoseconds, 16, :uint16, :source_timestamp},
    {:server_timestamp, 8, :int64, nil},
    {:server_picoseconds, 32, :uint16, :server_timestamp}
  ]
  @keys [:has_value, :value, :status | Enum.map(@fields, &elem(&1, 0))]
  @type t :: %{
          required(:has_value) => boolean(),
          required(:status) => 0..4_294_967_295,
          optional(:value) => Variant.t(),
          optional(:source_timestamp) => integer(),
          optional(:server_timestamp) => integer(),
          optional(:source_picoseconds) => 0..9999,
          optional(:server_picoseconds) => 0..9999
        }

  @doc "Encodes a closed DataValue envelope with validated field presence and exact integer metadata."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%{has_value: present, status: status} = value)
      when is_boolean(present) and map_size(value) <= 7 do
    with true <- Enum.all?(Map.keys(value), &(&1 in @keys)),
         {:ok, payload} <- encode_value(present, value),
         {:ok, encoded_status} <- Binary.encode(:uint32, status),
         {:ok, metadata, flags} <- encode_fields(value),
         status_bytes = if(status == 0, do: <<>>, else: encoded_status),
         true <- 1 + byte_size(payload) + byte_size(status_bytes) + byte_size(metadata) <= @limit do
      mask = if(present, do: 1, else: 0) + if(status == 0, do: 0, else: 2) + flags
      {:ok, <<mask, payload::binary, status_bytes::binary, metadata::binary>>}
    else
      {:error, _} = error -> error
      _ -> error(:invalid_value)
    end
  end

  def encode(_), do: error(:invalid_value)

  @doc "Decodes and normalizes one DataValue without classifying its StatusCode as service success."
  @spec decode(term()) :: {:ok, t(), binary()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) do
    prefix_size = min(byte_size(bytes), @limit)

    with {:ok, value, rest} <- decode_prefix(binary_part(bytes, 0, prefix_size)) do
      consumed = prefix_size - byte_size(rest)
      {:ok, value, binary_part(bytes, consumed, byte_size(bytes) - consumed)}
    end
  end

  def decode(_), do: error(:invalid_binary)

  defp encode_value(true, %{value: value}), do: Variant.encode(value)

  defp encode_value(false, value) do
    if Map.has_key?(value, :value), do: error(:invalid_value), else: {:ok, <<>>}
  end

  defp encode_value(_, _), do: error(:invalid_value)

  defp encode_fields(value) do
    Enum.reduce_while(@fields, {:ok, <<>>, 0}, fn {key, flag, type, parent}, {:ok, bytes, mask} ->
      case Map.fetch(value, key) do
        :error ->
          {:cont, {:ok, bytes, mask}}

        {:ok, field} ->
          case encode_field(type, field, parent, value) do
            {:ok, encoded} -> {:cont, {:ok, bytes <> encoded, mask + flag}}
            {:error, _} = error -> {:halt, error}
          end
      end
    end)
  end

  defp encode_field(type, field, nil, _), do: Binary.encode(type, field)

  defp encode_field(:uint16, field, parent, value) when is_integer(field) and field in 0..9999 do
    if Map.has_key?(value, parent), do: Binary.encode(:uint16, field), else: error(:invalid_value)
  end

  defp encode_field(_, _, _, _), do: error(:invalid_value)

  defp decode_prefix(<<mask, bytes::binary>>) when mask <= 63 do
    with {:ok, value, rest} <- decode_value(band(mask, 1) != 0, bytes),
         {:ok, status, rest} <- decode_status(band(mask, 2) != 0, rest),
         do: decode_fields(mask, Map.put(value, :status, status), rest)
  end

  defp decode_prefix(_), do: error(:invalid_binary)

  defp decode_value(false, rest), do: {:ok, %{has_value: false}, rest}

  defp decode_value(true, bytes) do
    with {:ok, value, rest} <- Variant.decode(bytes),
         do: {:ok, %{has_value: true, value: value}, rest}
  end

  defp decode_status(false, rest), do: {:ok, 0, rest}
  defp decode_status(true, bytes), do: Binary.decode(:uint32, bytes)

  defp decode_fields(mask, value, bytes) do
    Enum.reduce_while(@fields, {:ok, value, bytes}, fn {key, flag, type, parent},
                                                       {:ok, value, bytes} ->
      if band(mask, flag) == 0 do
        {:cont, {:ok, value, bytes}}
      else
        case Binary.decode(type, bytes) do
          {:ok, field, rest} -> {:cont, {:ok, retain_field(value, key, field, parent), rest}}
          {:error, _} = error -> {:halt, error}
        end
      end
    end)
  end

  defp retain_field(value, key, field, nil), do: Map.put(value, key, field)

  defp retain_field(value, key, field, parent) do
    if Map.has_key?(value, parent), do: Map.put(value, key, min(field, 9999)), else: value
  end

  defp error(code), do: {:error, Error.new(code)}
end
