defmodule Wotex.BLE.ContractFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.{Address, UUID, Value}

  @fixture_path Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @external_resource @fixture_path
  @corpus Jason.decode!(File.read!(@fixture_path))
  @p01_ids ~w(WBL-F01 WBL-F02 WBL-F03 WBL-F04 WBL-F05 WBL-F09 WBL-F10)
  @cases Enum.filter(@corpus["cases"], &(&1["id"] in @p01_ids))

  test "WBL-N04 P01 executes its exact assigned concrete case set" do
    assert @corpus["format_version"] == "1.0.0"
    assert Enum.sort(Enum.map(@cases, & &1["id"])) == Enum.sort(@p01_ids)
    assert Enum.all?(@cases, &(&1["kind"] == "pure"))
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
