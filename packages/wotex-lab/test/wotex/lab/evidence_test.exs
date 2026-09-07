defmodule Wotex.Lab.EvidenceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.{Digest, Record}

  @digest "sha256:" <> String.duplicate("ab", 32)

  defp fields(overrides \\ %{}) do
    Map.merge(
      %{
        scenario_id: "smart-room",
        revision: "aa1a007",
        attempt: 1,
        source_tree_digest: @digest,
        lock_digest: @digest,
        dependencies: [
          %{name: "wotex", version: "0.1.0", archive: @digest},
          %{name: "wotex_nx", version: "0.1.0", archive: :missing}
        ],
        fixtures: %{"loopback/thing-description.json" => @digest},
        seed: 7,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{max_rows: 2, deadline_ms: 5_000},
        inputs: ["fixture:loopback/thing-description.json"],
        assertions: [
          %{id: "WLB-C05:dispatch-once", status: :pass},
          %{id: "WLB-C05:mqtt", status: :not_run}
        ],
        outcomes: %{effect: 22.5, decision: :dispatched, note: "under budget"},
        durations: %{run_ms: 12},
        cleanup: %{status: :ok, details: %{containers: 0}}
      },
      overrides
    )
  end

  test "a complete record round-trips through its map form with a stable canonical digest" do
    assert {:ok, record} = Record.new(fields())
    assert record.schema_version == Record.schema_version()
    map = Record.to_map(record)

    assert map["dependencies"] == [
             %{"name" => "wotex", "version" => "0.1.0", "archive" => @digest},
             %{"name" => "wotex_nx", "version" => "0.1.0", "archive" => "missing"}
           ]

    assert map["assertions"] == [
             %{"id" => "WLB-C05:dispatch-once", "status" => "pass"},
             %{"id" => "WLB-C05:mqtt", "status" => "not_run"}
           ]

    assert map["outcomes"] == %{
             "effect" => 22.5,
             "decision" => "dispatched",
             "note" => "under budget"
           }

    assert {:ok, digest} = Record.digest(record)
    assert digest =~ ~r/\Asha256:[0-9a-f]{64}\z/

    assert {:ok, again} =
             Record.new(
               fields(%{outcomes: %{note: "under budget", decision: :dispatched, effect: 22.5}})
             )

    assert {:ok, ^digest} = Record.digest(again)

    assert {:ok, encoded} = Record.encode(record)
    assert {:ok, decoded} = Wotex.JSON.decode(encoded)
    assert {:ok, read} = Record.from_map(decoded)
    assert read.dependencies == record.dependencies
    assert read.assertions == record.assertions
    assert read.cleanup == %{status: :ok, details: %{"containers" => 0}}
    assert {:ok, ^digest} = Record.digest(%{read | cleanup: record.cleanup})
    assert {:ok, other} = Record.new(fields(%{attempt: 2}))
    assert {:ok, other_digest} = Record.digest(other)
    refute other_digest == digest
  end

  test "missing archive evidence must be stated, never synthesized" do
    unstated = [%{name: "wotex", version: "0.1.0"}]

    assert {:error, %Error{code: :archive_evidence_unstated, path: "/dependencies/0/archive"}} =
             Record.new(fields(%{dependencies: unstated}))

    assert {:error, %Error{code: :invalid_digest, path: "/dependencies/0/archive"}} =
             Record.new(
               fields(%{dependencies: [%{name: "wotex", version: "0.1.0", archive: "git:abc"}]})
             )

    assert {:error, %Error{code: :archive_evidence_unstated}} =
             Record.from_map(%{
               Record.to_map(elem(Record.new(fields()), 1))
               | "dependencies" => [%{"name" => "a", "version" => "1"}]
             })
  end

  test "callbacks, process identities, paths, secrets and structs are not public evidence" do
    assert {:error, %Error{code: :invalid_outcomes}} =
             Record.new(fields(%{outcomes: %{callback: fn -> :ok end}}))

    assert {:error, %Error{code: :not_public_evidence, path: "/cleanup/details/callback"}} =
             Record.new(fields(%{cleanup: %{status: :ok, details: %{callback: fn -> :ok end}}}))

    assert {:error, %Error{code: :invalid_outcomes}} =
             Record.new(fields(%{outcomes: %{pid: self()}}))

    assert {:error, %Error{code: :not_public_evidence, path: "/cleanup/details/pid"}} =
             Record.new(fields(%{cleanup: %{status: :ok, details: %{pid: self()}}}))

    assert {:error, %Error{code: :not_public_evidence, path: "/inputs/0"}} =
             Record.new(fields(%{inputs: ["/tmp/private/fixture.json"]}))

    assert {:error, %Error{code: :not_public_evidence, path: "/inputs/0"}} =
             Record.new(fields(%{inputs: ["./bin/run.sh"]}))

    assert {:error, %Error{code: :not_public_evidence, path: "/outcomes/note"}} =
             Record.new(fields(%{outcomes: %{note: "Bearer abc.def"}}))

    assert {:error, %Error{code: :not_public_evidence, path: "/cleanup/details/env"}} =
             Record.new(fields(%{cleanup: %{status: :ok, details: %{env: "password=hunter2"}}}))

    assert {:error, %Error{code: :not_public_evidence, path: "/cleanup/details/key"}} =
             Record.new(
               fields(%{cleanup: %{status: :ok, details: %{key: "-----BEGIN PRIVATE KEY-----"}}})
             )

    assert {:error, %Error{code: :not_public_evidence, path: "/cleanup/details/date"}} =
             Record.new(fields(%{cleanup: %{status: :ok, details: %{date: ~D[2026-09-08]}}}))
  end

  test "every field is validated with a typed error and a pointer path" do
    assert {:error, %Error{code: :missing_field, details: %{missing: [:seed]}}} =
             Record.new(Map.delete(fields(), :seed))

    assert {:error, %Error{code: :invalid_record}} = Record.new("nope")

    assert {:error, %Error{code: :invalid_text, path: "/scenario_id"}} =
             Record.new(fields(%{scenario_id: ""}))

    assert {:error, %Error{code: :invalid_attempt, path: "/attempt"}} =
             Record.new(fields(%{attempt: 0}))

    assert {:error, %Error{code: :invalid_digest, path: "/lock_digest"}} =
             Record.new(fields(%{lock_digest: "sha1:abc"}))

    assert {:error, %Error{code: :invalid_dependencies}} =
             Record.new(fields(%{dependencies: :none}))

    assert {:error, %Error{code: :invalid_dependency, path: "/dependencies/0"}} =
             Record.new(fields(%{dependencies: [%{name: "x"}]}))

    assert {:error, %Error{code: :invalid_digest, path: "/fixtures"}} =
             Record.new(fields(%{fixtures: %{"a" => "b"}}))

    assert {:error, %Error{code: :invalid_fixtures}} = Record.new(fields(%{fixtures: []}))
    assert {:error, %Error{code: :invalid_seed}} = Record.new(fields(%{seed: "7"}))

    assert {:error, %Error{code: :invalid_toolchain}} =
             Record.new(fields(%{toolchain: %{elixir: "1.20"}}))

    assert {:error, %Error{code: :invalid_budgets}} = Record.new(fields(%{budgets: %{"rows" => 1}}))
    assert {:error, %Error{code: :invalid_budgets}} = Record.new(fields(%{budgets: %{rows: -1}}))
    assert {:error, %Error{code: :invalid_budgets}} = Record.new(fields(%{budgets: [rows: 1]}))
    assert {:error, %Error{code: :invalid_inputs}} = Record.new(fields(%{inputs: [""]}))
    assert {:error, %Error{code: :invalid_inputs}} = Record.new(fields(%{inputs: "x"}))

    assert {:error, %Error{code: :invalid_assertions}} =
             Record.new(fields(%{assertions: [%{id: "a", status: :maybe}]}))

    assert {:error, %Error{code: :invalid_assertions}} = Record.new(fields(%{assertions: %{}}))
    assert {:error, %Error{code: :invalid_outcomes}} = Record.new(fields(%{outcomes: %{list: [1]}}))
    assert {:error, %Error{code: :invalid_outcomes}} = Record.new(fields(%{outcomes: []}))

    assert {:error, %Error{code: :invalid_durations}} =
             Record.new(fields(%{durations: %{run_ms: 1.5}}))

    assert {:error, %Error{code: :invalid_cleanup}} =
             Record.new(fields(%{cleanup: %{status: :done, details: %{}}}))
  end

  test "reading back refuses other schema versions and unknown keys" do
    assert {:error, %Error{code: :unsupported_schema_version, path: "/schema_version"}} =
             Record.from_map(%{"schema_version" => "2.0.0"})

    assert {:error, %Error{code: :invalid_record}} = Record.from_map(%{})
    {:ok, record} = Record.new(fields())
    map = Record.to_map(record)

    assert {:error, %Error{code: :invalid_budgets}} =
             Record.from_map(%{map | "budgets" => %{"never_seen_key_zz" => 1}})

    assert {:error, %Error{code: :invalid_assertions}} =
             Record.from_map(%{map | "assertions" => [%{"id" => "a", "status" => "maybe"}]})

    assert {:error, %Error{code: :invalid_cleanup}} =
             Record.from_map(%{map | "cleanup" => %{"status" => "ok"}})

    assert {:error, %Error{code: :invalid_toolchain}} = Record.from_map(%{map | "toolchain" => "x"})

    assert {:error, %Error{code: :invalid_dependency}} =
             Record.from_map(%{map | "dependencies" => ["x"]})
  end

  test "digests are content digests of files and trees, with the toolchain recorded as strings" do
    root = Path.join(System.tmp_dir!(), "wotex-lab-digest-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "a"))
    File.write!(Path.join(root, "a/one.txt"), "one")
    File.write!(Path.join(root, "two.txt"), "two")
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, one} = Digest.file(Path.join(root, "a/one.txt"))
    assert one == Digest.bytes("one")
    assert {:error, :enoent} = Digest.file(Path.join(root, "missing"))

    assert {:ok, tree} = Digest.tree(root, ["**/*.txt"])
    assert tree =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert {:ok, ^tree} = Digest.tree(root, ["two.txt", "a/*.txt"])
    File.write!(Path.join(root, "two.txt"), "TWO")
    assert {:ok, changed} = Digest.tree(root, ["**/*.txt"])
    refute changed == tree

    toolchain = Digest.toolchain(Nx.BinaryBackend)
    assert %{elixir: elixir, otp: otp, backend: "Nx.BinaryBackend", platform: platform} = toolchain
    assert elixir == System.version() and is_binary(otp) and is_binary(platform)
  end
end
