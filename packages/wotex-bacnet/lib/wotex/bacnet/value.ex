defmodule Wotex.BACnet.Value do
  @moduledoc """
  Converts supported WoT payloads to and from typed BACnet scalar values.

  `encode/2` requires an explicit BACnet type declaration or an already encoded
  BACstack value. It validates the value against the selected scalar type and
  returns the native encoding consumed by the client adapter. `result/1`
  separates a decoded Property value from its BACnet type metadata so Runtime
  can retain protocol evidence without changing the value's WoT meaning.

  ## Conversion boundary

  Conversion is deterministic and performs no I/O. Native tags are preserved;
  the module does not infer a BACnet type from an arbitrary Elixir value.
  Encoding and validation reject unsupported types, malformed native encodings,
  and out-of-range values with `Wotex.BACnet.Error`. `result/1` is a projection,
  not a validator; the Runtime adapter validates native values before calling it. The conversion result is
  protocol data, not a unit conversion, authorization decision, or claim about
  canonical Property state.
  """
  alias BACnet.Protocol.ApplicationTags
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{CharacterString, Error, ValueBoundary}

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

  @doc "Validates an explicit Form type selector without inferring or converting a value."
  @spec validate_type(term()) :: :ok | {:error, Error.t()}
  def validate_type(%{"@type" => name}) when is_map_key(@types, name), do: :ok
  def validate_type(_), do: {:error, Error.new(:invalid_value_type)}

  @doc "Encodes an explicitly declared scalar; absent type never triggers inference."
  @spec encode(term(), term()) :: {:ok, Encoding.t()} | {:error, Error.t()}
  def encode(value, %{"@type" => name}) do
    with {:ok, type} <- Map.fetch(@types, name),
         true <- valid?(type, value),
         {:ok, encoded} <- Encoding.create({type, typed_value(type, value)}) do
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
    with :ok <- ValueBoundary.validate(value) do
      if character_strings?(value),
        do: validate_encodings(value),
        else: {:error, Error.new(:invalid_value)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_value)}
  end

  @doc "Validates native writes, rejecting character sets the SDK cannot encode losslessly."
  @spec validate_write(term()) :: :ok | {:error, Error.t()}
  def validate_write(value) do
    with :ok <- validate_native(value) do
      if characters?(value, :write), do: :ok, else: {:error, Error.new(:unsupported_character_set)}
    end
  end

  @doc false
  @spec validate_read(term()) :: :ok | {:error, Error.t()}
  def validate_read(value) do
    with :ok <- validate_native(value) do
      if characters?(value, :read), do: :ok, else: {:error, Error.new(:character_set_unavailable)}
    end
  end

  @doc false
  @spec to_tag(Encoding.t()) :: tuple()
  def to_tag(value), do: transform(Encoding.to_encoding!(value), :write)

  defp typed_value(:character_string, value), do: %CharacterString{character_set: 0, bytes: value}
  defp typed_value(_, value), do: value

  # ValueBoundary counts only a CharacterString's bytes, so every struct, in any
  # position, must be exactly the value `CharacterString.new/2` builds.
  defp character_strings?(%CharacterString{} = string),
    do:
      CharacterString.new(Map.get(string, :character_set), Map.get(string, :bytes)) ==
        {:ok, string}

  defp character_strings?(value) when is_list(value), do: Enum.all?(value, &character_strings?/1)
  defp character_strings?(value) when is_tuple(value), do: character_strings?(Tuple.to_list(value))
  defp character_strings?(value) when is_map(value), do: character_strings?(Map.values(value))
  defp character_strings?(_), do: true

  defp characters?(%Encoding{type: :character_string, value: value}, mode),
    do: characters?({:character_string, value}, mode)

  defp characters?({:character_string, %CharacterString{character_set: set}}, mode),
    do: mode == :read or set == 0

  defp characters?({:character_string, _}, mode), do: mode == :write
  defp characters?(value, mode) when is_list(value), do: Enum.all?(value, &characters?(&1, mode))
  defp characters?(value, mode) when is_tuple(value), do: characters?(Tuple.to_list(value), mode)
  defp characters?(value, mode) when is_map(value), do: characters?(Map.values(value), mode)
  defp characters?(_, _), do: true

  defp transform({:character_string, %CharacterString{character_set: set, bytes: bytes}}, mode) do
    {:ok, _} = CharacterString.new(set, bytes)
    {:character_string, if(mode == :validate and set != 0, do: "", else: bytes)}
  end

  defp transform(value, mode) when is_list(value), do: Enum.map(value, &transform(&1, mode))

  defp transform(value, mode) when is_tuple(value),
    do:
      value
      |> Tuple.to_list()
      |> transform(mode)
      |> List.to_tuple()

  defp transform(value, _), do: value

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
         {:ok, bytes} <- ApplicationTags.encode(transform(tag, :validate)),
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

  defp native_scalar?(%Encoding{type: :character_string, value: %CharacterString{} = value}),
    do: match?({:ok, _}, CharacterString.new(value.character_set, value.bytes))

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
          {term(),
           %{
             optional(:bacnet_type) => term(),
             optional(:native_value) => true,
             optional(:character_set) => 0..255
           }}
  def result(%Encoding{
        encoding: :primitive,
        type: :character_string,
        value: %CharacterString{character_set: 0, bytes: bytes}
      }),
      do: {bytes, %{bacnet_type: :character_string, character_set: 0}}

  def result(
        %Encoding{
          encoding: :primitive,
          type: :character_string,
          value: %CharacterString{character_set: set}
        } = encoded
      ),
      do: {encoded, %{bacnet_type: :character_string, character_set: set, native_value: true}}

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
