defmodule Wotex.BLE.ContractFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.{Address, UUID, Value}

  @fixture_path Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @fixture_path
  @corpus Jason.decode!(File.read!(@fixture_path))
  @root Path.expand("../../..", __DIR__)
  @p01_ids ~w(WBL-F01 WBL-F02 WBL-F03 WBL-F04 WBL-F05 WBL-F09 WBL-F10)
  @cases Enum.filter(@corpus["cases"], &(&1["id"] in @p01_ids))

  # Pure cases execute in this file. Lifecycle cases need the private-bus native
  # lane and execute in its explicitly selected interop test.
  @owners %{
    "pure" => "test/wotex/ble/contract_fixture_test.exs",
    "lifecycle_contract" => "test/interop/native_bus_test.exs"
  }

  test "WBL-N04 P01 executes its exact assigned concrete case set" do
    assert @corpus["format_version"] == "1.0.0"
    assert @corpus["status"] == "executed"
    assert Enum.sort(Enum.map(@cases, & &1["id"])) == Enum.sort(@p01_ids)
    assert Enum.all?(@cases, &(&1["kind"] == "pure"))
  end

  test "WBL-N04 every corpus case has an executing owner that compares its expectation" do
    ids = Enum.map(@corpus["cases"], & &1["id"])
    assert ids == Enum.uniq(ids)

    for fixture <- @corpus["cases"] do
      assert Map.keys(fixture) |> Enum.sort() ==
               ~w(expectation id input kind operation requirements)

      assert fixture["expectation"]["operator"] == "exact"
      assert owner = @owners[fixture["kind"]], "#{fixture["id"]} has an unknown kind"
      assert fixture["kind"] != "pure" or fixture["id"] in @p01_ids
      source = File.read!(Path.join(@root, owner))

      assert String.contains?(source, fixture["operation"]),
             "#{owner} does not select #{fixture["id"]}"

      assert String.contains?(source, ~s(["expectation"]["value"])),
             "#{owner} does not compare #{fixture["id"]}"
    end
  end

  for fixture <- @cases do
    test "#{fixture["id"]} WBL-S01 WBL-N04 exact input and expected observation" do
      fixture = unquote(Macro.escape(fixture))
      assert fixture["expectation"]["operator"] == "exact"
      assert execute(fixture["operation"], fixture["input"]) == fixture["expectation"]["value"]
    end
  end

  defp execute("UUID.normalize", %{"value" => value}), do: result(UUID.normalize(value))
  defp execute("UUID.decode", %{"bytes_hex" => bytes}), do: result(UUID.decode(hex(bytes)))
  defp execute("UUID.encode", %{"value" => value}), do: byte_result(UUID.encode(value))
  defp execute("Address.from_topic", %{"value" => value}), do: result(Address.from_topic(value))

  defp execute("Value.decode", %{"bytes_hex" => bytes, "type" => type, "options" => options}),
    do: result(Value.decode(hex(bytes), type(type), options(options)))

  defp execute("Value.encode", %{"value" => value, "type" => type, "options" => options}),
    do: byte_result(Value.encode(value, type(type), options(options)))

  defp result({:ok, value}), do: %{"ok" => value}

  defp result({:error, error}),
    do: %{
      "error" => %{"code" => Atom.to_string(error.code), "effect" => Atom.to_string(error.effect)}
    }

  defp byte_result({:ok, bytes}),
    do: %{"ok" => %{"bytes_hex" => Base.encode16(bytes, case: :lower)}}

  defp byte_result({:error, _} = error), do: result(error)
  defp hex(bytes), do: Base.decode16!(bytes, case: :lower)

  defp type(type),
    do: Map.fetch!(%{"uint16" => :uint16, "int16" => :int16, "boolean" => :boolean}, type)

  defp options(options) when map_size(options) == 0, do: []

  defp options(%{"byte_order" => "little"} = options) when map_size(options) == 1,
    do: [byte_order: :little]
end
