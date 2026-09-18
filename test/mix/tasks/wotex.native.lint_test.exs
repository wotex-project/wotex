defmodule Mix.Tasks.Wotex.Native.LintTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Lint

  test "takes the selection switches, --fix, --tidy, --no-format and --no-clippy" do
    assert Lint.parse_args(~w(--all --base main --fix)) == [all: true, base: "main", fix: true]

    assert Lint.parse_args(~w(--package wotex-opcua --tidy --no-format --no-clippy)) ==
             [package: "wotex-opcua", tidy: true, format: false, clippy: false]

    assert Lint.parse_args(~w(--tidy --package wotex-opcua --workspace /tmp/ws)) ==
             [tidy: true, package: "wotex-opcua", workspace: "/tmp/ws"]
  end

  test "rejects inconsistent switches" do
    assert_raise Mix.Error, ~r/--workspace needs --tidy/, fn ->
      Lint.parse_args(~w(--package wotex-opcua --workspace /tmp/ws))
    end

    assert_raise Mix.Error, ~r/absolute/, fn ->
      Lint.parse_args(~w(--tidy --package wotex-opcua --workspace ws))
    end

    assert_raise Mix.Error, ~r/exactly one --package/, fn ->
      Lint.parse_args(~w(--tidy --all --workspace /tmp/ws))
    end

    assert_raise Mix.Error, ~r/--fix applies formatting/, fn ->
      Lint.parse_args(~w(--fix --tidy))
    end

    assert_raise Mix.Error, fn -> Lint.parse_args(~w(--lane current)) end
  end

  test "runs format and clippy by default and clang-tidy with --tidy" do
    both = %{c_family: true, rust: true}
    assert Lint.steps(both, []) == ["clang-format", "rustfmt", "clippy"]
    assert Lint.steps(both, tidy: true, format: false) == ["clippy", "clang-tidy"]
    assert Lint.steps(%{c_family: true, rust: false}, clippy: false) == ["clang-format"]
    assert Lint.steps(%{c_family: false, rust: true}, tidy: true) == ["rustfmt", "clippy"]
  end
end
