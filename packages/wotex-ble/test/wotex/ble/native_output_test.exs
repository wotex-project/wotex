Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeOutputTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, NativeLane}

  @root Path.expand("../../..", __DIR__)
  @fixtures @root
            |> Path.join("docs/specs/fixtures/native-port-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  setup_all do
    compiler = System.find_executable("c++") || flunk("native output tests require C++17")
    bootstrap = System.find_executable("cc") || flunk("native output tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-output-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "command")
    executable = Path.join(directory, "output-test")

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
          Path.join(@root, "test/native/output_test.cpp"),
          "-o",
          executable
        ]

    assert {:ok, "", 0} = NativeCommand.run(guardian, compiler, arguments, options)
    {:ok, guardian: guardian, executable: executable, options: options}
  end

  for {operation, result} <- [
        {"serialization", "native output serialization passed\n"},
        {"capacity", "native output capacity passed\n"},
        {"pipes", "native output pipe ownership passed\n"}
      ] do
    @operation operation
    @result result
    test "WBL-B02/C07 native #{@operation} ownership and bounds", context do
      assert {:ok, @result, 0} = run(context, [@operation])
    end
  end

  test "WBL-B02/C07 serialized native values agree with the independent BEAM decoder", context do
    values = [
      nil,
      true,
      false,
      -9_223_372_036_854_775_808,
      18_446_744_073_709_551_615,
      1.5,
      "åäö",
      "quotes\"\n\\\t",
      [1, "two", nil],
      %{"version" => 1, "id" => "1", "ok" => true, "result" => nil}
    ]

    for value <- values do
      assert {:ok, output, 0} = run(context, ["--encode", Jason.encode!(value)])
      assert String.ends_with?(output, "\n")
      assert Jason.decode!(output) == value
    end
  end

  for fixture <- @fixtures, fixture["operation"] == "serialize_frame" do
    @fixture fixture
    test "#{fixture["id"]} executes bounded native output serialization", context do
      assert {:ok, output, 0} =
               run(context, ["--serialize-input", Jason.encode!(@fixture["input"])])

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
