defmodule WotexLabWorkbench.InvestigationPresentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexLabWorkbench.Investigation.{Answer, RunContext}
  alias WotexLabWorkbench.Run

  test "run context selects only an older run of the same experiment" do
    newest = run("run-3", "thermal", 3)
    unrelated = run("run-2", "window_anomaly", 2)
    baseline = run("run-1", "thermal", 1)

    assert {:ok, current, selected_baseline} =
             RunContext.select([newest, unrelated, baseline], "run-3")

    assert current["id"] == "run-3"
    assert selected_baseline["id"] == "run-1"

    assert Map.keys(current) |> Enum.sort() ==
             ~w(assertions attempt backend duration_ms error evidence_digest experiment id source_mode started_at status summary)

    assert {:ok, older, nil} = RunContext.select([newest, unrelated, baseline], "run-1")
    assert older["id"] == "run-1"
    assert {:error, :no_run} = RunContext.select([], nil)
    assert {:error, :no_run} = RunContext.select([newest], "other")
  end

  test "answer preserves facts and hypotheses but never accepts source URLs" do
    notification = %{
      "context" => "Run <script>one</script>",
      "observation" => "Metric nx_duration_seconds increased.",
      "hypothesis" => "Backend contention might explain the increase.",
      "snapshots" => [%{"id" => "snapshot-1", "href" => "https://attacker.invalid"}]
    }

    answer =
      Answer.from_result(
        {:ok, %{notifications: [notification]}},
        %{provider: :ollama, model: "qwen3.5:4b-q4_K_M"}
      )

    assert answer.status == "complete"
    assert hd(answer.observed) =~ "<script>"
    assert answer.hypotheses == ["Backend contention might explain the increase."]

    assert answer.sources == [
             %{label: "BeamLens snapshot snapshot-1", href: "/evidence"},
             %{label: "Bounded session evidence", href: "/evidence"}
           ]

    assert answer.provider == "ollama"
    assert answer.model == "qwen3.5:4b-q4_K_M"
  end

  test "empty and failed results do not claim health" do
    empty = Answer.from_result({:ok, %{notifications: []}}, %{})
    assert empty.status == "complete"
    assert hd(empty.missing) =~ "not evidence"

    timeout = Answer.from_result({:error, :investigation_timeout}, %{})
    assert timeout.status == "timed out"
    assert hd(timeout.observed) =~ "deadline"

    unavailable = Answer.from_result(:malformed, %{})
    assert unavailable.status == "unavailable"
  end

  defp run(id, experiment, attempt) do
    %Run{
      id: id,
      experiment: experiment,
      attempt: attempt,
      params: [],
      status: :completed,
      source_mode: "source",
      backend: "binary",
      started_at: ~U[2026-09-08 00:00:00Z],
      duration_ms: attempt,
      summary: [{"attempt", Integer.to_string(attempt)}],
      assertions: [%{id: "assertion", status: :pass, note: "bounded"}],
      record_digest: "sha256:#{attempt}"
    }
  end
end
