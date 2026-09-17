defmodule Wotex.Thread.NativeTasksTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Mix.Tasks.Wotex.Thread.Native.Build, as: NativeBuildTask
  alias Mix.Tasks.Wotex.Thread.Software.Build, as: SoftwareBuildTask
  alias Mix.Tasks.Wotex.Thread.Software.Run, as: SoftwareRunTask
  alias Wotex.Thread.BuildFixture
  alias Wotex.Thread.Software.Build

  @moduletag requirements: ["WTH-B01", "WTH-B03"]

  setup do
    root = Path.join(File.cwd!(), ".wotex-thread-tasks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)
      File.rm_rf!(root)
    end)

    %{root: root, workspace: Path.join(root, "workspace")}
  end

  test "WTH-B01 the native build task reports its workspace, executable and manifest", context do
    environment = BuildFixture.environment(context.root)
    workspace = context.workspace

    assert :ok = NativeBuildTask.run(["--workspace", workspace], environment)
    assert_received {:mix_shell, :info, ["Native build completed: " <> ^workspace]}
    executable = Path.join(workspace, "build/wotex-thread-host")
    assert_received {:mix_shell, :info, ["Executable: " <> ^executable]}
    manifest = Path.join(workspace, "native-manifest.json")
    assert_received {:mix_shell, :info, ["Manifest: " <> ^manifest]}

    sanitized = Path.join(context.root, "sanitized")
    assert :ok = NativeBuildTask.run(["--workspace", sanitized, "--sanitizers"], environment)
    assert_received {:mix_shell, :info, ["Native build completed: " <> ^sanitized]}
    assert :ok = NativeBuildTask.run(["--workspace", workspace], environment)
    assert_received {:mix_shell, :info, ["Native build verified: " <> ^workspace]}

    assert_raise Mix.Error, ~r/usage: mix wotex.thread.native.build/, fn ->
      NativeBuildTask.run(["--workspace", "relative"])
    end

    assert_raise Mix.Error, ~r/Thread native build failed: :linux_required/, fn ->
      NativeBuildTask.run(
        ["--workspace", Path.join(context.root, "other")],
        %{environment | platform: {:unix, :darwin}}
      )
    end
  end

  test "WTH-B01 the software build task reports its manifest and refuses bad arguments",
       context do
    environment = BuildFixture.software_environment(context.root)
    workspace = context.workspace

    assert :ok = SoftwareBuildTask.run(["--workspace", workspace], environment)
    assert_received {:mix_shell, :info, ["Software build completed: " <> ^workspace]}
    manifest = Path.join(workspace, "software-manifest.json")
    assert_received {:mix_shell, :info, ["Manifest: " <> ^manifest]}

    assert :ok = SoftwareBuildTask.run(["--workspace", workspace], environment)
    assert_received {:mix_shell, :info, ["Software build verified: " <> ^workspace]}

    assert_raise Mix.Error, ~r/usage: mix wotex.thread.software.build/, fn ->
      SoftwareBuildTask.run([])
    end

    assert_raise Mix.Error, ~r/Thread software build failed: :linux_required/, fn ->
      SoftwareBuildTask.run(
        ["--workspace", Path.join(context.root, "other")],
        %{environment | platform: {:unix, :darwin}}
      )
    end
  end

  test "WTH-B03 the software run task reports its result path and refuses bad arguments",
       context do
    build_environment = BuildFixture.software_environment(context.root)
    workspace = context.workspace
    assert {:ok, %{reused: false}} = Build.run(workspace, build_environment)
    environment = run_environment(context, build_environment)

    assert :ok = SoftwareRunTask.run(["--workspace", workspace], environment)
    path = Path.join(workspace, "software-run/result.json")
    assert_received {:mix_shell, :info, ["Software run passed: " <> ^path]}
    assert Jason.decode!(File.read!(path))["status"] == "passed"

    assert_raise Mix.Error, ~r/usage: mix wotex.thread.software.run/, fn ->
      SoftwareRunTask.run(["--workspace", "relative"])
    end

    assert_raise Mix.Error, ~r/Thread software run failed: :software_run_exists/, fn ->
      SoftwareRunTask.run(["--workspace", workspace], environment)
    end
  end

  defp run_environment(context, build_environment) do
    project = Path.join(context.root, "project")

    for path <- ~w(lib priv/openthread test/software priv/fixtures) do
      File.mkdir_p!(Path.join(project, path))
      File.write!(Path.join([project, path, "placeholder"]), "disposable\n")
    end

    for path <- ~w(mix.exs mix.lock), do: File.write!(Path.join(project, path), "disposable\n")
    required = [%{"module" => "M", "name" => "one"}]

    inventory = %{
      "format" => "wotex.thread.software-acceptance",
      "version" => 1,
      "lanes" => %{
        "normal" => %{"paths" => [], "required" => required},
        "sanitized" => %{"paths" => ["test/software"], "required" => required}
      }
    }

    File.write!(Path.join(project, "test/software/acceptance.json"), Jason.encode!(inventory))
    mix = Path.join(project, "mix")

    File.write!(mix, """
    #!/bin/sh
    printf '{"module":"M","name":"one","state":"passed"}\\n' >> "$WOTEX_THREAD_CASE_RESULTS"
    exit 0
    """)

    File.chmod!(mix, 0o755)
    proc = Path.join(context.root, "proc")
    File.mkdir_p!(proc)

    %{
      platform: {:unix, :linux},
      project_root: project,
      build: fn path -> Build.run(path, build_environment) end,
      mix: mix,
      proc: proc
    }
  end
end
