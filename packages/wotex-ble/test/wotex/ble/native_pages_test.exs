Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativePagesTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

  @root Path.expand("../../..", __DIR__)
  @fixtures @root
            |> Path.join("priv/fixtures/native-port-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  setup_all do
    compiler = System.find_executable("c++") || flunk("native pages tests require C++17")
    bootstrap = System.find_executable("cc") || flunk("native pages tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-pages-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "command")
    executable = Path.join(directory, "pages-test")

    options = [
      cd: @root,
      timeout: NativeLane.timeout(15_000),
      limit: 1_048_576,
      env: NativeLane.environment(clean_environment())
    ]

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(
               bootstrap,
               Path.join(@root, "priv/bluez/native/build_command.c"),
               guardian,
               options
             )

    arguments =
      NativeLane.flags() ++
        [
          "-std=c++17",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-pedantic",
          "-I",
          Path.join(@root, "priv/bluez/native"),
          Path.join(@root, "test/native/pages_test.cpp"),
          "-o",
          executable
        ]

    assert {:ok, "", 0} = NativeCommand.run(guardian, compiler, arguments, options)
    {:ok, guardian: guardian, executable: executable, options: options}
  end

  for {operation, result} <- [
        {"boundaries", "native page boundaries passed\n"},
        {"ordering", "native page ordering passed\n"},
        {"limits", "native page aggregate limits passed\n"},
        {"ledger", "native page bounded ledger passed\n"},
        {"random", "native page random source failures passed\n"}
      ] do
    @operation operation
    @result result
    test "WBL-B04/C07 native discovery #{@operation}", context do
      assert {:ok, @result, 0} = run(context, [@operation])
    end
  end

  for fixture <- @fixtures, fixture["operation"] in ["discovery_page", "discovery_cursor_ledger"] do
    @fixture fixture
    test "#{fixture["id"]} executes bounded native discovery pages", context do
      selector =
        if @fixture["operation"] == "discovery_page", do: "--page-input", else: "--ledger-input"

      assert {:ok, output, 0} =
               run(context, [selector, Jason.encode!(@fixture["input"])])

      assert Jason.decode!(output) == @fixture["expectation"]["value"]
    end
  end

  defp run(context, arguments) do
    NativeCommand.run(context.guardian, context.executable, arguments, context.options)
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end
end
