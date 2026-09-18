defmodule Wotex.Workspace.NativeCheckTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Workspace.NativeCheck
  alias Wotex.Workspace.NativeSuite
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, "packages/p/native/a.c", "int a;\n")
    Fixtures.write!(root, "packages/p/native/a.h", "int a;\n")
    Fixtures.write!(root, "packages/p/test/native/t.cpp", "int t;\n")

    context = %{
      name: "p",
      root: root,
      dir: Path.join(root, "packages/p"),
      relative: "packages/p",
      suites: [],
      files: [],
      sources: ~w(packages/p/native/a.c packages/p/native/a.h packages/p/test/native/t.cpp),
      crates: ["packages/p/crate/Cargo.toml"],
      cache: Path.join(root, "cache")
    }

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{check: context}
  end

  test "selects package-relative translation units by glob", %{check: check} do
    assert NativeCheck.matching(check, ["native/*.c"]) == ["native/a.c"]

    assert NativeCheck.matching(check, ["native/**", "test/**/*.cpp"]) == [
             "native/a.c",
             "test/native/t.cpp"
           ]

    assert NativeCheck.matching(check, ["native/*.h"]) == []
    assert NativeCheck.kinds(check) == %{c_family: true, rust: true}
  end

  test "reports unmet host requirements" do
    suite = %NativeSuite{name: "sdk", requires: ["linux", "docker"]}

    probe = fn
      "linux" -> {:error, "requires Linux (this host is darwin)"}
      "docker" -> :ok
    end

    assert NativeCheck.unmet(suite, probe) == ["requires Linux (this host is darwin)"]
    assert NativeCheck.unmet(%NativeSuite{name: "x"}, probe) == []
  end

  test "builds cargo arguments with the target directory in the cache", %{check: check} do
    manifest = "packages/p/crate/Cargo.toml"
    target = Path.join(check.cache, "p/cargo")

    assert NativeCheck.cargo_args(check, :fmt, manifest) ==
             ["cargo", "fmt", "--manifest-path", manifest, "--check"]

    assert NativeCheck.cargo_args(check, :fmt, manifest, fix: true) == [
             "cargo",
             "fmt",
             "--manifest-path",
             manifest
           ]

    clippy = ~w(cargo clippy --manifest-path #{manifest} --locked --all-targets --all-features)

    assert NativeCheck.cargo_args(check, :clippy, manifest) ==
             clippy ++ ["--target-dir", target, "--", "-D", "warnings"]

    assert NativeCheck.cargo_args(check, :test, manifest) ==
             ~w(cargo test --manifest-path #{manifest} --locked --all-features --target-dir #{target})
  end

  test "runs a suite's test commands with placeholders and fails on the first failure", %{
    check: check
  } do
    passing = %NativeSuite{
      name: "unit",
      test: [%{run: ["sh", "-c", "echo ok > {scratch}/ran"], env: [], cd: nil, stdout: nil}]
    }

    assert NativeCheck.test(%{check | suites: [passing]}) == :ok
    assert File.read!(Path.join(check.cache, "p/unit/scratch/ran")) == "ok\n"

    failing = %NativeSuite{
      name: "unit",
      test: [
        %{run: ["sh", "-c", "exit 3"], env: [], cd: nil, stdout: nil},
        %{run: ["sh", "-c", "touch {scratch}/never"], env: [], cd: nil, stdout: nil}
      ]
    }

    assert NativeCheck.test(%{check | suites: [failing]}) == :error
    assert_received {:mix_shell, :error, [message]}
    assert message =~ "p suite unit: test command `sh -c exit 3` failed (3)"
    refute File.exists?(Path.join(check.cache, "p/unit/scratch/never"))

    blocked = %NativeSuite{name: "linux-only", requires: ["linux"]}

    if :os.type() != {:unix, :linux} do
      assert NativeCheck.test(%{check | suites: [blocked]}) == :error
      assert_received {:mix_shell, :error, [message]}
      assert message =~ "p suite linux-only requires Linux"
    end
  end

  test "clang-tidy fails when a translation unit has no compile command", %{check: check} do
    tool = %{tool: :clang_tidy, path: "/nonexistent/clang-tidy", version: "23", major: 23}
    assert NativeCheck.tidy(check, tool: tool) == :error

    messages = for {:mix_shell, :error, [message]} <- flush(), do: message
    assert Enum.any?(messages, &(&1 =~ "no compile command for 2 translation unit(s)"))
    assert "  packages/p/native/a.c" in messages
    assert "  packages/p/test/native/t.cpp" in messages
    assert File.exists?(Path.join(check.cache, "p/tidy/compile_commands.json"))
  end

  test "writes stdout of a prepare command to a file and synthesizes compile commands", %{
    check: check
  } do
    suite = %NativeSuite{
      name: "db",
      prepare: [
        %{run: ["sh", "-c", "echo generated"], env: [], cd: nil, stdout: "{scratch}/out.txt"}
      ],
      compile: [%{files: ["native/*.c", "test/native/*.cpp"], flags: ["-I{scratch}"]}]
    }

    # A stand-in for clang-tidy that records its arguments and reports nothing.
    fake = Fixtures.write!(check.root, "bin/fake-tidy", "#!/bin/sh\necho \"$@\" >> \"$0.args\"\n")
    File.chmod!(fake, 0o755)
    tool = %{tool: :clang_tidy, path: fake, version: "23", major: 23}

    assert NativeCheck.tidy(%{check | suites: [suite]}, tool: tool) == :ok
    calls = String.split(File.read!(fake <> ".args"), "\n", trim: true)
    assert length(calls) == 2

    assert Enum.all?(
             calls,
             &(&1 =~ "--quiet --config-file=" <> Path.join(check.root, ".clang-tidy"))
           )

    assert Enum.any?(calls, &String.starts_with?(&1, "packages/p/native/a.c "))

    scratch = Path.join(check.cache, "p/db/scratch")
    assert File.read!(Path.join(scratch, "out.txt")) == "generated\n"

    {:ok, entries} =
      Wotex.Workspace.CompileDb.read(Path.join(check.cache, "p/tidy/compile_commands.json"))

    assert Enum.map(entries, &Path.basename(&1["file"])) == ["a.c", "t.cpp"]
    assert Enum.all?(entries, &(("-I" <> scratch) in &1["arguments"]))
  end

  defp flush do
    receive do
      message -> [message | flush()]
    after
      0 -> []
    end
  end
end
