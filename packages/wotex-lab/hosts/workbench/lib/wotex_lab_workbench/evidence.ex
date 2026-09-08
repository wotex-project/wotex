defmodule WotexLabWorkbench.Evidence do
  @moduledoc """
  Builds `Wotex.Lab.Evidence.Record` values for workbench runs.

  A record binds the run to the compile-time provenance (Lab tree digest,
  lock digest, dependency archives, fixtures), its seed, toolchain, budgets,
  inputs, assertion outcomes, outcomes, durations and cleanup. The record's
  canonical digest is what the Evidence view and the exported report show.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.{Digest, Record}
  alias WotexLabWorkbench.{Provenance, Run}

  @doc "Builds and digests the record for a run."
  @spec record(Run.t(), map()) :: {:ok, Record.t(), String.t()} | {:error, Error.t()}
  def record(%Run{} = run, extras) do
    with {:ok, record} <-
           Record.new(%{
             scenario_id: run.experiment,
             revision: WotexLabWorkbench.version(),
             attempt: run.attempt,
             source_tree_digest: Provenance.source_tree_digest(),
             lock_digest: Provenance.lock_digest(),
             dependencies: Provenance.dependencies(),
             fixtures: Provenance.fixtures(),
             seed: Map.get(extras, :seed, 0),
             toolchain: Digest.toolchain(Nx.BinaryBackend),
             budgets: Map.get(extras, :budgets, %{}),
             inputs: Map.get(extras, :inputs, []),
             assertions: Enum.map(run.assertions, &Map.take(&1, [:id, :status])),
             outcomes:
               extras
               |> Map.get(:outcomes, %{})
               |> Enum.reject(fn {_k, v} -> is_nil(v) end)
               |> Map.new(),
             durations: %{run_ms: run.duration_ms},
             cleanup: run.cleanup
           }),
         {:ok, digest} <- Record.digest(record) do
      {:ok, record, digest}
    end
  end
end
