defmodule Wotex.Thread.JoinerIdentity do
  @moduledoc "An exact EUI-64 or bounded discerner identifying a permitted Thread joiner."

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
