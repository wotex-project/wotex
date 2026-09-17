Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeReportsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeCommand

  @root Path.expand("../../..", __DIR__)
  @fixtures @root
            |> Path.join("docs/specs/fixtures/native-port-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  setup_all do
    compiler = System.find_executable("c++") || flunk("native reports tests require C++17")
    bootstrap = System.find_executable("cc") || flunk("native reports tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-reports-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "command")
    executable = Path.join(directory, "reports-test")
    options = [cd: @root, timeout: 15_000, limit: 1_048_576, env: clean_environment()]

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(
               bootstrap,
               Path.join(@root, "priv/bluez/native/build_command.c"),
               guardian,
               options
             )

    arguments = [
      "-std=c++17",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-pedantic",
      "-I",
      Path.join(@root, "priv/bluez/native"),
      Path.join(@root, "test/native/reports_test.cpp"),
      "-o",
      executable
    ]

    assert {:ok, "", 0} = NativeCommand.run(guardian, compiler, arguments, options)
    {:ok, guardian: guardian, executable: executable, options: options}
  end

  for {operation, result} <- [
        {"boundaries", "native report boundaries passed\n"},
        {"overflow", "native report overflow passed\n"},
        {"fairness", "native report fairness and retirement passed\n"},
        {"bytes", "native report byte limits passed\n"},
        {"churn", "native report churn and control bounds passed\n"}
      ] do
    @operation operation
    @result result
    test "WBL-B02/C07 native report #{@operation}", context do
      assert {:ok, @result, 0} = run(context, [@operation])
    end
  end

  for fixture <- @fixtures, fixture["operation"] == "report_lifecycle" do
    @fixture fixture
    test "#{fixture["id"]} executes native report, control and retirement boundaries", context do
      assert {:ok, output, 0} =
               run(context, ["--report-input", Jason.encode!(@fixture["input"])])

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
