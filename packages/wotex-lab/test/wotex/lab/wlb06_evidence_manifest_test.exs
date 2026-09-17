defmodule Wotex.Lab.WLB06EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag :integration

  alias Wotex.Conformance.Corpus
  alias Wotex.Lab.Evidence.{Digest, Record}

  @record_keys ~w(cpu_seconds deadline_ms max_output_bytes memory_bytes processes samples
                  run_ms excluded_count test_count thing_description_vectors thing_model_vectors
                  container_test_count)a

  @source_files [
    "mix.exs",
    "docs/plans/wotex-lab-completion.md",
    "docs/provenance/source-cohort.json",
    "docs/provenance/source-index.json",
    "docs/specs/WLB.06-evidence-conformance-and-observability.md",
    "docs/decisions/0006-native-containment-executable.md",
    "docs/decisions/0009-kernel-isolated-conformance-profile.md",
    "docs/specs/catalogue.yaml",
    "lib/wotex/lab/benchmark.ex",
    "lib/wotex/lab/conformance/containment.ex",
    "lib/wotex/lab/conformance/kernel_containment.ex",
    "lib/wotex/lab/conformance/target.ex",
    "lib/wotex/lab/continuum/fault_schedule.ex",
    "lib/wotex/lab/evidence/digest.ex",
    "lib/wotex/lab/evidence/record.ex",
    "lib/wotex/lab/graph.ex",
    "lib/wotex/lab/telemetry.ex",
    "priv/conformance/native/Cargo.toml",
    "priv/conformance/native/Cargo.lock",
    "priv/conformance/native/src/main.rs",
    "priv/conformance/native/src/config.rs",
    "priv/conformance/native/src/accounting.rs",
    "priv/conformance/native/probes/main.rs",
    "priv/conformance/native/tests/lifecycle.rs",
    "test/support/native_containment.ex",
    "test/test_helper.exs",
    "test/wotex/lab/benchmark_test.exs",
    "test/wotex/lab/conformance_target_process_test.exs",
    "test/wotex/lab/conformance_test.exs",
    "test/wotex/lab/continuum_test.exs",
    "test/wotex/lab/evidence_test.exs",
    "test/wotex/lab/graph_test.exs",
    "test/wotex/lab/kernel_containment_lane_test.exs",
    "test/wotex/lab/kernel_containment_test.exs",
    "test/wotex/lab/telemetry_test.exs",
    "test/wotex/lab/wlb06_evidence_manifest_test.exs"
  ]

  test "the WLB.06 run record is public, complete and bound to its exact inputs" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, json} = File.read(Path.join(root, "docs/provenance/WLB.06-evidence.json"))
    assert {:ok, map} = Wotex.JSON.decode(json)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.06-evidence-conformance-and-observability"

    assert record.cleanup == %{
             status: :ok,
             details: %{"descendants" => 0, "ports" => 0, "temporary_directories" => 0}
           }

    assert record.outcomes.excluded_count == 1
    assert record.outcomes.thing_description_vectors == 16
    assert record.outcomes.thing_model_vectors == 8
    assert record.outcomes.test_count > 0
    assert record.outcomes.container_test_count > 0
    assert record.durations.run_ms > 0

    assert Enum.map(Enum.filter(record.assertions, &(&1.status == :not_run)), & &1.id) ==
             ["WCF-C05:discovery-corpus", "WLB-C07:linux-bubblewrap-reviewed-local"]

    assert Enum.all?(
             Enum.reject(record.assertions, &(&1.status == :not_run)),
             &(&1.status == :pass)
           )

    assert {:ok, record.source_tree_digest} == Digest.tree(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))

    for {id, digest} <- record.fixtures do
      directory = String.replace_prefix(id, "corpus:", "")

      assert {:ok, corpus} =
               Corpus.load(Application.app_dir(:wotex_conformance, "priv/vectors/" <> directory))

      assert corpus.digest == digest
    end
  end
end
