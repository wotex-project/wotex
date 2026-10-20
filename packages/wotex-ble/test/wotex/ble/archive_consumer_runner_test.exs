Code.require_file("../../../bin/write_mode_consumers.exs", __DIR__)

defmodule Wotex.BLE.ArchiveConsumerRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.Check.WriteModeConsumers

  test "an archive result must contain all cases and assertion-only mutation catches" do
    baseline = output(5, 0, 0, 0)
    mutant = output(5, 2, 2, 0)
    assert {:ok, _} = WriteModeConsumers.validate(baseline, 0, 5, false)
    assert {:ok, _} = WriteModeConsumers.validate(mutant, 1, 5, true)

    for {bytes, status, count, mutated?} <- [
          {baseline, 1, 5, false},
          {mutant, 0, 5, true},
          {baseline, 0, 5, true},
          {output(5, 2, 1, 1), 1, 5, true},
          {output(5, 2, 1, 0), 1, 5, true},
          {output(4, 1, 1, 0), 1, 5, true},
          {output(5, 1, 1, 0, 1), 1, 5, true},
          {output(5, 1, 1, 0, 0, 1), 1, 5, true},
          {baseline <> baseline, 0, 5, false},
          {"WRITE_RESULT={}\nWRITE_ASSERTIONS={}\n", 0, 5, false},
          {"WRITE_RESULT=invalid\nWRITE_ASSERTIONS={}\n", 0, 5, false},
          {"compiler failure", 1, 5, true}
        ] do
      assert :error == WriteModeConsumers.validate(bytes, status, count, mutated?)
    end
  end

  defp output(total, failures, assertions, errors, skipped \\ 0, excluded \\ 0) do
    "WRITE_RESULT=" <>
      JSON.encode!(%{total: total, failures: failures, skipped: skipped, excluded: excluded}) <>
      "\nWRITE_ASSERTIONS=" <> JSON.encode!(%{assertions: assertions, errors: errors}) <> "\n"
  end
end
