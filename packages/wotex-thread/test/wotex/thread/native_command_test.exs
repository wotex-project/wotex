defmodule Wotex.Thread.NativeCommandTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.Native.{Bootstrap, Build, Command}

  setup do
    directory =
      Path.join(File.cwd!(), ".wotex-thread-command-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    source = Application.app_dir(:wotex_thread, "priv/openthread/build_command.c")
    guardian = Path.join(directory, "build-command")
    %{directory: directory, source: source, guardian: guardian}
  end

  test "WTH-B01 C guardian bounds output, deadline and direct argument execution", c do
    assert {:ok, _} = Bootstrap.compile("/usr/bin/cc", c.source, c.guardian, c.directory)

    step = %{
      id: :probe,
      executable: "/bin/echo",
      cwd: c.directory,
      args: ["exact argument"],
      env: [{"PATH", "/usr/bin:/bin"}, {"LC_ALL", "C"}],
      timeout_ms: 1_000,
      output_bytes: 4_096,
      cleanup_ms: 1_000
    }

    assert {:ok, %{output: "exact argument\n", exit_status: 0}} =
             Command.run(c.guardian, step)

    assert {:error, :command_output_limit, %{exit_status: 125}} =
             Command.run(c.guardian, %{
               step
               | executable: "/usr/bin/yes",
                 args: [],
                 output_bytes: 64
             })

    assert {:error, :command_deadline, %{exit_status: 124}} =
             Command.run(c.guardian, %{step | executable: "/bin/sleep", args: ["2"]})
  end

  test "WTH-B01 build refuses unsupported host before creating workspace", c do
    if :os.type() != {:unix, :linux} do
      workspace = Path.join(c.directory, "native")
      assert {:error, :linux_required} = Build.run(workspace)
      refute File.exists?(workspace)
    end
  end
end
