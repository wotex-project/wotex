defmodule Wotex.OPCUA.Value do
  @moduledoc """
  Converts explicitly typed OPC UA Variants at the WoT boundary.

  `encode/2` accepts a value with a supported OPC UA built-in type name. With
  a nil type argument, the value must be a map containing `type` and `value`.
  The current flat-array Write path accepts an explicit typed ByteString
  envelope with `array: true` and optional dimensions.
  The value is validated through
  `Wotex.OPCUA.Binary`; byte strings are represented as Base64 for the JSON
  bridge. The module never infers a Variant type from an arbitrary Elixir value.

  `result/1` accepts a native value with a 32-bit StatusCode and type name. It
  rejects bad StatusCodes, preserves non-bad status and type as protocol
  metadata, and decodes scalar or bounded flat-array ByteString envelopes. It does not validate
  other returned types against their payloads; values without a StatusCode envelope
  pass through with empty metadata. Invalid status envelopes and malformed
  Base64 return `Wotex.OPCUA.Error`. Full typed result validation, general arrays and
  DataValue metadata remain target work. Conversion does not validate an
  application DataSchema, perform unit conversion, or establish Property state.

  ## Examples

      iex> Wotex.OPCUA.Value.encode(<<0, 255>>, "ByteString")
      {:ok, %{type: "ByteString", value: "AP8="}}
      iex> {:error, error} = Wotex.OPCUA.Value.encode(256, "Byte")
      iex> error.code
      :variant_type_required

  """
  import Bitwise
  alias Wotex.OPCUA.{Binary, Error}

  @types %{
    "Boolean" => :boolean,
    "SByte" => :sbyte,
    "Byte" => :byte,
    "Int16" => :int16,
    "UInt16" => :uint16,
    "Int32" => :int32,
    "UInt32" => :uint32,
    "Int64" => :int64,
    "UInt64" => :uint64,
    "Float" => :float,
    "Double" => :double,
    "String" => :string,
    "ByteString" => :bytestring
  }

  @doc "Wraps a value in an explicitly named and validated Variant."
  @spec encode(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def encode(%{type: name, array: true, value: values} = typed, nil) do
    with true <- name == "ByteString",
         {:ok, _} <- Binary.encode_variant(typed) do
      payload =
        if name == "ByteString" and is_list(values),
          do: Enum.map(values, &encode_byte/1),
          else: values

      {:ok, %{typed | value: payload}}
    else
      _ -> {:error, Error.new(:variant_type_required)}
    end
  end

  def encode(%{"type" => name, "array" => true, "value" => values} = typed, nil) do
    if Enum.all?(Map.keys(typed), &(&1 in ~w(type array value dimensions))) do
      array = %{type: name, array: true, value: values}

      array =
        if Map.has_key?(typed, "dimensions"),
          do: Map.put(array, :dimensions, typed["dimensions"]),
          else: array

      encode(array, nil)
    else
      {:error, Error.new(:variant_type_required)}
    end
  end

  def encode(%{type: name, value: value}, nil), do: encode(value, name)
  def encode(%{"type" => name, "value" => value}, nil), do: encode(value, name)

  def encode(value, name) do
    with {:ok, type} <- Map.fetch(@types, name), {:ok, _} <- Binary.encode(type, value) do
      payload = if type == :bytestring and is_binary(value), do: Base.encode64(value), else: value
      {:ok, %{type: name, value: payload}}
    else
      _ -> {:error, Error.new(:variant_type_required)}
    end
  end

  @doc "Separates a successful native value from status/type metadata, retaining uncertain status."
  @spec result(term()) :: {:ok, term(), map()} | {:error, Error.t()}
  def result(%{"status" => status, "value" => value, "type" => type})
      when is_integer(status) and status in 0..4_294_967_295 and is_binary(type) do
    if band(status, 0x80000000) == 0 do
      with {:ok, value} <- payload(type, value),
           do: {:ok, value, %{opcua_type: type, status: status}}
    else
      {:error, Error.new(:bad_status, nil, %{status: status})}
    end
  end

  def result(%{"status" => _}), do: {:error, Error.new(:invalid_result)}
  def result(value), do: {:ok, value, %{}}

  defp payload("ByteString", values) when is_list(values) and length(values) <= 1024 do
    result =
      Enum.reduce_while(values, {:ok, [], 0}, fn item, {:ok, decoded, size} ->
        case byte_payload(item) do
          {:ok, bytes} ->
            next_size = size + byte_length(bytes)

            if next_size <= 1_048_576,
              do: {:cont, {:ok, [bytes | decoded], next_size}},
              else: {:halt, {:error, Error.new(:response_limit)}}

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, decoded, _} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp payload("ByteString", values) when is_list(values),
    do: {:error, Error.new(:response_limit)}

  defp payload("ByteString", value), do: byte_payload(value)
  defp payload(_, value), do: {:ok, value}

  defp byte_payload(nil), do: {:ok, nil}

  defp byte_payload(%{"type" => "ByteString", "base64" => text} = envelope)
       when map_size(envelope) == 2 and is_binary(text) do
    if byte_size(text) > 87_384 do
      {:error, Error.new(:response_limit)}
    else
      case Base.decode64(text) do
        {:ok, bytes} when byte_size(bytes) <= 65_536 -> {:ok, bytes}
        {:ok, _} -> {:error, Error.new(:response_limit)}
        :error -> {:error, Error.new(:invalid_bytestring)}
      end
    end
  end

  defp byte_payload(_), do: {:error, Error.new(:invalid_bytestring)}

  defp encode_byte(nil), do: nil
  defp encode_byte(bytes), do: Base.encode64(bytes)

  defp byte_length(nil), do: 0
  defp byte_length(bytes), do: byte_size(bytes)
end
