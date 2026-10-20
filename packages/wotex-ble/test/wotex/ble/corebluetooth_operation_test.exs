defmodule Wotex.BLE.CoreBluetoothOperationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.NativeLane

  @source Path.expand("../../native/corebluetooth_operation_test.cpp", __DIR__)
  @cases ~w(modes bounds invalid_start readiness changed_facts deadline foreign_callbacks
            malformed_callbacks submission_failure retirement cleanup_expiry clock_regression
            separate_owners unfinished_destruction)

  setup_all do
    compiler = System.find_executable("c++") || flunk("CoreBluetooth operation tests require C++17")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-ble-cb-op-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    executable = Path.join(directory, "operation")

    {output, status} =
      System.cmd(
        compiler,
        NativeLane.flags() ++
          ~w(-std=c++17 -Wall -Wextra -Werror -pedantic) ++
          [@source, "-o", executable],
        stderr_to_stdout: true,
        env: NativeLane.environment([])
      )

    assert status == 0, output
    {:ok, executable: executable}
  end

  for name <- @cases do
    test "CoreBluetooth operation #{name}", %{executable: executable} do
      {output, status} = System.cmd(executable, [unquote(name)], env: NativeLane.environment([]))
      assert status == 0, output
      assert output == "ok #{unquote(name)}\n"
    end
  end
end
