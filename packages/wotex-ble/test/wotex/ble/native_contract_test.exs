defmodule Wotex.BLE.NativeContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @corpus @root
          |> Path.join("docs/specs/fixtures/native-port-v1.json")
          |> File.read!()
          |> Jason.decode!()

  # Each corpus operation has one executable owner. Default owners run in the
  # ordinary suite; interop owners require their explicit native lane.
  @owners %{
    "parse_request" => {:default, "test/wotex/ble/native_frame_test.exs"},
    "ready" => {:interop, "test/interop/native_host_test.exs"},
    "flow_trace" => {:default, "test/wotex/ble/native_credit_test.exs"},
    "process_flow" => {:default, "test/wotex/ble/native_process_flow_test.exs"},
    "decode_bytes" => {:default, "test/wotex/ble/native_bytes_test.exs"},
    "agent_prompt" => {:interop, "test/interop/native_bus_test.exs"},
    "pair_lifecycle" => {:interop, "test/interop/native_bus_test.exs"},
    "gatt_procedure" => {:interop, "test/interop/native_bus_test.exs"},
    "notify_mode" => {:interop, "test/interop/native_bus_test.exs"},
    "notify_lifecycle" => {:interop, "test/interop/native_bus_test.exs"},
    "serialize_frame" => {:default, "test/wotex/ble/native_output_test.exs"},
    "report_lifecycle" => {:default, "test/wotex/ble/native_reports_test.exs"},
    "peer_health" => {:interop, "test/interop/native_bus_test.exs"},
    "discovery_page" => {:default, "test/wotex/ble/native_pages_test.exs"},
    "discovery_cursor_ledger" => {:default, "test/wotex/ble/native_pages_test.exs"},
    "native_host" => {:interop, "test/interop/native_bus_test.exs"},
    "native_artifact_selectors" => {:default, "test/wotex/ble/native_artifacts_test.exs"}
  }

  test "WBL-B03 corpus format, identifiers and normalized expectations are exact" do
    assert Map.take(@corpus, ["format", "version", "package"]) == %{
             "format" => "wotex.native-contract",
             "version" => "1.0.0",
             "package" => "wotex_ble"
           }

    cases = @corpus["cases"]
    ids = Enum.map(cases, & &1["id"])
    assert ids == Enum.uniq(ids)
    assert ids == Enum.map(1..length(cases), &"WBL-B-F#{String.pad_leading("#{&1}", 2, "0")}")

    for fixture <- cases do
      assert Map.keys(fixture) |> Enum.sort() ==
               ~w(expectation id input operation requirements)

      assert Map.has_key?(@owners, fixture["operation"]), "unknown operation in #{fixture["id"]}"
      assert fixture["expectation"]["operator"] == "exact"
      assert Map.has_key?(fixture["expectation"], "value")
      assert fixture["requirements"] != []
    end
  end

  test "WBL-B03 executed cases name only operations bound to an asserting owner" do
    cases = Map.new(@corpus["cases"], &{&1["id"], &1})
    executed = @corpus["executed_cases"]
    assert executed == Enum.uniq(executed)
    assert Enum.all?(executed, &Map.has_key?(cases, &1))

    status =
      if length(executed) == map_size(cases), do: "executed", else: "partially_executed"

    assert @corpus["status"] == status

    for id <- executed do
      fixture = cases[id]
      assert {_, owner} = @owners[fixture["operation"]], "#{id} has no executable owner"
      source = File.read!(Path.join(@root, owner))

      assert String.contains?(source, ~s("#{fixture["operation"]}")) or
               String.contains?(source, id),
             "#{owner} does not select #{id}"

      assert String.contains?(source, ~s(["expectation"]["value"])),
             "#{owner} does not compare the corpus expectation"
    end

    for id <- Map.keys(cases) -- executed do
      refute @owners[cases[id]["operation"]], "#{id} has an owner but is not recorded as executed"
    end
  end
end
