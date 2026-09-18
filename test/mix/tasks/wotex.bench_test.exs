defmodule Mix.Tasks.Wotex.BenchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Bench
  alias WotexWorkspace.Fixtures

  test "takes the selection switches" do
    assert Bench.parse_args(~w(--package wotex --base main)) == [package: "wotex", base: "main"]
    assert Bench.parse_args(~w(--all)) == [all: true]
    assert_raise Mix.Error, fn -> Bench.parse_args(~w(--fix)) end
    assert_raise Mix.Error, ~r/unexpected arguments: x/, fn -> Bench.parse_args(~w(x)) end
  end

  test "finds the benchmark scripts of a package, sorted and relative to it" do
    root = Fixtures.tmp_dir("bench")
    assert Bench.scripts(root) == []

    Fixtures.write!(root, "bench/values_bench.exs", "")
    Fixtures.write!(root, "bench/codec_bench.exs", "")
    Fixtures.write!(root, "bench/support.exs", "")
    Fixtures.write!(root, "bench/output/codec.md", "")

    assert Bench.scripts(root) == ["bench/codec_bench.exs", "bench/values_bench.exs"]
  end

  test "runs each script with mix run in the dev environment" do
    assert Bench.steps(["bench/codec_bench.exs", "bench/values_bench.exs"]) == [
             {"codec", ["run", "bench/codec_bench.exs"], [mix_env: "dev"]},
             {"values", ["run", "bench/values_bench.exs"], [mix_env: "dev"]}
           ]
  end
end
