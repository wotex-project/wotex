defmodule Wotex.Lab.WLB12EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Test.SourceTree

  @moduletag :integration

  @record_keys ~w(archive_deadline_ms archive_gate_ms browser_gate_ms browser_status
                  browser_timeout_ms git_on_release_path hosted_adoption release_built
                  resolved_archives search_asset_bytes search_filters site_artifact_bytes
                  surfaces wcag_certification)a

  @source_files [
    "../../.github/workflows/documentation.yml",
    "../../tooling/doc_shell_collector/bin/build.exs",
    "../../tooling/doc_shell_collector/mix.exs",
    "../../tooling/doc_shell_collector/mix.lock",
    "docs/decisions/0008-unified-documentation-publication.md",
    "docs/plans/unified-documentation.md",
    "docs/specs/WLB.12-unified-documentation.md",
    "bin/build_artifacts.exs",
    "bin/check_workbench_archive.exs",
    "bin/support/archive_repository.exs",
    "lib/wotex/lab/docs/**/*",
    "test/wotex/lab/docs/**/*",
    "hosts/workbench/test/e2e/documentation_test.exs",
    "hosts/workbench/test/support/documentation_server.ex",
    "hosts/workbench/tools/documentation/browser_fixture_support.exs",
    "hosts/workbench/tools/documentation/browser_fixture.exs",
    "hosts/workbench/lib/mix/tasks/wotex_lab.docs.build.ex",
    "hosts/workbench/lib/wotex_lab_workbench/documentation.ex",
    "hosts/workbench/lib/wotex_lab_workbench/documentation/**/*",
    "hosts/workbench/lib/wotex_lab_workbench_web/documentation_live.ex",
    "hosts/workbench/test/wotex_lab_workbench/documentation_build_test.exs",
    "hosts/workbench/test/wotex_lab_workbench/documentation_publication_test.exs",
    "hosts/workbench/test/wotex_lab_workbench/documentation_storybook_builder_test.exs",
    "hosts/workbench/test/wotex_lab_workbench_web/documentation_live_test.exs",
    "test/wotex/lab/wlb12_evidence_manifest_test.exs"
  ]

  test "the historical WLB.12 record remains stale after tooling relocation" do
    root = Path.expand("../../..", __DIR__)
    path = Path.join(root, "priv/provenance/WLB.12-evidence.json")
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, bytes} = File.read(path)
    assert {:ok, map} = Wotex.JSON.decode(bytes)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.12-unified-documentation"
    assert record.outcomes.browser_status == "passed"
    assert record.outcomes.release_built
    assert record.outcomes.git_on_release_path == false
    assert record.outcomes.search_filters == 7
    assert record.outcomes.surfaces == 2
    refute record.outcomes.wcag_certification
    refute record.outcomes.hosted_adoption
    assert Enum.all?(record.assertions, &(&1.status == :pass))
    refute {:ok, record.source_tree_digest} == SourceTree.digest(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "hosts/workbench/mix.lock"))
  end
end
