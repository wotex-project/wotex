defmodule Wotex.Lab.WLB09EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :integration

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Formal.Model

  @record_keys ~w(broken_variants cookbook_checks deadline_ms descendants excluded_count
                  max_depth max_output_bytes pools ports processes reachable_states run_ms
                  safe_properties solutions test_count)a

  @source_files [
    "mix.exs",
    "bin/provision_maude.exs",
    "docs/plans/wotex-lab-completion.md",
    "docs/provenance/source-cohort.json",
    "docs/provenance/source-index.json",
    "docs/specs/WLB.07-cookbooks-and-machine-interfaces.md",
    "docs/specs/WLB.09-formal-control-verification.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab/cookbook.ex",
    "lib/wotex/lab/experiments/room_model.ex",
    "lib/wotex/lab/formal/abstraction.ex",
    "lib/wotex/lab/formal/model.ex",
    "lib/wotex/lab/formal/output.ex",
    "lib/wotex/lab/formal/profile.ex",
    "lib/wotex/lab/formal/replay.ex",
    "lib/wotex/lab/formal/result.ex",
    "lib/wotex/lab/formal/search.ex",
    "lib/wotex/lab/formal/serializer.ex",
    "lib/wotex/lab/mcp/server.ex",
    "lib/wotex/lab/mcp/tools.ex",
    "lib/wotex/lab/smart_room/policy.ex",
    "priv/cookbooks/*.livemd",
    "priv/models/manifest.json",
    "priv/models/thermal-control-v1.maude",
    "test/support/cookbook_runner.ex",
    "test/support/formal_fixtures.ex",
    "test/wotex/lab/cookbook_test.exs",
    "test/wotex/lab/formal_maude_mcp_test.exs",
    "test/wotex/lab/formal_maude_test.exs",
    "test/wotex/lab/formal_search_test.exs",
    "test/wotex/lab/formal_test.exs",
    "test/wotex/lab/mcp_formal_tool_test.exs",
    "test/wotex/lab/wlb09_evidence_manifest_test.exs"
  ]

  test "the WLB.09 source result names its exact model, engine and executable cohort" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, json} = File.read(Path.join(root, "docs/provenance/WLB.09-evidence.json"))
    assert {:ok, map} = Wotex.JSON.decode(json)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.09-formal-control-verification"
    assert record.outcomes.safe_properties == 5
    assert record.outcomes.broken_variants == 5
    assert record.outcomes.reachable_states == 253
    assert record.outcomes.cookbook_checks == 9
    assert record.outcomes.test_count > 0
    assert record.durations.run_ms > 0
    assert Enum.all?(record.assertions, &(&1.status == :pass))

    assert record.cleanup == %{
             status: :ok,
             details: %{"descendants" => 0, "pools" => 0, "ports" => 0}
           }

    assert "engine-executable:sha256:266eed04679fde6029a18e5e2b1828223d4a7169ac55503aa15d67e126792fbf" in record.inputs

    assert %{archive: maude_archive, version: "3.5.1-macos-arm64"} =
             Enum.find(record.dependencies, &(&1.name == "maude"))

    assert maude_archive ==
             "sha256:95851274f57b3853aab833674e2b770ed800f38fb1f3d03c97dcac56346c13dc"

    assert {:ok, model} = Model.fetch(:thermal_control_v1)
    assert {:ok, ^model} = Model.verify(model)
    assert record.fixtures["model:thermal-control-v1"] == model.digest
    assert {:ok, record.source_tree_digest} == Digest.tree(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))
  end
end
