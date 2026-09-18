defmodule Wotex.Lab.WLB02EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Runner.Budgets
  alias Wotex.Lab.Test.SourceTree

  @moduletag :integration

  @record_keys ~w(children_per_role cleanup_ms ingress_bytes max_steps queued_deliveries
                  reconnect_attempts wall_ms admitted_scenarios children frontends run_ms
                  test_count work_files workbench_test_count)a

  @assertions ~w(
    WLB-C02:closed-descriptor
    WLB-C02:identical-frontend-descriptors
    WLB-C02:preflight-before-startup
    WLB-C02:concurrent-attempt-isolation
    WLB-C02:independent-plugin-hosts
    WLB-C02:partial-startup-unwind
    WLB-C02:exhausted-limits
    WLB-C02:callback-failures
    WLB-C02:cancellation-and-late-results
    WLB-C02:receiver-death-and-forced-kill
    WLB-C02:deterministic-replay
    WLB-C02:no-leaked-children-or-files
    WLB-C02:manifest-integrity
  )

  @source_files [
    "mix.exs",
    "docs/plans/wotex-lab-completion.md",
    "priv/provenance/source-cohort.json",
    "priv/provenance/source-index.json",
    "docs/specs/WLB.02-scenarios-and-reference-components.md",
    "docs/specs/catalogue.yaml",
    "hosts/workbench/lib/wotex_lab_workbench/control.ex",
    "hosts/workbench/lib/wotex_lab_workbench_web/controllers/control_controller.ex",
    "hosts/workbench/mix.lock",
    "hosts/workbench/test/wotex_lab_workbench_web/control_controller_test.exs",
    "lib/mix/tasks/wotex.lab.scenarios.ex",
    "lib/wotex/lab/component.ex",
    "lib/wotex/lab/graph/descriptors.ex",
    "lib/wotex/lab/mcp/resources.ex",
    "lib/wotex/lab/plugin.ex",
    "lib/wotex/lab/runner.ex",
    "lib/wotex/lab/runner/*.ex",
    "lib/wotex/lab/scenario.ex",
    "priv/cookbooks/nerves-and-mcp.livemd",
    "priv/fixtures/loopback/thing-description.json",
    "test/support/*_component.ex",
    "test/support/cookbook_runner.ex",
    "test/wotex/lab/runner_test.exs",
    "test/wotex/lab/scenario_frontends_test.exs",
    "test/wotex/lab/scenario_test.exs",
    "test/wotex/lab/wlb02_evidence_manifest_test.exs"
  ]

  test "the scenario runner record covers every WLB.02 obligation and its exact inputs" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)
    path = Path.join(root, "priv/provenance/WLB.02-evidence.json")
    assert {:ok, map} = Wotex.JSON.decode(File.read!(path))
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.02-scenarios-and-reference-components"
    assert Enum.map(record.assertions, & &1.id) == @assertions
    assert Enum.all?(record.assertions, &(&1.status == :pass))
    assert record.budgets == Budgets.defaults()
    assert record.outcomes.admitted_scenarios == length(Wotex.Lab.Scenario.admitted())
    assert record.outcomes.frontends == 4
    assert record.outcomes.test_count > 0
    assert record.outcomes.workbench_test_count > 0
    assert record.durations.run_ms > 0

    assert record.cleanup == %{status: :ok, details: %{"children" => 0, "work_files" => 0}}

    assert {:ok, record.source_tree_digest} == SourceTree.digest(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))

    for {name, digest} <- record.fixtures do
      assert {:ok, ^digest} = Digest.file(Path.join(root, "priv/fixtures/#{name}"))
    end
  end
end
