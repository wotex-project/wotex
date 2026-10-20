defmodule Wotex.BLE.CoreBluetoothSDKTest do
  @moduledoc false

  use ExUnit.Case, async: false

  if :os.type() == {:unix, :darwin} do
    alias Wotex.BLE.NativeLane

    @root Path.expand("../../..", __DIR__)
    @vectors Path.join(@root, "priv/fixtures/corebluetooth-notifications-v1.json")
    @external_resource @vectors
    @cases ~w(permissions invalid_options discovery discovery_refusal discovery_capacity missing_and_expired modes
              operation_refusal submission_boundary read_callbacks released_objects callback_identity
              continuity_loss cleanup_fault independent notification_modes notification_controls
              notification_values notification_credit notification_capacity notification_faults
              notification_deadlines notification_aliases notification_host_join
              power_registration power_messages power_operations power_notifications power_cleanup power_independent power_host_join)

    setup_all do
      directory =
        Path.join(
          System.tmp_dir!(),
          "wotex-ble-cb-sdk-#{System.pid()}-#{System.unique_integer([:positive])}"
        )

      File.mkdir!(directory)
      on_exit(fn -> File.rm_rf!(directory) end)
      executable = Path.join(directory, "sdk")

      compiler =
        System.find_executable("xcrun") || flunk("CoreBluetooth tests require the Apple SDK")

      {output, status} =
        System.cmd(
          compiler,
          ["clang++"] ++
            NativeLane.flags() ++
            ~w(-std=c++17 -x objective-c++ -fobjc-arc -mmacosx-version-min=14.0 -Wall -Wextra -Werror) ++
            [
              Path.join(@root, "priv/corebluetooth/native/sdk.cpp"),
              Path.join(@root, "test/native/corebluetooth_sdk_test.cpp"),
              "-framework",
              "Foundation",
              "-framework",
              "CoreBluetooth",
              "-framework",
              "IOKit",
              "-o",
              executable
            ],
          stderr_to_stdout: true,
          env: NativeLane.environment([])
        )

      assert status == 0, output
      {:ok, executable: executable}
    end

    for name <- @cases do
      test "CoreBluetooth SDK #{name}", %{executable: executable} do
        arguments =
          if unquote(name) in ["notification_modes", "notification_controls"],
            do: [unquote(name), @vectors],
            else: [unquote(name)]

        {output, status} = System.cmd(executable, arguments, env: NativeLane.environment([]))
        assert status == 0, output
        assert output == "ok #{unquote(name)}\n"
      end
    end

    test "unfinished SDK ownership is a native lifetime failure", %{executable: executable} do
      assert {"", 73} =
               System.cmd(executable, ["unfinished_destruction"], env: NativeLane.environment([]))
    end
  end
end
