defmodule Wotex.BLE.CoreBluetoothBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "build arguments reject implicit, duplicate and relative workspaces" do
    for args <- [
          [],
          ["--workspace", "relative"],
          ["--workspace", "/tmp/a", "--workspace", "/tmp/b"],
          ["--force"]
        ] do
      assert {:error, :invalid_native_build_arguments} =
               Wotex.BLE.CoreBluetooth.Build.arguments(args)
    end
  end

  if :os.type() == {:unix, :darwin} do
    import ExUnit.CaptureIO

    alias Mix.Tasks.Wotex.Ble.Corebluetooth.Build, as: BuildTask
    alias Wotex.BLE.BlueZ.Artifacts
    alias Wotex.BLE.CoreBluetooth.Build

    setup_all do
      directory =
        "/private/tmp/wotex-cb-build-#{System.pid()}-#{System.unique_integer([:positive])}"

      on_exit(fn -> File.rm_rf!(directory) end)
      result = Build.run(directory)

      unless match?({:ok, _}, result) do
        logs =
          Map.new(
            Path.wildcard(Path.join(directory, "logs/*.log")),
            &{Path.basename(&1), File.read!(&1)}
          )

        flunk(inspect({result, logs}, limit: :infinity))
      end

      assert {:ok, %{reused: false, manifest: manifest}} = result
      {:ok, directory: directory, manifest: manifest}
    end

    test "the real SDK host has exact passive startup, system linkage and admitted artifacts",
         context do
      assert context.manifest["audit"]["embedded_usage_description"]

      assert context.manifest["audit"]["ready_probe"] ==
               ~s({"backend":"corebluetooth-native","event":"ready","revision":"1","version":1}\n)

      assert context.manifest["build_features"]["minimum_macos"] == "14.0"
      assert context.manifest["build_features"]["system_power_observation"] == "iokit"
      headers = context.manifest["upstream_sources"]["apple_sdk"]["api_headers"]

      assert Map.has_key?(
               headers,
               "System/Library/Frameworks/IOKit.framework/Headers/pwr_mgt/IOPMLib.h"
             )

      assert Enum.any?(context.manifest["binaries"], fn binary ->
               Enum.any?(binary["dependencies"], &String.contains?(&1, "/IOKit.framework/"))
             end)

      artifacts = context.manifest["artifacts"]
      host = "output/bin/wotex-ble-corebluetooth"
      guardian = "output/bin/wotex-ble-guardian"

      assert {:ok, selectors} =
               Artifacts.new(
                 executable: Path.join(context.directory, host),
                 executable_sha256: artifacts[host],
                 guardian: Path.join(context.directory, guardian),
                 guardian_sha256: artifacts[guardian]
               )

      assert {:ok, _} = Artifacts.verify(selectors, System.monotonic_time(:millisecond) + 5000)
      assert Enum.all?(context.manifest["binaries"], &(&1["format"] == "mach-o"))
    end

    test "reuse rehashes exact artifacts and refuses tampering without repair", context do
      assert {:ok, %{reused: true}} = Build.run(context.directory)
      host = Path.join(context.directory, "output/bin/wotex-ble-corebluetooth")
      original = File.read!(host)

      try do
        File.write!(host, original <> <<0>>)
        assert {:error, :build_manifest_mismatch} = Build.run(context.directory)
        assert File.read!(host) == original <> <<0>>
      after
        File.write!(host, original)
      end

      assert {:ok, %{reused: true}} = Build.run(context.directory)
    end

    test "the public task reports verified artifacts and rejects malformed arguments", context do
      output = capture_io(fn -> assert :ok = BuildTask.run(["--workspace", context.directory]) end)
      assert output =~ "CoreBluetooth build verified: #{context.directory}"
      assert output =~ "Manifest: #{Path.join(context.directory, "native-manifest.json")}"

      assert_raise Mix.Error, ~r/invalid_native_build_arguments/, fn ->
        BuildTask.run(["--workspace", "relative"])
      end
    end
  end
end
