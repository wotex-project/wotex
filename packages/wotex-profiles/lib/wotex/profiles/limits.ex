defmodule Wotex.Profiles.Limits do
  @moduledoc "Complete caller-selected limits for one bounded profile closure; no defaults or catalogue scan."
  alias Wotex.Profiles.Error

  @ceilings %{
    "max_bytes" => 1_048_576,
    "max_depth" => 16,
    "max_nodes" => 100_000,
    "max_channels" => 1024,
    "max_definitions" => 1024,
    "max_bindings" => 64,
    "max_dependencies" => 1024,
    "max_numeric_digits" => 128
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: %{String.t() => pos_integer()}}

  @doc "Checks every required selection and the exact native shape against the engineering ceilings."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{data: data} = value) when map_size(value) == 2, do: new(data)

  def new(data) when is_map(data) and not is_struct(data) and map_size(data) == 8 do
    if Enum.sort(Map.keys(data)) == Enum.sort(Map.keys(@ceilings)) and
         Enum.all?(@ceilings, fn {key, ceiling} ->
           is_integer(data[key]) and data[key] in 1..ceiling
         end), do: {:ok, %__MODULE__{data: data}}, else: Error.refusal(:invalid_input, "/limits")
  end

  def new(_), do: Error.refusal(:invalid_input, "/limits")

  @doc "Revalidates before returning the complete selected limits."
  @spec to_map(term()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value) do
    with {:ok, checked} <- new(value), do: {:ok, checked.data}
  end
end
