defmodule Wotex.Lab.Runner.Budgets do
  @moduledoc """
  Run budgets with explicit defaults and profile ceilings.

  Defaults are 60 s wall time, 100 steps, 128 children per role, 1 MiB per
  ingress value, 1,024 queued deliveries, 100 reconnect attempts and 5 s
  cleanup. Every value is a positive integer a host may override up to the
  ceiling; preflight refuses anything else. Wall and cleanup budgets are
  enforced with monotonic deadlines; observation time supplied by a fixture
  is a separate coordinate the runner never mixes with them.

  `defaults/0` and `ceilings/0` expose the contract as inert maps, while `new/1`
  merges and validates consumer overrides. This module allocates no resource.
  The runner applies the wall, step, child, ingress, observer-delivery and
  cleanup limits at the boundaries it governs; it has no connection of its own,
  so `reconnect_attempts` reaches components through their step context for
  the adapters that reconnect.
  """

  alias Wotex.Lab.Error

  @defaults %{
    wall_ms: 60_000,
    max_steps: 100,
    children_per_role: 128,
    ingress_bytes: 1_048_576,
    queued_deliveries: 1_024,
    reconnect_attempts: 100,
    cleanup_ms: 5_000
  }

  @ceilings %{
    wall_ms: 600_000,
    max_steps: 100_000,
    children_per_role: 10_000,
    ingress_bytes: 16_777_216,
    queued_deliveries: 65_536,
    reconnect_attempts: 10_000,
    cleanup_ms: 60_000
  }

  @type t :: %{
          wall_ms: pos_integer(),
          max_steps: pos_integer(),
          children_per_role: pos_integer(),
          ingress_bytes: pos_integer(),
          queued_deliveries: pos_integer(),
          reconnect_attempts: pos_integer(),
          cleanup_ms: pos_integer()
        }

  @doc "The default budgets."
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc "The hard ceilings."
  @spec ceilings() :: t()
  def ceilings, do: @ceilings

  @doc "Merges overrides into the defaults and enforces positivity and ceilings."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(overrides) when is_list(overrides), do: new(Map.new(overrides))

  def new(overrides) when is_map(overrides) do
    case Map.keys(overrides) -- Map.keys(@defaults) do
      [] -> validate(Map.merge(@defaults, overrides))
      unknown -> unknown_budget(unknown)
    end
  end

  def new(_), do: {:error, Error.new(:invalid_budget, :preflight, "budgets must be a map")}

  defp validate(budgets) do
    case Enum.find_value(budgets, &invalid_value/1) do
      nil -> {:ok, budgets}
      error -> {:error, error}
    end
  end

  defp invalid_value({key, value}) when not is_integer(value) or value <= 0,
    do:
      Error.new(:invalid_budget, :preflight, "budget must be a positive integer",
        details: %{budget: key}
      )

  defp invalid_value({key, value}) do
    ceiling = Map.fetch!(@ceilings, key)

    if value > ceiling,
      do:
        Error.new(:budget_ceiling, :preflight, "budget exceeds the profile ceiling",
          details: %{budget: key, ceiling: ceiling}
        )
  end

  defp unknown_budget(keys),
    do:
      {:error,
       Error.new(:invalid_budget, :preflight, "unknown budget keys", details: %{keys: keys})}
end
