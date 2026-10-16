defmodule Wotex.Routines.Limits do
  @moduledoc """
  Caller-selected bounds for routine values and their complete JSON projections.

  Call `Wotex.Routines.Limits.new/1` with a plain string-keyed map containing
  exactly six positive integer members: `"max_bytes"`, `"max_depth"`,
  `"max_nodes"`, `"max_string_bytes"`, `"max_collection_size"` and
  `"max_integer"`. Each selection must fit its supported ceiling; there are no
  inferred defaults. Success returns `{:ok, limits}` with a
  `t:Wotex.Routines.Limits.t/0`; invalid selections return `{:error, error}`
  with a `Wotex.Routines.Error` carrying `:invalid_limits`.

  The supported inclusive ceilings are:

  | Member | Ceiling |
  | --- | ---: |
  | `"max_bytes"` | 67,108,864 |
  | `"max_depth"` | 64 |
  | `"max_nodes"` | 2,000,000 |
  | `"max_string_bytes"` | 65,536 |
  | `"max_collection_size"` | 8,192 |
  | `"max_integer"` | 9,223,372,036,854,775,807 |

  Pass the accepted value explicitly to constructors and projections.
  `Wotex.Routines.Limits.to_map/1` revalidates it and returns the exact selected
  map as `{:ok, data}`. Both functions also accept and revalidate an existing
  Limits value. Selecting a larger allowed ceiling does not enlarge an
  existing value's bounds. Full nested inputs and outputs, including repeated
  embedded copies, count against the supplied JSON limits. Integer magnitude
  is bounded by the selected `"max_integer"`.

  `Wotex.Routines.Profile` independently bounds expanded program structure,
  runs and pending work. The consumer chooses both the member and aggregate
  envelopes before use; the maximum of each individual member is not a promise
  that their complete aggregate fits. Limits allocate no resource, start no
  process and introduce no retry or truncation policy.
  """

  alias Wotex.Routines.Error

  @ceilings %{
    "max_bytes" => 67_108_864,
    "max_depth" => 64,
    "max_nodes" => 2_000_000,
    "max_string_bytes" => 65_536,
    "max_collection_size" => 8192,
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
