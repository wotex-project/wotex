defmodule Wotex.OPCUA.Value do
  @moduledoc """
  Converts explicitly typed OPC UA Variants at the WoT boundary.

  `encode/2` accepts a value with a supported OPC UA built-in type name. With
  a nil type argument, the value must be a map containing `type` and `value`.
  An array Write takes an explicit typed envelope with `array: true`, a flat
  element list or nil, and optional dimensions, for any of the scalar types
  below. The value is validated through
  `Wotex.OPCUA.Binary`; byte strings are represented as Base64 for the JSON
  bridge. The module never infers a Variant type from an arbitrary Elixir value.

  `result/1` accepts a native value with a 32-bit StatusCode and type name. It
  rejects bad StatusCodes, preserves non-bad status and type as protocol
  metadata, and decodes scalar or bounded flat-array ByteString envelopes. It does not validate
  other returned types against their payloads; values without a StatusCode envelope
  pass through with empty metadata. Invalid status envelopes and malformed
  Base64 return `Wotex.OPCUA.Error`. `native_result/1` projects one native typed
  DataValue map, from a persistent Read or an observation: Bad status and an
  absent value fail, and a scalar or array Variant of a Null, Boolean, integer,
  Float, Double, String, DateTime, Guid, ByteString, NodeId or StatusCode type
  becomes the payload only after `Wotex.OPCUA.Binary.encode_variant/1` accepts
  every element against its declared type, the element and byte limits and any
  dimensions. ByteString elements become raw binaries and arrays stay flat.
  Metadata keeps the type, status, `opcua_dimensions` of a multidimensional
  array and any timestamps or picosecond fractions. Other types, such as
  QualifiedName or ExtensionObject, an element that contradicts its declared
  type and dimensions on a scalar fail with `:unsupported_type`; exceeded
  limits fail with `:response_limit`. Conversion
  does not validate an application DataSchema, perform unit conversion, or
  establish Property state.

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
    with {:ok, _} <- Map.fetch(@types, name),
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

  @timestamps %{
    "source_timestamp" => :source_timestamp,
    "server_timestamp" => :server_timestamp,
    "source_picoseconds" => :source_picoseconds,
    "server_picoseconds" => :server_picoseconds
  }

  @doc "Projects one native typed DataValue map onto a Runtime payload and metadata."
  @spec native_result(term()) :: {:ok, term(), map()} | {:error, Error.t()}
  def native_result(%{"status" => status, "has_value" => present} = data_value)
      when is_integer(status) and status in 0..4_294_967_295 and is_boolean(present) do
    cond do
      band(status, 0x80000000) != 0 -> {:error, Error.new(:bad_status, nil, %{status: status})}
      not present -> {:error, Error.new(:missing_value, nil, %{status: status})}
      true -> native_variant(data_value["value"], status, data_value)
    end
  end

  def native_result(_), do: {:error, Error.new(:invalid_result)}

  @native_types ~w(Null Boolean SByte Byte Int16 UInt16 Int32 UInt32 Int64 UInt64 Float Double
                   String DateTime Guid ByteString NodeId StatusCode)

  defp native_variant(%{"type" => type, "array" => array} = variant, status, data_value)
       when is_binary(type) and is_boolean(array) and is_map_key(variant, "value") do
    with :ok <- native_type(type),
         {:ok, dimensions} <- native_dimensions(variant),
         {:ok, payload} <- native_payload(type, array, variant["value"]),
         :ok <- validate_variant(type, array, payload, dimensions) do
      base = %{opcua_type: type, status: status}
      base = if dimensions, do: Map.put(base, :opcua_dimensions, dimensions), else: base

      metadata =
        Enum.reduce(@timestamps, base, fn {key, atom}, metadata ->
          if Map.has_key?(data_value, key),
            do: Map.put(metadata, atom, data_value[key]),
            else: metadata
        end)

      {:ok, payload, metadata}
    end
  end

  defp native_variant(_, _, _), do: {:error, Error.new(:unsupported_type)}

  defp native_type(type) when type in @native_types, do: :ok
  defp native_type(_), do: {:error, Error.new(:unsupported_type)}

  defp native_dimensions(variant) do
    case Map.keys(variant) -- ["type", "array", "value"] do
      [] -> {:ok, nil}
      ["dimensions"] -> {:ok, variant["dimensions"]}
      _ -> {:error, Error.new(:unsupported_type)}
    end
  end

  defp native_payload(_, true, nil), do: {:ok, nil}

  defp native_payload(type, true, values) when is_list(values) do
    elements =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, elements} ->
        case native_element(value) do
          {:ok, element} -> {:cont, {:ok, [element | elements]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, elements} <- elements, do: payload(type, Enum.reverse(elements))
  end

  defp native_payload(type, false, value) do
    with {:ok, element} <- native_element(value), do: payload(type, element)
  end

  defp native_payload(_, _, _), do: {:error, Error.new(:unsupported_type)}

  # The bridge sends scalars as JSON values and byte strings as a closed
  # base64 envelope; any other element shape is outside the projection.
  defp native_element(%{"type" => "bytes", "base64" => text} = envelope)
       when map_size(envelope) == 2 and is_binary(text),
       do: {:ok, envelope}

  defp native_element(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp native_element(_), do: {:error, Error.new(:unsupported_type)}

  # The pure codec checks each element against its type's width, the 64 KiB
  # element and 1 MiB Variant budgets and the dimensions' element count.
  defp validate_variant(type, array, payload, dimensions) do
    variant = %{type: type, array: array, value: payload}
    variant = if dimensions, do: Map.put(variant, :dimensions, dimensions), else: variant

    case Binary.encode_variant(variant) do
      {:ok, _} -> :ok
      {:error, %Error{code: :response_limit}} = error -> error
      {:error, _} -> {:error, Error.new(:unsupported_type)}
    end
  end

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

  defp payload(_, values) when is_list(values) and length(values) > 1024,
    do: {:error, Error.new(:response_limit)}

  defp payload(_, value), do: {:ok, value}

  defp byte_payload(nil), do: {:ok, nil}

  defp byte_payload(%{"type" => kind, "base64" => text} = envelope)
       when kind in ["ByteString", "bytes"] and map_size(envelope) == 2 and is_binary(text) do
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
