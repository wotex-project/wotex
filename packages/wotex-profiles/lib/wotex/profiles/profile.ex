defmodule Wotex.Profiles.Profile do
  @moduledoc """
  Bounded external profile data with separate raw and semantic identities.

  Parsing retains the original-byte SHA-256. Construction from a map or native
  value rechecks data and recomputes semantic identity, setting raw identity to
  nil. An annotation, digest or fingerprint establishes no device qualification.
  """
  alias Wotex.Profiles.{Error, Grammar, Parser, Reader}

  @enforce_keys [:data, :raw_sha256, :semantic_sha256]
  defstruct [:data, :raw_sha256, :semantic_sha256]
  @type t :: %__MODULE__{data: map(), raw_sha256: String.t() | nil, semantic_sha256: String.t()}

  @doc "Parses bounded original bytes, refusing duplicate members and numeric rounding."
  @spec parse(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(bytes, limits) do
    with {:ok, data, limits} <- Parser.decode(bytes, limits),
         {:ok, value} <- new(data, limits) do
      {:ok, %{value | raw_sha256: Grammar.hash(bytes)}}
    end
  end

  @doc "Revalidates a closed map or native Profile; native hashes are never trusted."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(value, limits) do
    with {:ok, fields} <- Reader.new(:profile, value, limits), do: {:ok, struct(__MODULE__, fields)}
  end

  @doc "Returns the checked external representation."
  @spec to_map(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, limits) do
    with {:ok, checked} <- new(value, limits), do: {:ok, checked.data}
  end

  @doc "Returns an exact reference to recomputed semantic identity, excluding annotations."
  @spec reference(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def reference(value, limits) do
    with {:ok, checked} <- new(value, limits) do
      {:ok, Map.put(Map.take(checked.data, ~w(id version)), "sha256", checked.semantic_sha256)}
    end
  end
end
