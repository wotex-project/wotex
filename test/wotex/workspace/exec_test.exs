defmodule Wotex.Workspace.ExecTest do
  @moduledoc false

  # run/2 announces commands and reports missing executables with
  # Mix.shell(), which is global: the module swaps in Mix.Shell.Process and
  # runs synchronously. The commands are shell scripts in a temporary
  # directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Wotex.Workspace
  alias Wotex.Workspace.Exec
  alias Wotex.Workspace.NativeCache
  alias WotexWorkspace.Fixtures

  setup context do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{root: Fixtures.tmp_dir(context)}
  end

  defp script!(root, relative, body) do
    path = Fixtures.write!(root, relative, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  # Runs Exec.run/2 and returns its status with the output it streamed.
  defp run_captured(argv, opts) do
    output = capture_io(fn -> send(self(), {:status, Exec.run(argv, opts)}) end)
    assert_received {:status, status}
    {status, output}
  end

  describe "describe/3" do
    test "names the directory relative to the repository, then the environment and the command" do
      cd = Path.join(Workspace.root(), "packages/wotex-coap")

      assert Exec.describe(cd, ~w(cmake -S . -B build), [{"CC", "clang"}, {"CFLAGS", "-O2"}]) ==
               "packages/wotex-coap: CC=clang CFLAGS=-O2 cmake -S . -B build"

      assert Exec.describe(Workspace.root(), ~w(cargo test), []) == ".: cargo test"
    end

    test "shows an unset variable as -u NAME, as the package runner does" do
      assert Exec.describe("/opt/build", ["make"], [{"CC", "clang"}, {"MIX_ENV", nil}]) ==
               "/opt/build: CC=clang -u MIX_ENV make"
    end

    test "keeps a directory outside the repository absolute" do
      assert Exec.describe("/opt/build", ["make"], []) == "/opt/build: make"
    end
  end

  describe "resolve/2" do
    test "looks a bare name up on PATH, not in the directory", %{root: root} do
      sh = Exec.resolve("sh", root)
      assert Path.type(sh) == :absolute
      assert Path.basename(sh) == "sh"
      assert File.regular?(sh)

      script!(root, "wotex-exec-probe", "exit 0\n")
      assert Exec.resolve("wotex-exec-probe", root) == nil
    end

    test "expands a name containing / against the directory", %{root: root} do
      tool = script!(root, "bin/tool", "exit 0\n")

      assert Exec.resolve("bin/tool", root) == tool
      assert Exec.resolve("./bin/tool", root) == tool
      assert Exec.resolve(tool, "/") == tool
    end

    test "is nil for a missing file or a directory", %{root: root} do
      script!(root, "bin/tool", "exit 0\n")

      assert Exec.resolve("bin/missing", root) == nil
      assert Exec.resolve("./bin", root) == nil
    end
  end

  describe "run/2" do
    test "returns the exit status and streams output and errors", %{root: root} do
      script!(root, "bin/probe", "echo out\necho err >&2\nexit 3\n")

      assert {3, output} = run_captured(["bin/probe"], cd: root, quiet: true)
      assert output =~ "out\n"
      assert output =~ "err\n"

      script!(root, "bin/ok", "exit 0\n")
      assert {0, ""} = run_captured(["./bin/ok"], cd: root, quiet: true)
    end

    test "passes the arguments unchanged and runs in the directory", %{root: root} do
      script!(root, "bin/args", ~S(printf '%s|' "$@" > args.txt) <> "\n")

      assert {0, _} = run_captured(["bin/args", "one two", "", "*"], cd: root, quiet: true)
      assert File.read!(Path.join(root, "args.txt")) == "one two||*|"
    end

    test "runs in the current directory by default", %{root: root} do
      tool = script!(root, "bin/pwd", ~S(pwd -P > "$0.out") <> "\n")

      assert {0, _} = run_captured([tool], quiet: true)
      assert File.read!(tool <> ".out") == NativeCache.real_path(File.cwd!()) <> "\n"
    end

    test "sets and unsets environment variables", %{root: root} do
      System.put_env("WOTEX_EXEC_TEST_INHERITED", "parent")
      on_exit(fn -> System.delete_env("WOTEX_EXEC_TEST_INHERITED") end)

      script!(root, "bin/env", """
      echo "${WOTEX_EXEC_TEST_SET-unset}|${WOTEX_EXEC_TEST_INHERITED-unset}" > env.txt
      """)

      assert {0, _} = run_captured(["bin/env"], cd: root, quiet: true)
      assert File.read!(Path.join(root, "env.txt")) == "unset|parent\n"

      env = [{"WOTEX_EXEC_TEST_SET", "1"}, {"WOTEX_EXEC_TEST_INHERITED", nil}]
      assert {0, _} = run_captured(["bin/env"], cd: root, env: env, quiet: true)
      assert File.read!(Path.join(root, "env.txt")) == "1|unset\n"
    end

    test "with stdout: writes standard output to the file instead", %{root: root} do
      script!(root, "bin/probe", "echo line one\necho line two\nexit 4\n")
      out = Path.join(root, "logs/nested/out.txt")

      assert {4, ""} = run_captured(["bin/probe"], cd: root, stdout: out, quiet: true)
      assert File.read!(out) == "line one\nline two\n"
    end

    test "announces the command unless quiet", %{root: root} do
      script!(root, "bin/probe", "exit 0\n")
      argv = ["bin/probe", "--flag"]
      env = [{"A", "1"}]

      assert {0, _} = run_captured(argv, cd: root, env: env)
      assert_received {:mix_shell, :info, [announcement]}
      assert announcement == "==> " <> Exec.describe(root, argv, env)

      assert {0, _} = run_captured(argv, cd: root, env: env, quiet: true)
      refute_received {:mix_shell, :info, _}
    end

    test "a missing executable returns 127 and says so", %{root: root} do
      assert {127, ""} = run_captured(["wotex-no-such-command", "x"], cd: root, quiet: true)
      assert_received {:mix_shell, :error, ["wotex-no-such-command: command not found"]}

      assert {127, ""} = run_captured(["bin/missing"], cd: root, quiet: true)
      assert_received {:mix_shell, :error, ["bin/missing: command not found"]}
    end
  end
end
