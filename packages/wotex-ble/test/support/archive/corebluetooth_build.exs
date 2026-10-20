defmodule CoreArchiveBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false
  @tag timeout: 120_000
  test "the archived public builder compiles the full native source closure and verifies reuse" do
    directory = Path.join(File.cwd!(), "native")

    assert {:ok, %{reused: false, manifest: manifest}} =
             Wotex.BLE.CoreBluetooth.Build.run(directory)

    assert manifest["build_features"]["system_power_observation"] == "iokit"
    assert manifest["audit"]["embedded_usage_description"]

    assert manifest["audit"]["ready_probe"] ==
             ~s({"backend":"corebluetooth-native","event":"ready","revision":"1","version":1}\n)

    host =
      Enum.find(manifest["binaries"], &(Path.basename(&1["path"]) == "wotex-ble-corebluetooth"))

    guardian = Enum.find(manifest["binaries"], &(Path.basename(&1["path"]) == "wotex-ble-guardian"))
    assert Enum.any?(host["dependencies"], &String.contains?(&1, "/IOKit.framework/"))
    assert {:ok, %{reused: true}} = Wotex.BLE.CoreBluetooth.Build.run(directory)

    identity = %{
      guardian: Path.join(directory, guardian["path"]),
      guardian_sha256: manifest["artifacts"][guardian["path"]]
    }

    File.write!("native_identity.json", JSON.encode!(identity))

    IO.write(
      "CORE_BUILD=" <>
        JSON.encode!(%{
          host: manifest["artifacts"][host["path"]],
          guardian: identity.guardian_sha256,
          source: manifest["source_revision"],
          power: "iokit"
        }) <> "\n"
    )
  end
end
