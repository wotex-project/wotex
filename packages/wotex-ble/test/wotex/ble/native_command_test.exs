Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeCommandTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeCommand

  @root Path.expand("../../..", __DIR__)

  setup_all do
    compiler = System.find_executable("cc") || flunk("native command tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-command-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    options = [cd: directory, timeout: 15_000, env: compiler_environment()]
    native = Path.join(@root, "test/interop/native")
    command = Path.join(directory, "command")

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(compiler, guardian_source(), command, options)

    for name <- ["command_launcher", "command_probe"] do
      assert {:ok, "", 0} =
               NativeCommand.run(
                 command,
                 compiler,
                 [
                   "-std=c11",
                   "-Wall",
                   "-Wextra",
                   "-Werror",
                   Path.join(native, name <> ".c"),
                   "-o",
                   Path.join(directory, name)
                 ],
                 options
               )
    end

    fault = Path.join(directory, "fault")

    assert {:ok, "", 0} =
             NativeCommand.run(
               command,
               compiler,
               [
                 "-std=c11",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 "-Dsetpgid=wotex_test_setpgid",
                 guardian_source(),
                 Path.join(native, "command_group_fault.c"),
                 "-o",
                 fault
               ],
               options
             )

    {:ok,
     directory: directory,
     command: command,
     fault: fault,
     probe: Path.join(directory, "command_probe"),
     launcher: Path.join(directory, "command_launcher"),
     options: Keyword.merge(options, timeout: 2000, cleanup: 400, limit: 65_536)}
  end

  test "WBL-B01 inherited SIGCHLD and signal masks cannot discard owned child status", context do
    port =
      Port.open({:spawn_executable, context.launcher}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [context.command, "2000", "65536", "400", context.directory, context.probe, "output"],
        env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
      ])

    assert {:ok, "stdout\nstderr\n", 0} = NativeCommand.await(port, 3000, 65_536)
  end

  @tag timeout: 60_000
  test "WBL-B01 one thousand short commands retain group custody and exact exit", context do
    for _ <- 1..1000 do
      assert {:ok, "", 7} =
               NativeCommand.run(context.command, context.probe, ["exit"], context.options)
    end

    1..32
    |> Task.async_stream(
      fn _ -> NativeCommand.run(context.command, context.probe, ["output"], context.options) end,
      max_concurrency: 32,
      ordered: false,
      timeout: 5000
    )
    |> Enum.each(fn result -> assert result == {:ok, {:ok, "stdout\nstderr\n", 0}} end)
  end

  test "WBL-B01 failed group admission cannot execute the child", context do
    marker = Path.join(context.directory, "unexecuted")
    started = System.monotonic_time(:millisecond)

    assert {:ok, "", 126} =
             NativeCommand.run(context.fault, context.probe, ["marker", marker], context.options)

    assert System.monotonic_time(:millisecond) - started < 1000
    refute File.exists?(marker)
  end

  # Compilers resolve their linker through PATH; the guardian cases clear it again.
  defp compiler_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end

  defp empty_environment, do: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
  defp guardian_source, do: Path.join(@root, "priv/bluez/native/build_command.c")
end
