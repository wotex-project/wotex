defmodule Mix.Tasks.Wotex.Native.TestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Test

  test "takes the selection switches and a workspace for one package" do
    assert Test.parse_args(~w(--package wotex-lab)) == [package: "wotex-lab"]

    assert Test.parse_args(~w(--package wotex-opcua --workspace /tmp/ws)) ==
             [package: "wotex-opcua", workspace: "/tmp/ws"]

    assert_raise Mix.Error, ~r/exactly one --package/, fn ->
      Test.parse_args(~w(--workspace /tmp/ws))
    end

    assert_raise Mix.Error, ~r/absolute/, fn -> Test.parse_args(~w(--package p --workspace rel)) end
  end

  test "runs cargo test before each native suite" do
    assert Test.steps(["a/Cargo.toml"], ~w(portable sdk)) ==
             ["cargo test", "suite portable", "suite sdk"]
  end
end
