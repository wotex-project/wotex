defmodule Mix.Tasks.Wotex.Native.SuiteTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Suite

  test "takes a package, a suite and one of --tidy and --test" do
    assert Suite.parse_args(
             ~w(--package wotex-ble --suite libdbus --tidy --exclude a.c --exclude b.c --result /r.json)
           ) == [
             package: "wotex-ble",
             suite: "libdbus",
             tidy: true,
             exclude: "a.c",
             exclude: "b.c",
             result: "/r.json"
           ]

    assert Suite.parse_args(
             ~w(--package wotex-thread --suite openthread --test --workspace /tmp/ws)
           ) ==
             [package: "wotex-thread", suite: "openthread", test: true, workspace: "/tmp/ws"]
  end

  test "rejects a missing package, suite or mode and a relative workspace" do
    for {args, message} <- [
          {~w(--suite s --test), ~r/--package/},
          {~w(--package p --test), ~r/--suite/},
          {~w(--package p --suite s), ~r/exactly one/},
          {~w(--package p --suite s --tidy --test), ~r/exactly one/},
          {~w(--package p --suite s --test --workspace rel), ~r/absolute/}
        ] do
      assert_raise Mix.Error, message, fn -> Suite.parse_args(args) end
    end
  end
end
