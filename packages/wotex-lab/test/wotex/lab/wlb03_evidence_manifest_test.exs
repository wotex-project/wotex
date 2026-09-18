defmodule Wotex.Lab.WLB03EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Test.SourceTree

  @moduletag :integration

  @record_keys ~w(deadline_ms device_tensors effects excluded_count max_samples
                  max_schedule_entries required_lanes run_ms servings test_count tolerance_ppm)a

  @source_files [
    "mix.exs",
    "docs/plans/wotex-lab-completion.md",
    "priv/provenance/source-cohort.json",
    "priv/provenance/source-index.json",
    "docs/specs/WLB.03-nx-experiments.md",
    "docs/decisions/0005-interactive-elixir-analytics.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab/adapters/nx/unit_converter.ex",
    "lib/wotex/lab/examples/thermal.ex",
    "lib/wotex/lab/examples/window_anomaly.ex",
    "lib/wotex/lab/experiments/room_model.ex",
    "lib/wotex/lab/simulators/thermal.ex",
    "lib/wotex/lab/smart_room/policy.ex",
    "lib/wotex/lab/smart_room/scenario.ex",
    "priv/cookbooks/thermal-nx.livemd",
    "priv/cookbooks/window-anomaly.livemd",
    "priv/cookbooks/serving-batches.livemd",
    "priv/cookbooks/axon-room-model.livemd",
    "priv/cookbooks/smart-room.livemd",
    "priv/fixtures/thermal/*",
    "test/support/cookbook_runner.ex",
    "test/wotex/lab/backend_cohort_test.exs",
    "test/wotex/lab/cookbook_test.exs",
    "test/wotex/lab/room_model_test.exs",
    "test/wotex/lab/serving_test.exs",
    "test/wotex/lab/smart_room_test.exs",
    "test/wotex/lab/thermal_test.exs",
    "test/wotex/lab/window_anomaly_test.exs",
    "test/wotex/lab/wlb03_evidence_manifest_test.exs"
  ]

  test "the numerical adoption record covers every required local lane" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)
    path = Path.join(root, "priv/provenance/WLB.03-evidence.json")
    assert {:ok, map} = Wotex.JSON.decode(File.read!(path))
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.03-nx-experiments"
    assert record.outcomes.test_count == 52
    assert record.outcomes.excluded_count == 3
    assert record.outcomes.required_lanes == 6
    assert Enum.all?(record.assertions, &(&1.status == :pass))

    assert record.cleanup == %{
             status: :ok,
             details: %{"device_tensors" => 0, "effects" => 0, "servings" => 0}
           }

    assert {:ok, record.source_tree_digest} == SourceTree.digest(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))

    for {name, digest} <- record.fixtures do
      assert {:ok, ^digest} = Digest.file(Path.join(root, "priv/fixtures/thermal/#{name}"))
    end
  end
end
