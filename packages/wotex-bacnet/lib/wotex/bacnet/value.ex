defmodule Wotex.BACnet.Value do
  @moduledoc "Explicit BACnet scalar conversion for WoT payloads with native tags retained as metadata."
  alias BACnet.Protocol.ApplicationTags
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Error, ValueBoundary}

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

  def encode(%Encoding{} = value, nil) do
    with :ok <- validate_native(value), do: {:ok, value}
  end

  def encode(_, _), do: {:error, Error.new(:value_type_required)}

  @doc "Validates bounded native tags without invoking user-provided encoders."
  @spec validate_native(term()) :: :ok | {:error, Error.t()}
  def validate_native(value) do
    with :ok <- ValueBoundary.validate(value), do: validate_encodings(value)
  rescue
    _ -> {:error, Error.new(:invalid_value)}
  end

  defp validate_encodings(values) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validate_encodings(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_encodings(%Encoding{} = value) do
    with true <- valid_extras?(value),
         true <- native_scalar?(value),
         {:ok, tag} <- Encoding.to_encoding(value),
         {:ok, bytes} <- ApplicationTags.encode(tag),
         true <- byte_size(bytes) <= 65_536 do
      :ok
    else
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  defp validate_encodings(_), do: {:error, Error.new(:invalid_value)}

  defp valid_extras?(%Encoding{encoding: :primitive, extras: []}), do: true

  defp valid_extras?(%Encoding{encoding: encoding, extras: [tag_number: tag]})
       when encoding in [:tagged, :constructed] and is_integer(tag) and tag in 0..255,
       do: true

  defp valid_extras?(_), do: false

  defp native_scalar?(%Encoding{type: type, value: value})
       when type in [
              :null,
              :boolean,
              :signed_integer,
              :unsigned_integer,
              :real,
              :double,
              :character_string,
              :octet_string
            ],
       do: valid?(type, value)

  defp native_scalar?(_), do: true

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
    do: is_integer(value) and value in -9_223_372_036_854_775_808..9_223_372_036_854_775_807

  defp valid?(:unsigned_integer, value),
    do: is_integer(value) and value in 0..18_446_744_073_709_551_615

  defp valid?(:real, value), do: is_float(value) and abs(value) <= 3.402_823_466_385_288_6e38
  defp valid?(:double, value), do: is_float(value)

  defp valid?(:character_string, value),
    do: is_binary(value) and byte_size(value) <= 65_536 and String.valid?(value)

  defp valid?(:octet_string, value), do: is_binary(value) and byte_size(value) <= 65_536
  defp valid?(_, _), do: false
end
