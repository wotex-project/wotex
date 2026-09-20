defmodule Mix.Tasks.Wotex.Native.PlanTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Plan

  test "accepts bounded selection and output switches" do
    assert Plan.parse_args(~w(--base main --package one --package two --limit 8 --json)) == [
             base: "main",
             package: "one",
             package: "two",
             limit: 8,
             json: true
           ]

    assert_raise Mix.Error, ~r/mutually exclusive/, fn -> Plan.parse_args(~w(--json --count)) end
  end

  test "renders count, canonical JSON and explicit fallback" do
    cell = %{
      package: "native",
      profile: "production",
      target: "linux",
      toolchain: "compiler",
      system: "host",
      status: :supported,
      reason: nil
    }

    plan = %{cells: [cell], slices: [[cell]], fallback: true, fallback_reason: "no base"}

    assert Plan.render(plan, count: true) == "1"
    assert Plan.render(plan, []) =~ "fallback: no base"

    json = Plan.render(plan, json: true)
    assert {:ok, decoded} = JSON.decode(json)
    assert decoded["schema"] == "wotex.native-plan@1"
    assert decoded["count"] == 1
    assert decoded["fallback"]
  end
end
