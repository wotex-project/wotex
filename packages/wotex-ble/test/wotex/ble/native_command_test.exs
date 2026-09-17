Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeCommandTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

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

    options = [
      cd: directory,
      timeout: NativeLane.timeout(15_000),
      env: NativeLane.environment(compiler_environment())
    ]

    native = Path.join(@root, "test/interop/native")
    bootstrap = Path.join(directory, "bootstrap")
    command = Path.join(directory, "command")

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(compiler, guardian_source(), bootstrap, options)

    # The bootstrap guardian only compiles; the guardian under test is built in
    # the selected lane.
    for {name, inputs} <- [
          {"command", [guardian_source()]},
          {"command_launcher", [Path.join(native, "command_launcher.c")]},
          {"command_probe", [Path.join(native, "command_probe.c")]},
          {"fault",
           [
             "-Dsetpgid=wotex_test_setpgid",
             guardian_source(),
             Path.join(native, "command_group_fault.c")
           ]}
        ] do
      assert {:ok, "", 0} =
               NativeCommand.run(
                 bootstrap,
                 compiler,
                 NativeLane.flags() ++
                   ["-std=c11", "-O1", "-Wall", "-Wextra", "-Werror"] ++
                   inputs ++ ["-o", Path.join(directory, name)],
                 options
               )
    end

    {:ok,
     directory: directory,
     command: command,
     fault: Path.join(directory, "fault"),
     probe: Path.join(directory, "command_probe"),
     launcher: Path.join(directory, "command_launcher"),
     options:
       Keyword.merge(options,
         timeout: NativeLane.timeout(2000),
         cleanup: 400,
         limit: 65_536,
         env: NativeLane.environment(empty_environment())
       )}
  end

  test "WBL-B01 inherited SIGCHLD and signal masks cannot discard owned child status", context do
    environment =
      Enum.map(NativeLane.environment(empty_environment()), fn
        {key, nil} -> {String.to_charlist(key), false}
        {key, value} -> {String.to_charlist(key), String.to_charlist(value)}
      end)

    port =
      Port.open({:spawn_executable, context.launcher}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [
          context.command,
          Integer.to_string(context.options[:timeout]),
          "65536",
          "400",
          context.directory,
          context.probe,
          "output"
        ],
        env: environment
      ])

    assert {:ok, "stdout\nstderr\n", 0} =
             NativeCommand.await(port, NativeLane.timeout(3000), 65_536)
  end

  @tag timeout: NativeLane.timeout(60_000)
  test "WBL-B01 one thousand short commands retain group custody and exact exit", context do
    # LeakSanitizer scans every instrumented exit; its lane keeps the exact exit
    # and concurrent output cases but limits sequential churn, as for startup.
    count = if NativeLane.leak_audit?(), do: 32, else: 1000

    for _ <- 1..count do
      assert {:ok, "", 7} =
               NativeCommand.run(context.command, context.probe, ["exit"], context.options)
    end

    1..32
    |> Task.async_stream(
      fn _ -> NativeCommand.run(context.command, context.probe, ["output"], context.options) end,
      max_concurrency: 32,
      ordered: false,
      timeout: NativeLane.timeout(5000)
    )
    |> Enum.each(fn result -> assert result == {:ok, {:ok, "stdout\nstderr\n", 0}} end)
  end

  test "WBL-B01 failed group admission cannot execute the child", context do
    marker = Path.join(context.directory, "unexecuted")
    started = System.monotonic_time(:millisecond)

    assert {:ok, "", 126} =
             NativeCommand.run(context.fault, context.probe, ["marker", marker], context.options)

    # The named leak-audit allowance covers only LeakSanitizer exit scanning.
    instrumentation = if NativeLane.leak_audit?(), do: 1000, else: 0
    assert System.monotonic_time(:millisecond) - started < 1000 + instrumentation
    refute File.exists?(marker)
  end

  # Compilers resolve their linker through PATH; the guardian cases clear it.
  defp compiler_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end

  defp empty_environment, do: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
  defp guardian_source, do: Path.join(@root, "priv/bluez/native/build_command.c")
end
