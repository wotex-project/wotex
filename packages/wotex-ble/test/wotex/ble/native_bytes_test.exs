Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.NativeBytesTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.{NativeCommand, Procedure}

  @root Path.expand("../../..", __DIR__)
  @fixtures @root
            |> Path.join("docs/specs/fixtures/native-port-v1.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  setup_all do
    compiler = System.find_executable("c++") || flunk("native byte tests require C++17")
    bootstrap = System.find_executable("cc") || flunk("native byte tests require C11")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-native-bytes-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    guardian = Path.join(directory, "command")
    executable = Path.join(directory, "bytes-test")
    options = [cd: @root, timeout: 15_000, limit: 1_048_576, env: clean_environment()]

    assert {:ok, "", 0} =
             NativeCommand.bootstrap(
               bootstrap,
               Path.join(@root, "test/interop/native/command.c"),
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
      Path.join(@root, "test/native/bytes_test.cpp"),
      "-o",
      executable
    ]

    assert {:ok, "", 0} = NativeCommand.run(guardian, compiler, arguments, options)
    {:ok, guardian: guardian, executable: executable, options: options}
  end

  test "WBL-B02/C07 RFC 4648 known answers, all sizes and canonical padding", context do
    assert {:ok, "native byte envelope invariants passed\n", 0} =
             NativeCommand.run(context.guardian, context.executable, [], context.options)
  end

  test "WBL-S03/C07 native byte envelopes agree with the independent BEAM codec", context do
    cases = [<<>>, <<0>>, <<255>>, <<0, 255>>, <<0, 255, 34>>, :binary.copy(<<0, 255>>, 256)]

    for bytes <- cases do
      value = %{"type" => "bytes", "base64" => Base.encode64(bytes)}
      assert Procedure.decode_bytes(value) == {:ok, bytes}

      assert decode(context, Jason.encode!(value)) == %{
               "accepted" => true,
               "bytes" => :binary.bin_to_list(bytes)
             }
    end
  end

  test "WBL-C02/C07 malformed, oversized and noncanonical bytes fail", context do
    values = [
      nil,
      [],
      %{},
      %{"type" => "bytes", "base64" => true},
      %{"type" => "bytes", "base64" => "", "extra" => true}
    ]

    encoded = [
      "AA",
      "AA==\n",
      "AB==",
      "AAB=",
      "AA-_",
      "AA\0=",
      Base.encode64(:binary.copy(<<0>>, 513))
    ]

    values = values ++ Enum.map(encoded, &%{"type" => "bytes", "base64" => &1})

    for value <- values do
      assert Procedure.decode_bytes(value) == :invalid
      assert decode(context, Jason.encode!(value)) == %{"accepted" => false}
    end

    assert decode(context, ~s({"type":"bytes","type":"bytes","base64":""})) == %{
             "accepted" => false
           }
  end

  for fixture <- @fixtures, fixture["operation"] == "decode_bytes" do
    @fixture fixture
    test "#{fixture["id"]} executes the production native byte decoder", context do
      actual = decode(context, Jason.encode!(@fixture["input"]["value"]))
      assert actual == @fixture["expectation"]["value"]
    end
  end

  defp decode(context, value) do
    assert {:ok, output, 0} =
             NativeCommand.run(
               context.guardian,
               context.executable,
               ["--decode", value],
               context.options
             )

    Jason.decode!(output)
  end

  defp clean_environment do
    Enum.map(System.get_env(), fn
      {"PATH", value} -> {"PATH", value}
      {name, _} -> {name, nil}
    end)
  end
end
