defmodule Mix.Tasks.Wotex.Native.InspectTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Inspect

  test "requires one package unless repository-wide inspection is explicit" do
    assert Inspect.parse_args(~w(--package wotex-ble --profile production --json)) ==
             [package: "wotex-ble", profile: "production", json: true]

    assert Inspect.parse_args(~w(--all)) == [all: true]
    assert_raise Mix.Error, ~r/--package NAME is required/, fn -> Inspect.parse_args([]) end

    assert_raise Mix.Error, ~r/mutually exclusive/, fn ->
      Inspect.parse_args(~w(--all --package x))
    end
  end

  test "identity inspection requires one explicit cell" do
    assert_raise Mix.Error, ~r/requires --profile and --target/, fn ->
      Inspect.parse_args(~w(--package x --identity))
    end

    assert_raise Mix.Error, ~r/--target requires --profile/, fn ->
      Inspect.parse_args(~w(--package x --target linux))
    end
  end

  test "human output exposes support and the authoritative full identity" do
    identity = String.duplicate("a", 64)

    assert Inspect.render([
             %{
               "package" => "native",
               "profile" => "production",
               "kind" => "executable",
               "targets" => [
                 %{"name" => "linux", "status" => "supported", "reason" => nil},
                 %{"name" => "device", "status" => "unsupported", "reason" => "no runner"}
               ],
               "build_identity" => identity
             }
           ]) ==
             "native/production  executable  linux, device (unsupported: no runner)  #{identity}"
  end
end
