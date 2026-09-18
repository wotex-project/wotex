defmodule Mix.Tasks.Wotex.Native.BuildTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Build

  test "requires --package and an absolute --workspace" do
    assert Build.parse_args(~w(--package wotex-coap --workspace /tmp/ws)) ==
             [package: "wotex-coap", workspace: "/tmp/ws"]

    assert_raise Mix.Error, ~r/--package NAME is required/, fn ->
      Build.parse_args(~w(--workspace /tmp/ws))
    end

    assert_raise Mix.Error, ~r/--workspace/, fn -> Build.parse_args(~w(--package wotex-coap)) end
  end
end
