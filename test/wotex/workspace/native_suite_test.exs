defmodule Wotex.Workspace.NativeSuiteTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeSuite

  @suite %{
    "suite" => "sdk",
    "requires" => ["linux"],
    "build" => "p.native.build",
    "prepare" => [["cmake", "-S", "{package}/native", "-B", "{scratch}/db"]],
    "compile_commands" => ["{scratch}/db/compile_commands.json"],
    "compile" => [%{"files" => ["test/*.c"], "flags" => ["-std=c11", "-I{workspace}/include"]}],
    "test" => [
      ["ctest", "--test-dir", "{workspace}/build"],
      %{
        "run" => ["mix", "test"],
        "env" => %{"W" => "{workspace}"},
        "cd" => "{root}",
        "stdout" => "{scratch}/out"
      }
    ]
  }

  test "parses a suite" do
    assert {:ok, [suite]} = NativeSuite.parse_all("p", [@suite])
    assert suite.name == "sdk"
    assert suite.requires == ["linux"]
    assert suite.build == "p.native.build"
    assert [%{run: ["cmake" | _], env: [], cd: nil, stdout: nil}] = suite.prepare
    assert suite.compile == [%{files: ["test/*.c"], flags: ["-std=c11", "-I{workspace}/include"]}]

    assert [
             _,
             %{
               run: ["mix", "test"],
               env: [{"W", "{workspace}"}],
               cd: "{root}",
               stdout: "{scratch}/out"
             }
           ] =
             suite.test

    assert NativeSuite.parse_all("p", nil) == {:ok, []}
  end

  test "rejects malformed suites with the package and suite named" do
    assert {:error, "package p: native_check must be a list"} = NativeSuite.parse_all("p", %{})

    assert {:error, "package p: every native_check entry needs a suite name"} =
             NativeSuite.parse_all("p", [%{}])

    for {change, expected} <- [
          {%{"requires" => ["windows"]}, "unknown requirement(s) windows"},
          {%{"build" => 3}, "build must be a task name"},
          {%{"extra" => 1}, "unknown key(s) extra"},
          {%{"prepare" => [[]]}, "prepare has an empty command"},
          {%{"test" => [%{"run" => ["x"], "env" => %{"A" => 1}}]},
           "test env must map names to strings"},
          {%{"compile" => [%{"files" => []}]}, "compile entries need files and flags"},
          {%{"compile" => [%{"files" => [], "flags" => []}]}, "compile files must not be empty"},
          {%{"compile_commands" => ["{nope}/db.json"]}, "unknown placeholder(s) {nope}"},
          {%{"build" => nil}, "{workspace} needs a build task"}
        ] do
      assert {:error, message} =
               NativeSuite.parse("p", Map.reject(Map.merge(@suite, change), &is_nil(elem(&1, 1))))

      assert message =~ "package p, native_check suite sdk"
      assert message =~ expected
    end

    assert {:error, "package p: duplicate native_check suite sdk"} =
             NativeSuite.parse_all("p", [@suite, @suite])
  end

  test "parses a container and requires docker for it" do
    container = %{
      "dockerfile" => "tooling/native/docker/sdk.Dockerfile",
      "platform" => "linux/amd64",
      "volumes" => ["{workspace}:/work", "{package}/native:/work/sdk/native/"]
    }

    entry = %{@suite | "requires" => ["docker"]} |> Map.put("container", container)
    assert {:ok, suite} = NativeSuite.parse("p", entry)

    assert suite.container == %{
             dockerfile: "tooling/native/docker/sdk.Dockerfile",
             platform: "linux/amd64",
             volumes: [{"{workspace}", "/work"}, {"{package}/native", "/work/sdk/native"}]
           }

    assert {:ok, %{container: %{platform: nil, volumes: []}}} =
             NativeSuite.parse("p", Map.put(entry, "container", %{"dockerfile" => "d"}))

    assert {:ok, %{container: nil}} = NativeSuite.parse("p", @suite)

    for {change, expected} <- [
          {%{"requires" => ["linux"]}, "container needs requires: [docker]"},
          {%{"container" => ["x"]}, "container must be a mapping with a dockerfile"},
          {%{"container" => %{"dockerfile" => "d", "extra" => 1}}, "unknown key(s) extra"},
          {%{"container" => %{"dockerfile" => "d", "volumes" => ["/a"]}},
           ~s(volume "/a" must be HOST:/absolute/container/path)},
          {%{"container" => %{"dockerfile" => "d", "volumes" => ["{x}:/a"]}},
           "unknown placeholder(s) {x}"}
        ] do
      assert {:error, message} = NativeSuite.parse("p", Map.merge(entry, change))
      assert message =~ expected
    end
  end

  test "expands placeholders and leaves unknown braces alone" do
    values = %{
      "package" => "/r/packages/p",
      "workspace" => "/c/ws",
      "scratch" => "/c/s",
      "root" => "/r"
    }

    assert NativeSuite.expand("-I{workspace}/include {other}", values) == "-I/c/ws/include {other}"

    command = %{
      run: ["{package}/x", "{scratch}"],
      env: [{"W", "{workspace}"}],
      cd: "{root}",
      stdout: nil
    }

    assert NativeSuite.expand_command(command, values) ==
             %{run: ["/r/packages/p/x", "/c/s"], env: [{"W", "/c/ws"}], cd: "/r", stdout: nil}
  end

  test "the repository manifest declares valid suites for the native C and C++ packages" do
    manifest = Manifest.load!()

    for name <-
          ~w(wotex-bacnet wotex-ble wotex-coap wotex-matter wotex-modbus wotex-opcua wotex-thread) do
      assert [_ | _] = Manifest.fetch!(name, manifest).native_check,
             "#{name} has no native_check suite"
    end

    assert Manifest.fetch!("wotex-lab", manifest).native_check == []
    assert NativeSuite.requirements() == ~w(linux docker)

    # Every suite container is built from a Dockerfile of tooling/native/docker.
    for package <- Manifest.packages(manifest),
        %{container: %{dockerfile: dockerfile}} <- package.native_check do
      assert dockerfile =~ ~r{^tooling/native/docker/[a-z0-9-]+\.Dockerfile$}
      assert File.regular?(Path.join(Wotex.Workspace.root(), dockerfile))
    end
  end
end
