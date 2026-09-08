defmodule Wotex.Lab.EvidenceManifestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.{Digest, Record}

  @record_keys ~w(deadline_ms max_inflight max_payload_bytes max_response_bytes
                  maximum_packet_size receive_maximum run_ms broker_enabled test_count)a

  @source_files [
    "mix.exs",
    "docs/specs/WLB.04-runtime-and-network-adapters.md",
    "lib/wotex/lab/adapters/http/req_client.ex",
    "lib/wotex/lab/adapters/http/sse/parser.ex",
    "lib/wotex/lab/adapters/http/sse/session.ex",
    "lib/wotex/lab/adapters/mqtt/emqtt_client.ex",
    "lib/wotex/lab/adapters/mqtt/sample_admission.ex",
    "lib/wotex/lab/adapters/mqtt/session.ex",
    "lib/wotex/lab/adapters/runtime/loopback.ex",
    "lib/wotex/lab/adapters/runtime/loopback/session.ex",
    "lib/wotex/lab/adapters/runtime/no_sec.ex",
    "lib/wotex/lab/adapters/runtime/static_ref.ex",
    "lib/wotex/lab/network/destination.ex",
    "lib/wotex/lab/reference/thing.ex",
    "test/fixtures/tls/ca-cert.pem",
    "test/fixtures/tls/localhost-cert.pem",
    "test/fixtures/tls/localhost-key.pem",
    "test/support/http_server.ex",
    "test/support/mqtt_broker.ex",
    "test/support/mqtt_server.ex",
    "test/support/mqtt_thing.ex",
    "test/wotex/lab/evidence_manifest_test.exs",
    "test/wotex/lab/http_destination_test.exs",
    "test/wotex/lab/http_test.exs",
    "test/wotex/lab/loopback_test.exs",
    "test/wotex/lab/mqtt_broker_test.exs",
    "test/wotex/lab/mqtt_sample_admission_test.exs",
    "test/wotex/lab/mqtt_test.exs"
  ]

  test "the WLB.04 run record is public, complete and bound to its exact inputs" do
    root = Path.expand("../../..", __DIR__)
    assert Enum.all?(@record_keys, &is_atom/1)

    assert {:ok, json} = File.read(Path.join(root, "docs/provenance/WLB.04-evidence.json"))
    assert {:ok, map} = Wotex.JSON.decode(json)
    assert {:ok, record} = Record.from_map(map)

    assert record.scenario_id == "WLB.04-runtime-and-network-adapters"
    assert record.cleanup == %{status: :ok, details: %{"containers" => 0, "sessions" => 0}}
    assert record.outcomes.broker_enabled
    assert record.outcomes.test_count > 0
    assert record.durations.run_ms > 0
    assert Enum.all?(record.assertions, &(&1.status == :pass))

    assert {:ok, record.source_tree_digest} == Digest.tree(root, @source_files)
    assert {:ok, record.lock_digest} == Digest.file(Path.join(root, "mix.lock"))

    Enum.each(record.fixtures, fn {name, digest} ->
      assert Digest.file!(Path.join(root, "test/fixtures/#{name}")) == digest
    end)
  end
end
