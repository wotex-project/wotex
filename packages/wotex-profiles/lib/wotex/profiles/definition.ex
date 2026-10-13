defmodule Wotex.Profiles.Definition do
  @moduledoc """
  A consumer-supplied semantic descriptor, bounded DataSchema and quantity unit.

  Quantity identifiers are opaque input, never a built-in sensor enum. These
  constructors check structure and integrity; installed behavior, model truth
  and physical qualification remain separate obligations.
  """
  alias Wotex.Profiles.{Error, Grammar, Parser, Reader}

  @enforce_keys [:data, :raw_sha256, :semantic_sha256]
  defstruct [:data, :raw_sha256, :semantic_sha256]
  @type t :: %__MODULE__{data: map(), raw_sha256: String.t() | nil, semantic_sha256: String.t()}

  @doc "Parses original descriptor bytes with exact numeric admission and raw identity."
  @spec parse(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(bytes, limits) do
    with {:ok, data, limits} <- Parser.decode(bytes, limits),
         {:ok, value} <- new(data, limits) do
      {:ok, %{value | raw_sha256: Grammar.hash(bytes)}}
    end
  end

  @doc "Revalidates data and recomputes semantic identity; raw identity becomes nil."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value, limits) do
    with {:ok, fields} <- Reader.new(:definition, value, limits),
         do: {:ok, struct(__MODULE__, fields)}
  end

  @doc "Returns a checked descriptor map."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, checked} <- new(value, limits), do: {:ok, checked.data}
  end

  @doc "Returns the exact id, version and recomputed semantic digest."
  @spec reference(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def reference(value, limits) do
    with {:ok, checked} <- new(value, limits) do
      {:ok, Map.put(Map.take(checked.data, ~w(id version)), "sha256", checked.semantic_sha256)}
    end
  end
end
