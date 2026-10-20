Code.require_file("../../../bin/corebluetooth_consumers.exs", __DIR__)

defmodule Wotex.BLE.CoreBluetoothArchiveRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.Check.CoreBluetoothConsumers

  test "archive evidence requires complete cases and assertion-only mutation failures" do
    baseline = output(7, 0, 0, 0)
    mutant = output(7, 2, 2, 0)
    assert {:ok, _} = CoreBluetoothConsumers.validate(baseline, 0, 7, false)
    assert {:ok, _} = CoreBluetoothConsumers.validate(mutant, 1, 7, true)
    assert {:ok, _} = CoreBluetoothConsumers.validate(output(1, 0, 0, 0), 0, 1, false)

    for {bytes, status, changed?} <- [
          {baseline, 1, false},
          {mutant, 0, true},
          {baseline, 0, true},
          {output(7, 2, 1, 1), 1, true},
          {output(7, 2, 1, 0), 1, true},
          {output(6, 1, 1, 0), 1, true},
          {output(7, 1, 1, 0, 1), 1, true},
          {output(7, 1, 1, 0, 0, 1), 1, true},
          {baseline <> baseline, 0, false},
          {"CORE_RESULT={}\nCORE_ASSERTIONS={}\n", 0, false},
          {"CORE_RESULT=invalid\nCORE_ASSERTIONS={}\n", 0, false},
          {"compiler failure", 1, true},
          {"warning: invalid assertion harness\n" <> mutant, 1, true}
        ] do
      assert :error == CoreBluetoothConsumers.validate(bytes, status, 7, changed?)
    end
  end

  defp output(total, failures, assertions, errors, skipped \\ 0, excluded \\ 0),
    do:
      "CORE_RESULT=" <>
        JSON.encode!(%{total: total, failures: failures, skipped: skipped, excluded: excluded}) <>
        "\nCORE_ASSERTIONS=" <> JSON.encode!(%{assertions: assertions, errors: errors}) <> "\n"
end
