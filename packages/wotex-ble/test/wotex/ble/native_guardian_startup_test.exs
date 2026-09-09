Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeGuardianStartupTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeCommand

  @root Path.expand("../../..", __DIR__)

  setup_all do
    compiler = System.find_executable("cc") || flunk("native guardian tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-startup-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    command = Path.join(directory, "command")
    options = [cd: directory, timeout: 15_000, limit: 65_536, env: empty_environment()]
    native = Path.join(@root, "test/interop/native")
    custody = Path.join(@root, "priv/bluez/native/custody.c")

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(compiler, Path.join(native, "command.c"), command, options)

    for {name, input} <- [
          {"custody", custody},
          {"check", Path.join(@root, "test/native/guardian_startup_check.c")}
        ] do
      assert {:ok, "", 0} =
               NativeCommand.run(
                 command,
                 compiler,
                 [
                   "-std=c11",
                   "-Wall",
                   "-Wextra",
                   "-Werror",
                   input,
                   "-o",
                   Path.join(directory, name)
                 ],
                 options
               )
    end

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
                 custody,
                 Path.join(native, "command_group_fault.c"),
                 "-o",
                 Path.join(directory, "fault")
               ],
               options
             )

    {:ok,
     directory: directory,
     command: command,
     check: Path.join(directory, "check"),
     options: Keyword.put(options, :timeout, 30_000)}
  end

  for {executable, count, inheritance, status} <- [
        {"custody", 1000, "plain", 0},
        {"custody", 32, "inherit", 0},
        {"fault", 32, "inherit", 126}
      ] do
    @scenario {executable, count, inheritance, status}
    @tag timeout: 60_000
    test "WBL-G01 #{executable} #{count} #{inheritance} retains startup ownership", context do
      {executable, count, inheritance, status} = @scenario

      assert {:ok, output, 0} =
               NativeCommand.run(
                 context.command,
                 context.check,
                 [
                   Path.join(context.directory, executable),
                   "custody",
                   Integer.to_string(count),
                   inheritance,
                   context.directory,
                   Integer.to_string(status)
                 ],
                 context.options
               )

      assert Jason.decode!(output) == %{"launches" => count, "status" => "passed"}
    end
  end

  defp empty_environment, do: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
end
