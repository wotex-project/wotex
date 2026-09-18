defmodule Mix.Tasks.Wotex.Native.BenchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Native.Bench
  alias Wotex.Workspace.NativeBench

  defp bench(id, kind), do: %NativeBench{id: id, kind: kind, title: id, description: id}

  test "requires one package and absolute directories" do
    assert Bench.parse_args(~w(--package wotex-opcua)) == [package: "wotex-opcua"]

    assert Bench.parse_args(~w(--package p --bench a --bench b --workspace /w --output /o)) == [
             package: "p",
             bench: "a",
             bench: "b",
             workspace: "/w",
             output: "/o"
           ]

    assert_raise Mix.Error, "--package NAME is required", fn -> Bench.parse_args([]) end

    assert_raise Mix.Error, "--workspace must be an absolute directory", fn ->
      Bench.parse_args(~w(--package p --workspace rel))
    end

    assert_raise Mix.Error, "--output must be an absolute directory", fn ->
      Bench.parse_args(~w(--package p --output rel))
    end

    assert_raise Mix.Error, fn -> Bench.parse_args(~w(--package p --all)) end

    assert_raise Mix.Error, ~r/unexpected arguments: x/, fn ->
      Bench.parse_args(~w(--package p x))
    end
  end

  test "selects benchmarks by id in manifest order" do
    benches = [bench("a", :nanobench), bench("b", :criterion), bench("c", :elixir)]

    assert Bench.select(benches, []) == {:ok, benches}
    assert {:ok, [%{id: "a"}, %{id: "c"}]} = Bench.select(benches, ~w(c a c))

    assert Bench.select(benches, ~w(a x)) ==
             {:error, "unknown native_bench x; known: a, b, c"}

    assert Bench.select([], []) == {:error, "no native_bench in tooling/packages.yaml"}
  end

  test "says when elixir benchmarks are skipped for want of a workspace" do
    benches = [bench("a", :nanobench), bench("c", :elixir)]

    assert Bench.skip_notice(benches, nil) =~
             "1 elixir benchmark(s) need the package's native build"

    assert Bench.skip_notice(benches, nil) =~ "running the nanobench and criterion benchmarks only"
    assert Bench.skip_notice(benches, "/w") == nil
    assert Bench.skip_notice([bench("a", :nanobench)], nil) == nil
  end
end
