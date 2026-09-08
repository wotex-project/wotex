defmodule Wotex.BACnet.Value do
  @moduledoc "Explicit BACnet scalar conversion for WoT payloads with native tags retained as metadata."
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.Error

  @types %{
    "bacv:Null" => :null,
    "bacv:Boolean" => :boolean,
    "bacv:Signed" => :signed_integer,
    "bacv:Unsigned" => :unsigned_integer,
    "bacv:Real" => :real,
    "bacv:Double" => :double,
    "bacv:String" => :character_string,
    "bacv:OctetString" => :octet_string
  }

  @doc "Encodes an explicitly declared scalar; absent type never triggers inference."
  @spec encode(term(), term()) :: {:ok, Encoding.t()} | {:error, Error.t()}
  def encode(value, %{"@type" => name}) do
    with {:ok, type} <- Map.fetch(@types, name),
         true <- valid?(type, value),
         {:ok, encoded} <- Encoding.create({type, value}) do
      {:ok, encoded}
    else
      _ -> {:error, Error.new(:invalid_value_type)}
    end
  end

  def encode(%Encoding{} = value, nil), do: {:ok, value}
  def encode(_, _), do: {:error, Error.new(:value_type_required)}

  @doc "Extracts supported native scalars; unknown tags remain intact instead of being discarded."
  @spec result(term()) ::
          {term(), %{optional(:bacnet_type) => term(), optional(:native_value) => true}}
  def result(%Encoding{encoding: :primitive, type: type, value: value} = encoded) do
    if valid?(type, value),
      do: {value, %{bacnet_type: type}},
      else: {encoded, %{bacnet_type: type, native_value: true}}
  end

  def result(value), do: {value, %{}}

  defp valid?(:null, value), do: is_nil(value)
  defp valid?(:boolean, value), do: is_boolean(value)

  defp valid?(:signed_integer, value),
    do: is_integer(value) and value in -2_147_483_648..2_147_483_647

  defp valid?(:unsigned_integer, value), do: is_integer(value) and value in 0..4_294_967_295
  defp valid?(:real, value), do: is_float(value) and abs(value) <= 3.402_823_466_385_288_6e38
  defp valid?(:double, value), do: is_float(value)

  defp valid?(:character_string, value),
    do: is_binary(value) and byte_size(value) <= 4096 and String.valid?(value)

  defp valid?(:octet_string, value), do: is_binary(value) and byte_size(value) <= 4096
  defp valid?(_, _), do: false
end
