defmodule Wotex.Lab.WLB05EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}

  @record_keys ~w(capacity deadline_ms max_expiry_batch_limit max_page_limit max_rows
                  run_ms broker_enabled excluded_count test_count)a

  @source_files [
    "mix.exs",
    "docs/provenance/source-cohort.json",
    "docs/specs/WLB.05-directory-continuum-and-smart-room.md",
    "docs/specs/WLB.07-cookbooks-and-machine-interfaces.md",
    "lib/wotex/lab/cookbook.ex",
    "lib/wotex/lab/adapters/directory/authorization.ex",
    "lib/wotex/lab/adapters/directory/clock.ex",
    "lib/wotex/lab/adapters/directory/ets_repository.ex",
    "lib/wotex/lab/adapters/directory/identifier.ex",
    "lib/wotex/lab/adapters/directory/sqlite_repository.ex",
    "lib/wotex/lab/continuum/channel.ex",
    "lib/wotex/lab/continuum/fault_schedule.ex",
    "lib/wotex/lab/continuum/host.ex",
    "lib/wotex/lab/continuum/wire.ex",
    "lib/wotex/lab/smart_room/policy.ex",
    "lib/wotex/lab/smart_room/scenario.ex",
    "priv/cookbooks/*.livemd",
    "priv/fixtures/loopback/thing-description.json",
    "test/support/continuum_fixtures.ex",
    "test/support/cookbook_runner.ex",
    "test/support/http_server.ex",
    "test/support/mqtt_broker.ex",
    "test/support/mqtt_server.ex",
    "test/wotex/lab/continuum_test.exs",
    "test/wotex/lab/cookbook_test.exs",
    "test/wotex/lab/directory_test.exs",
    "test/wotex/lab/smart_room_test.exs",
    "test/wotex/lab/wlb05_evidence_manifest_test.exs"
  ]

  test "the WLB.05 run record is public, complete and bound to its exact inputs" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, json} = File.read(Path.join(root, "docs/provenance/WLB.05-evidence.json"))
    assert {:ok, map} = Wotex.JSON.decode(json)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.05-directory-continuum-and-smart-room"

    assert record.cleanup == %{
             status: :ok,
             details: %{"containers" => 0, "sessions" => 0, "sqlite_files" => 0}
           }

    assert record.outcomes.broker_enabled
    assert record.outcomes.test_count > 0
    assert record.durations.run_ms > 0
    assert Enum.all?(record.assertions, &(&1.status == :pass))

    assert {:ok, record.source_tree_digest} == Digest.tree(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))

    Enum.each(record.fixtures, fn {name, digest} ->
      assert Digest.file!(Path.join(root, "priv/fixtures/#{name}")) == digest
    end)
  end
end
