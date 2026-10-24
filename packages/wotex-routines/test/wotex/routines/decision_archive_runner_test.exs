Code.require_file("../../../bin/decision_consumers.exs", __DIR__)

defmodule Wotex.Routines.DecisionArchiveRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Routines.Check.DecisionConsumers

  test "only a complete passing baseline or assertion-only semantic catch is evidence" do
    baseline = marker(41, 0, 0, 0)
    mutant = marker(40, 2, 2, 0)
    assert {:ok, _} = DecisionConsumers.validate(baseline, 0, 41, false)
    assert {:ok, _} = DecisionConsumers.validate(mutant, 1, 40, true)

    for {output, status, total, mutant?} <- [
          {baseline, 1, 41, false},
          {marker(8, 0, 0, 0), 0, 41, false},
          {marker(7, 1, 1, 0), 1, 40, true},
          {mutant, 0, 40, true},
          {marker(40, 0, 0, 0), 0, 40, true},
          {marker(40, 2, 1, 1), 1, 40, true},
          {marker(40, 2, 1, 0), 1, 40, true},
          {marker(39, 1, 1, 0), 1, 40, true},
          {marker(40, 1, 1, 0, skipped: 1), 1, 40, true},
          {marker(40, 1, 1, 0, excluded: 1), 1, 40, true},
          {baseline <> baseline, 0, 41, false},
          {"DECISION_RESULT={}\nDECISION_ASSERTIONS={}\n", 0, 41, false},
          {"DECISION_RESULT=invalid\nDECISION_ASSERTIONS={}\n", 0, 41, false},
          {"compiler failure", 1, 40, true}
        ] do
      assert {:error, _} = DecisionConsumers.validate(output, status, total, mutant?)
    end
  end

  defp marker(total, failures, assertions, errors, opts \\ []) do
    result = %{
      total: total,
      failures: failures,
      skipped: opts[:skipped] || 0,
      excluded: opts[:excluded] || 0
    }

    "DECISION_RESULT=" <>
      JSON.encode!(result) <>
      "\nDECISION_ASSERTIONS=" <>
      JSON.encode!(%{assertions: assertions, errors: errors}) <> "\n"
  end
end
