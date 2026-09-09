defmodule Wotex.Lab.WLB01EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :integration

  alias Wotex.Lab.Evidence.{Digest, Record}

  @record_keys ~w(children default_children_per_role instances max_children_per_role roles
                  run_ms test_count)a

  @source_files [
    "mix.exs",
    "docs/plans/wotex-lab-completion.md",
    "docs/provenance/source-cohort.json",
    "docs/provenance/source-index.json",
    "docs/provenance/wotex-lab-api.json",
    "docs/specs/WLB.01-library-foundation.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab.ex",
    "lib/wotex/lab/error.ex",
    "lib/wotex/lab/options.ex",
    "lib/wotex/lab/plugin.ex",
    "lib/wotex/lab/supervisor.ex",
    "test/wotex/lab/library_contract_test.exs",
    "test/wotex/lab/supervisor_test.exs",
    "test/wotex/lab/wlb01_evidence_manifest_test.exs"
  ]

  test "the foundation record is complete and bound to its source cohort" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)
    path = Path.join(root, "docs/provenance/WLB.01-evidence.json")
    assert {:ok, map} = path |> File.read!() |> Wotex.JSON.decode()
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.01-library-foundation"
    assert record.outcomes.test_count == 12
    assert Enum.all?(record.assertions, &(&1.status == :pass))
    assert record.cleanup == %{status: :ok, details: %{"children" => 0, "instances" => 0}}
    assert {:ok, record.source_tree_digest} == Digest.tree(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))
  end
end
