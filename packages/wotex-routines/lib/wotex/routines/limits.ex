defmodule Wotex.Routines.Limits do
  @moduledoc "Explicit finite limits. Every member is required; no runtime defaults are inferred."

  alias Wotex.Routines.Error

  @ceilings %{
    "max_bytes" => 1_048_576,
    "max_depth" => 32,
    "max_nodes" => 100_000,
    "max_string_bytes" => 65_536,
    "max_collection_size" => 1024,
    "max_integer" => 9_223_372_036_854_775_807
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: %{String.t() => pos_integer()}}

  @doc "Validates every selected limit against the closed profile ceiling."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value) when map_size(value) == 2, do: new(data)

  def new(data) when is_map(data) and not is_struct(data) and map_size(data) == 6 do
    if Enum.sort(Map.keys(data)) == Enum.sort(Map.keys(@ceilings)) and
         Enum.all?(@ceilings, fn {key, ceiling} ->
           is_integer(data[key]) and data[key] > 0 and data[key] <= ceiling
         end) do
      {:ok, %__MODULE__{data: data}}
    else
      Error.refusal(:invalid_limits)
    end
  end

  def new(_), do: Error.refusal(:invalid_limits)

  @doc "Revalidates the selected limits and returns their data."
  @spec to_map(term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value) do
    with {:ok, value} <- new(value), do: {:ok, value.data}
  end
end
