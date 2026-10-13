defmodule Wotex.Routines.Profile do
  @moduledoc "Explicit finite bounds for the bounded composition profile. Every selection is required."

  alias Wotex.Routines.Error

  @ceilings %{
    "source_bytes" => 1_048_576,
    "source_depth" => 32,
    "expanded_nodes" => 4096,
    "predicate_nodes" => 4096,
    "invocation_depth" => 16,
    "parallel_width" => 64,
    "effects" => 1024,
    "waits" => 1024,
    "active_definitions" => 1024,
    "active_runs" => 1024,
    "pending_work" => 1024,
    "run_ms" => 604_800_000
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: %{String.t() => pos_integer()}}

  @doc "Validates all explicit selections against the executable profile's closed ceilings."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value) when map_size(value) == 2, do: new(data)

  def new(data) when is_map(data) and not is_struct(data) and map_size(data) == 12 do
    if Enum.sort(Map.keys(data)) == Enum.sort(Map.keys(@ceilings)) and
         Enum.all?(@ceilings, fn {key, ceiling} ->
           is_integer(data[key]) and data[key] > 0 and data[key] <= ceiling
         end) do
      {:ok, %__MODULE__{data: data}}
    else
      Error.refusal(:invalid_profile)
    end
  end

  def new(_), do: Error.refusal(:invalid_profile)

  @doc "Revalidates the profile before projecting its selected limits."
  @spec to_map(term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(profile) do
    with {:ok, profile} <- new(profile), do: {:ok, profile.data}
  end
end
