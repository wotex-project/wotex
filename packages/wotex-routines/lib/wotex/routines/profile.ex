defmodule Wotex.Routines.Profile do
  @moduledoc """
  Selects finite limits for bounded routine compilation and execution.

  `new/1` requires all twelve string-keyed selections as positive integers and
  returns `{:ok, profile}`. Missing, additional, noninteger or over-ceiling
  selections return `{:error, error}` with `Wotex.Routines.Error` code
  `:invalid_profile`. There are no implicit defaults. `to_map/1` revalidates a
  native profile before returning its selections.

  Source bounds are `"source_bytes"` and `"source_depth"`; expansion bounds are
  `"expanded_nodes"`, `"predicate_nodes"`, `"invocation_depth"` and
  `"parallel_width"`. The remaining selections are `"effects"`, `"waits"`,
  `"active_definitions"`, `"active_runs"`, `"pending_work"` and `"run_ms"`.
  Run duration is measured in elapsed milliseconds. Compilation counts all
  possible expanded paths, rather than only the branch later selected.

  The installed ceilings are 1 MiB of source, depth 32, 4096 expanded/predicate
  nodes each, invocation depth 16, parallel width 64, 1024 for each effect, wait
  and activity count, and seven days per run. Consumers may select lower bounds.
  Separate `Wotex.Routines.Limits` still constrain JSON shape, bytes and integer
  magnitude; neither set of limits widens the other.

  These selections bound the executable representation. They do not reserve
  host capacity, establish complete active membership or enforce a consumer's
  durable admission and pending-work accounting.
  """

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
