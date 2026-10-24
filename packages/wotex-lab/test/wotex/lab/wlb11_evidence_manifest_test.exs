defmodule Wotex.Lab.WLB11EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Test.SourceTree

  @moduletag :integration

  @record_keys ~w(asset_build_ms asset_files browser_status browser_timeout_ms hosted_adoption
                  island_families viewport_minimum_px wcag_certification zoom_percent)a

  @current_source_files [
    "docs/specs/WLB.11-workbench-and-design-system.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab/design_system.ex",
    "test/wotex/lab/design_system_test.exs",
    "hosts/workbench/assets/**/*",
    "hosts/workbench/tools/assets/check.ts",
    "hosts/workbench/test/e2e/island_reconnect_test.exs",
    "hosts/workbench/test/e2e/island_fallback_test.exs",
    "hosts/workbench/test/e2e/analytics_test.exs",
    "hosts/workbench/test/e2e/backend_journeys_test.exs",
    "hosts/workbench/tools/assets/clean.ts",
    "hosts/workbench/config/**/*",
    "hosts/workbench/lib/wotex_lab_workbench_web/components/shell.ex",
    "hosts/workbench/lib/wotex_lab_workbench_web/islands.ex",
    "hosts/workbench/lib/wotex_lab_workbench_web/workbench_live.ex",
    "hosts/workbench/mix.exs",
    "hosts/workbench/mix.lock",
    "hosts/workbench/package.json",
    "hosts/workbench/pnpm-lock.yaml",
    "hosts/workbench/pnpm-workspace.yaml",
    "hosts/workbench/tsconfig.json",
    "hosts/workbench/vite.config.ts",
    "hosts/workbench/storybook/**/*",
    "hosts/workbench/priv/static/contract-assets/**/*",
    "hosts/workbench/test/e2e/storybook_islands_test.exs",
    "hosts/workbench/test/frontend/storybook-bridge.test.ts",
    "hosts/workbench/test/wotex_lab_workbench/storybook_design_contract_test.exs",
    "hosts/workbench/test/wotex_lab_workbench_web/storybook_test.exs",
    "hosts/workbench/test/wotex_lab_workbench_web/islands_test.exs",
    "hosts/workbench/test/wotex_lab_workbench_web/workbench_live_test.exs",
    "test/wotex/lab/wlb11_evidence_manifest_test.exs"
  ]

  test "the historical WLB.11 record remains valid and stale for the consolidated host" do
    root = Path.expand("../../..", __DIR__)
    path = Path.join(root, "priv/provenance/WLB.11-evidence.json")
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, bytes} = File.read(path)
    assert {:ok, map} = Wotex.JSON.decode(bytes)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.11-workbench-and-design-system"
    assert record.outcomes.asset_files == 8
    assert record.outcomes.island_families == 3
    assert record.outcomes.browser_status == "passed"
    refute record.outcomes.wcag_certification
    refute record.outcomes.hosted_adoption
    assert Enum.all?(record.assertions, &(&1.status == :pass))
    refute {:ok, record.source_tree_digest} == SourceTree.digest(root, @current_source_files)
    refute {:ok, record.lock_digest} == Digest.file(Path.join(root, "hosts/workbench/mix.lock"))
  end
end
