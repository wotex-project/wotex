defmodule WotexLabWorkbench.Report do
  @moduledoc """
  A bounded JSON evidence report for one session.

  The report carries the host identity and source mode, the compile-time
  provenance, every run record with its digest, the frozen datasets, the
  formal results in their evidence form and the policy records. Encoding is
  capped at one mebibyte: runs are dropped from the oldest end until the
  report fits, and `truncated` says so. Nothing here is an authorization.
  """

  alias Wotex.Lab.Evidence.Record
  alias Wotex.Lab.Formal.Result
  alias WotexLabWorkbench.{Provenance, Run, Runs}

  @max_bytes 1_048_576

  @doc "Builds the report map from a room snapshot."
  @spec build(map()) :: map()
  def build(snapshot) do
    %{
      "schema_version" => "1.0.0",
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "host" => %{
        "name" => "wotex_lab_workbench",
        "version" => WotexLabWorkbench.version(),
        "source_mode" => Provenance.source_mode()
      },
      "session" => snapshot.id,
      "provenance" => %{
        "source_tree_digest" => Provenance.source_tree_digest(),
        "lock_digest" => Provenance.lock_digest(),
        "dependencies" => Runs.plain(Provenance.dependencies()),
        "fixtures" => Provenance.fixtures(),
        "specs" => Provenance.specs(),
        "source_cohort" => Provenance.cohort(),
        "source_index" => Map.take(Provenance.source_index(), ["kind", "observed_on", "packages"])
      },
      "runs" => Enum.map(snapshot.runs, &run_entry/1),
      "datasets" => Runs.plain(snapshot.datasets),
      "formal" => Enum.map(snapshot.formal, &Result.to_map/1),
      "policy" => Runs.plain(snapshot.policy),
      "conformance" => %{
        "status" => "not_run",
        "note" => "the conformance runner is not a host dependency; see the Lab's own gate"
      },
      "truncated" => false
    }
  end

  @doc "Encodes the report, dropping the oldest runs until it fits the byte ceiling."
  @spec encode(map()) :: {:ok, binary()} | {:error, :too_large}
  def encode(report) do
    json = Jason.encode!(report)

    cond do
      byte_size(json) <= @max_bytes -> {:ok, json}
      report["runs"] == [] -> {:error, :too_large}
      true -> encode(%{report | "runs" => Enum.drop(report["runs"], -1), "truncated" => true})
    end
  end

  defp run_entry(%Run{} = run) do
    %{
      "id" => run.id,
      "experiment" => run.experiment,
      "status" => Atom.to_string(run.status),
      "record_digest" => run.record_digest,
      "record" => run.record && Record.to_map(run.record),
      "proposal" => run.proposal,
      "decision" => run.decision,
      "dispatch" => run.dispatch,
      "effect" => Runs.plain(run.effect),
      "error" => run.error
    }
  end
end
