defmodule Wotex.Lab.WLB11EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Test.SourceTree

  @moduletag :integration

  @record_keys ~w(asset_build_ms asset_files browser_status browser_timeout_ms hosted_adoption
                  island_families viewport_minimum_px wcag_certification zoom_percent)a

  @source_files [
    "docs/specs/WLB.11-workbench-and-design-system.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab/design_system.ex",
    "test/wotex/lab/design_system_test.exs",
    "hosts/workbench/assets/**/*",
    "hosts/workbench/bin/check_assets.mjs",
    "hosts/workbench/bin/check_islands_browser.mjs",
    "hosts/workbench/bin/clean_assets.mjs",
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
    "hosts/workbench/test/wotex_lab_workbench_web/islands_test.exs",
    "hosts/workbench/test/wotex_lab_workbench_web/workbench_live_test.exs",
    "hosts/storybook/config/**/*",
    "hosts/storybook/lib/**/*",
    "hosts/storybook/priv/static/contract-assets/**/*",
    "hosts/storybook/storybook/**/*",
    "hosts/storybook/test/**/*",
    "hosts/storybook/README.md",
    "hosts/storybook/mix.exs",
    "hosts/storybook/mix.lock",
    "test/wotex/lab/wlb11_evidence_manifest_test.exs"
  ]

  test "the WLB.11 record binds the shared frontend and real-browser cohort" do
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
    assert {:ok, record.source_tree_digest} == SourceTree.digest(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "hosts/workbench/mix.lock"))
  end
end
