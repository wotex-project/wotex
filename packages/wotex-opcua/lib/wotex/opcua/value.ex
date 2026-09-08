defmodule Wotex.OPCUA.Value do
  @moduledoc "Explicit Variant conversion between WoT values and the secure client profile."
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

  @doc "Wraps a value in an explicitly named and validated scalar Variant."
  @spec encode(term(), term()) :: {:ok, map()} | {:error, Error.t()}
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
      with {:ok, value} <- payload(value), do: {:ok, value, %{opcua_type: type, status: status}}
    else
      {:error, Error.new(:bad_status, nil, %{status: status})}
    end
  end

  def result(%{"status" => _}), do: {:error, Error.new(:invalid_result)}
  def result(value), do: {:ok, value, %{}}

  defp payload(%{"type" => "ByteString", "base64" => text}) when is_binary(text) do
    case Base.decode64(text) do
      {:ok, bytes} -> {:ok, bytes}
      _ -> {:error, Error.new(:invalid_bytestring)}
    end
  end

  defp payload(value), do: {:ok, value}
end
