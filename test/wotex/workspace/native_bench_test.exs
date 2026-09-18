defmodule Wotex.Workspace.NativeBenchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeBench
  alias Wotex.Workspace.NativeSuite

  @nanobench %{
    "bench" => "queue",
    "kind" => "nanobench",
    "title" => "Bounded queue",
    "description" => "Admission and drain.\n",
    "requires" => ["linux"],
    "env" => %{"FIXTURES" => "{package}/priv/fixtures"},
    "compile" => [
      %{"files" => ["bench/native/queue.cpp"], "flags" => ["-std=c++17", "-I{package}/native"]},
      %{"files" => ["native/queue.c", "native/vendor/*.c"], "flags" => ["-std=c11"]}
    ],
    "link" => ["-lm", "pkg-config:openssl"]
  }

  test "parses a nanobench benchmark" do
    assert {:ok, [bench]} = NativeBench.parse_all("p", [@nanobench])

    assert %NativeBench{
             id: "queue",
             kind: :nanobench,
             title: "Bounded queue",
             description: "Admission and drain.",
             requires: ["linux"],
             env: [{"FIXTURES", "{package}/priv/fixtures"}],
             link: ["-lm", "pkg-config:openssl"]
           } = bench

    assert [%{files: ["bench/native/queue.cpp"], flags: ["-std=c++17", "-I{package}/native"]}, _] =
             bench.compile

    assert NativeBench.source(bench) == "bench/native/queue.cpp"
    assert NativeBench.report(bench) == "native-queue.md"
    assert NativeBench.parse_all("p", nil) == {:ok, []}
  end

  test "places each kind's source below bench/native" do
    criterion = %{"bench" => "codec", "kind" => "criterion", "title" => "T", "description" => "D"}
    elixir = %{criterion | "bench" => "sdk_path", "kind" => "elixir"}

    elixir =
      Map.put(elixir, "env", %{"WOTEX_P_NATIVE_WORKSPACE" => "{workspace}", "S" => "{scratch}"})

    assert {:ok, [criterion, elixir]} = NativeBench.parse_all("p", [criterion, elixir])
    assert NativeBench.source(criterion) == "bench/native/codec/Cargo.toml"
    assert NativeBench.source(elixir) == "bench/native/sdk_path_bench.exs"
    assert NativeBench.report(elixir) == "native-sdk_path.md"
    assert elixir.env == [{"S", "{scratch}"}, {"WOTEX_P_NATIVE_WORKSPACE", "{workspace}"}]
    assert NativeBench.kinds() == ~w(criterion elixir nanobench)
  end

  test "rejects malformed benchmarks with the package and benchmark named" do
    assert {:error, "package p: native_bench must be a list"} = NativeBench.parse_all("p", %{})

    assert {:error, "package p: every native_bench entry needs a bench id"} =
             NativeBench.parse_all("p", [%{"kind" => "nanobench"}])

    for {change, expected} <- [
          {%{"bench" => "Queue"}, "the bench id must be lowercase letters, digits and underscores"},
          {%{"kind" => "gbench"}, "kind must be one of criterion, elixir, nanobench"},
          {%{"extra" => 1}, "unknown key(s) extra"},
          {%{"title" => " "}, "title must be a non-empty string"},
          {%{"description" => nil}, "description must be a non-empty string"},
          {%{"requires" => ["windows"]}, "unknown requirement(s) windows"},
          {%{"env" => %{"A" => 1}}, "env must map names to strings"},
          {%{"link" => [""]}, "link must be a list of strings"},
          {%{"compile" => [%{"files" => ["native/queue.c"], "flags" => []}]},
           "compile must include the driver bench/native/queue.cpp"},
          {%{"compile" => [%{"files" => ["bench/native/*.cpp"], "flags" => ["-I{nope}"]}]},
           "unknown placeholder(s) {nope}"},
          {%{"env" => %{"W" => "{workspace}"}}, "{workspace} is available to the elixir kind only"}
        ] do
      assert {:error, message} = NativeBench.parse("p", Map.merge(@nanobench, change))
      assert message =~ "package p, native_bench "
      assert message =~ expected
    end

    # compile and link belong to the nanobench kind.
    criterion = %{"bench" => "c", "kind" => "criterion", "title" => "T", "description" => "D"}

    assert {:error, "package p, native_bench c: unknown key(s) compile"} =
             NativeBench.parse("p", Map.put(criterion, "compile", []))

    assert {:error, "package p: duplicate native_bench queue"} =
             NativeBench.parse_all("p", [@nanobench, @nanobench])
  end

  test "a driver glob satisfies the driver rule" do
    entry = %{@nanobench | "compile" => [%{"files" => ["bench/native/*.cpp"], "flags" => []}]}
    assert {:ok, _} = NativeBench.parse("p", entry)
  end

  test "gives clang-tidy one compile-only suite per nanobench driver" do
    {:ok, [bench]} = NativeBench.parse_all("p", [@nanobench])
    criterion = %NativeBench{id: "c", kind: :criterion, title: "T", description: "D"}

    assert [%NativeSuite{} = suite] = NativeBench.tidy_suites([bench, criterion])
    assert suite.name == "bench-queue"
    assert suite.name == NativeBench.suite_name(bench)
    assert suite.requires == ["linux"]
    assert suite.build == nil

    # Only the files below bench/native: the package's suites cover its sources.
    assert suite.compile == [
             %{
               files: ["bench/native/queue.cpp"],
               flags: NativeBench.default_flags() ++ ["-std=c++17", "-I{package}/native"]
             }
           ]

    assert NativeBench.default_flags() == [
             "-O2",
             "-DNDEBUG",
             "-isystem{root}/tooling/native/nanobench"
           ]
  end

  test "the repository's benchmarks name existing sources and the vendored nanobench" do
    root = Workspace.root()
    manifest = Manifest.load!()
    assert File.regular?(Path.join([root, NativeBench.nanobench_dir(), "nanobench.h"]))

    benches =
      for package <- Manifest.packages(manifest), bench <- package.native_bench do
        path = Path.join([root, "packages", package.name, NativeBench.source(bench)])
        assert File.regular?(path), "#{package.name}: #{NativeBench.source(bench)} is missing"
        {package.name, bench.id}
      end

    assert {"wotex-opcua", "output_queue"} in benches
  end
end
