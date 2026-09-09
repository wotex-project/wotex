defmodule Wotex.Thread.JoinerIdentity do
  @moduledoc """
  Identifies one Thread joiner by an EUI-64 or a bounded discerner.

  `new/1` accepts an exact eight-byte `:eui64` value, or a `:discerner`
  map with `:length` in 1..64 and a nonnegative integer `:value` smaller
  than two raised to that length. Unknown fields, wildcards, hexadecimal
  text in place of EUI-64 bytes and out-of-range values return
  `:invalid_joiner_identity` errors.

  `Wotex.Thread.JoinerAdmission` uses this value to select a commissioner
  admission. `Wotex.Thread.JoinerConfig` accepts only the discerner variant.
  Construction performs no discovery or admission; a well-formed identifier
  does not establish that a peer exists or possesses the required credential.

  ## Examples

      iex> {:ok, identity} = Wotex.Thread.JoinerIdentity.new(%{discerner: %{length: 12, value: 42}})
      iex> {identity.kind, identity.value, identity.length}
      {:discerner, 42, 12}
  """

  alias Wotex.Thread.Error

  @enforce_keys [:kind, :value, :length]
  defstruct [:kind, :value, :length]

  @type t :: %__MODULE__{
          kind: :eui64 | :discerner,
          value: binary() | non_neg_integer(),
          length: nil | 1..64
        }

  @doc "Constructs one exact identity; wildcard and unknown fields are rejected."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{eui64: <<_::64>> = value} = input) when map_size(input) == 1,
    do: {:ok, %__MODULE__{kind: :eui64, value: value, length: nil}}

  def new(%{discerner: %{length: length, value: value} = discerner} = input)
      when map_size(input) == 1 and map_size(discerner) == 2 and is_integer(length) and
             length in 1..64 and is_integer(value) and value >= 0 do
    if value < Bitwise.bsl(1, length),
      do: {:ok, %__MODULE__{kind: :discerner, value: value, length: length}},
      else: {:error, Error.new(:invalid_joiner_identity)}
  end

  def new(_), do: {:error, Error.new(:invalid_joiner_identity)}

  @doc false
  @spec parameters(term()) :: {:ok, map()} | {:error, Error.t()}
  def parameters(%__MODULE__{} = identity), do: encode(identity)

  def parameters(input) do
    with {:ok, identity} <- new(input), do: encode(identity)
  end

  @doc false
  @spec decode(term()) :: {:ok, map()} | {:error, Error.t()}
  def decode(%{"type" => "eui64", "value" => value} = wire)
      when map_size(wire) == 2 and is_binary(value) and byte_size(value) == 16 do
    case Base.decode16(value) do
      {:ok, <<_::64>> = bytes} -> {:ok, %{eui64: bytes}}
      _ -> {:error, Error.new(:invalid_joiner_identity)}
    end
  end

  def decode(%{"type" => "discerner", "length" => length, "value" => value} = wire)
      when map_size(wire) == 3 and is_binary(value) and byte_size(value) in 1..20 do
    with {integer, ""} <- Integer.parse(value),
         true <- Integer.to_string(integer) == value,
         {:ok, _} <- new(%{discerner: %{length: length, value: integer}}) do
      {:ok, %{discerner: %{length: length, value: integer}}}
    else
      _ -> {:error, Error.new(:invalid_joiner_identity)}
    end
  end

  def decode(_), do: {:error, Error.new(:invalid_joiner_identity)}

  @doc false
  @spec encode(term()) :: {:ok, map()} | {:error, Error.t()}
  def encode(%__MODULE__{kind: :eui64, value: value, length: nil} = identity)
      when map_size(identity) == 4 do
    with {:ok, _} <- new(%{eui64: value}),
         do: {:ok, %{type: "eui64", value: Base.encode16(value)}}
  end

  def encode(%__MODULE__{kind: :discerner, value: value, length: length} = identity)
      when map_size(identity) == 4 do
    with {:ok, _} <- new(%{discerner: %{length: length, value: value}}),
         do: {:ok, %{type: "discerner", length: length, value: Integer.to_string(value)}}
  end

  def encode(_), do: {:error, Error.new(:invalid_joiner_identity)}
end
