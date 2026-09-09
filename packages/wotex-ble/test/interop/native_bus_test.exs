Code.require_file("../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeBusTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeCommand

  @moduletag :interop
  @root Path.expand("../..", __DIR__)

  test "WBL-B01 private libdbus ownership, bounded calls and exact replies" do
    source = required_directory!("WOTEX_BLE_DBUS_SOURCE")
    build = required_directory!("WOTEX_BLE_DBUS_BUILD")
    compiler = System.find_executable("c++") || flunk("native bus fixture requires C++17")
    bootstrap = System.find_executable("cc") || flunk("native bus fixture requires C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-bus-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "command")
    executable = Path.join(directory, "bus-test")
    config = Path.join(directory, "bus.conf")
    daemon = artifact!(build, ["bin/dbus-daemon", "bus/dbus-daemon"])
    library = library!(build)
    options = [cd: @root, timeout: 15_000, limit: 1_048_576, env: clean_environment()]

    assert {:ok, output, 0} =
             NativeCommand.bootstrap(
               bootstrap,
               Path.join(@root, "test/interop/native/command.c"),
               guardian,
               options
             )

    assert output == ""

    arguments = [
      "-std=c++17",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-pedantic",
      "-I",
      Path.join(@root, "priv/bluez/native"),
      "-I",
      source,
      "-I",
      build,
      Path.join(@root, "test/native/bus_test.cpp"),
      library,
      "-Wl,-rpath,#{Path.dirname(library)}",
      "-o",
      executable
    ]

    assert {:ok, output, 0} = NativeCommand.run(guardian, compiler, arguments, options)
    assert output == ""

    File.write!(config, """
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <type>session</type><listen>unix:tmpdir=#{directory}</listen><auth>EXTERNAL</auth>
      <policy context="default">
        <allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/>
      </policy>
    </busconfig>
    """)

    assert {:ok, "native bus ownership invariants passed\n", 0} =
             NativeCommand.run(guardian, executable, [daemon, config], options)
  end

  defp required_directory!(name) do
    value = System.get_env(name)

    assert is_binary(value) and Path.type(value) == :absolute and File.dir?(value),
           "selected native bus fixture requires #{name} as an absolute directory"

    value
  end

  defp library!(build) do
    filename =
      case :os.type() do
        {:unix, :darwin} -> "libdbus-1.3.dylib"
        {:unix, :linux} -> "libdbus-1.so"
      end

    artifact!(build, ["lib/#{filename}", "dbus/#{filename}"])
  end

  defp artifact!(build, paths) do
    path = Enum.find_value(paths, &existing_file(build, &1))
    assert path, "selected native bus fixture requires #{inspect(paths)} under #{build}"
    path
  end

  defp existing_file(build, path) do
    full = Path.join(build, path)
    if File.regular?(full), do: full
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end
end
