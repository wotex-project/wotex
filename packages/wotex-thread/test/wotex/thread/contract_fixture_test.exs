defmodule Wotex.Thread.ContractFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag requirements: ["WTH-N04"]
  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus

  # Every corpus case is either bound to the executable test that compares its
  # actual observation, or explicitly unexecuted with the package that owns it.
  @bindings %{
    "WTH-F01" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"},
    "WTH-F02" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"},
    "WTH-F03" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"},
    "WTH-F04" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"},
    "WTH-F05" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"},
    "WTH-F06" => {:executed, "test/wotex/thread/daemon_fault_test.exs"},
    "WTH-F07" => {:unexecuted, "WTH-P04"},
    "WTH-F08" => {:unexecuted, "WTH-P04"},
    "WTH-F09" => {:executed, "test/wotex/thread/native_contract_test.exs"},
    "WTH-F10" => {:executed, "test/wotex/thread/dataset_boundary_test.exs"}
  }
  @operations %{
    "Dataset.decode" => "pure",
    "daemon_fragmented_state" => "lifecycle_contract",
    "management_callback_acceptance" => "lifecycle_contract",
    "management_timeout_late_callback" => "lifecycle_contract",
    "state_coalescing" => "lifecycle_contract"
  }

  test "WTH-N04 the concrete corpus has an exact format, operations and expectations" do
    corpus = Jason.decode!(File.read!(@corpus))

    assert Map.keys(corpus) |> Enum.sort() ==
             ~w(cases format_version normalization_spec package status)

    assert corpus["format_version"] == "1.0.0"
    assert corpus["package"] == "wotex_thread"
    assert corpus["status"] == "specified_unexecuted"
    ids = Enum.map(corpus["cases"], & &1["id"])
    assert ids == Enum.map(1..10, &"WTH-F#{String.pad_leading(Integer.to_string(&1), 2, "0")}")

    for item <- corpus["cases"] do
      assert Map.keys(item) |> Enum.sort() == ~w(expectation id input kind operation requirements),
             item["id"]

      assert Map.fetch!(@operations, item["operation"]) == item["kind"], item["id"]
      assert %{"operator" => "exact", "value" => _} = item["expectation"]
      assert map_size(item["expectation"]) == 2

      assert item["requirements"] != [] and
               Enum.all?(item["requirements"], &(&1 =~ ~r/\AWTH-[SN]\d\d\z/))
    end
  end

  test "WTH-N04 every case is bound to its executing test or explicitly unexecuted" do
    corpus = Jason.decode!(File.read!(@corpus))
    assert Map.keys(@bindings) |> Enum.sort() == Enum.map(corpus["cases"], & &1["id"])

    for {id, {:executed, path}} <- @bindings do
      source = File.read!(Path.expand("../../../#{path}", __DIR__))
      case_item = Enum.find(corpus["cases"], &(&1["id"] == id))

      # Pure Dataset cases are generated per corpus entry; the daemon case names its ID.
      assert String.contains?(source, id) or
               (case_item["operation"] == "Dataset.decode" and
                  String.contains?(source, ~s(fixture["operation"] == "Dataset.decode"))),
             id
    end

    assert for({id, {:unexecuted, _}} <- @bindings, do: id) |> Enum.sort() ==
             ~w(WTH-F07 WTH-F08)
  end
end
