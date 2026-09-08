Code.require_file("../../../bin/support/reference_summary.exs", __DIR__)

defmodule Wotex.Lab.ReferenceSummaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.ReferenceSummary

  test "complete old and new ExUnit formats distinguish totals, failures and exclusions" do
    assert {:ok, %{tests: 302, failures: 0, excluded: 24}} =
             ReferenceSummary.parse("Finished in 30 seconds\nResult: 302 passed, 24 excluded\n")

    assert {:ok, %{tests: 10, failures: 2, excluded: 1}} =
             ReferenceSummary.parse("Result: 8/10 passed, 1 excluded\nFailed: 2 tests\n")

    assert {:ok, %{tests: 10, failures: 0, excluded: 0}} =
             ReferenceSummary.parse("10 tests, 0 failures\r\n")

    assert {:ok, %{tests: 8, failures: 1, excluded: 2}} =
             ReferenceSummary.parse("10 tests, 1 failure, 2 excluded\n")

    assert {:ok, %{tests: 1, failures: 1, excluded: 0}} =
             ReferenceSummary.parse("1 test, 1 failure\n")
  end

  test "empty, ambiguous, embedded, malformed and impossible summaries fail closed" do
    for output <- [
          nil,
          "",
          "0 tests, 0 failures",
          "Result: 0 passed",
          "diagnostic Result: 12 passed",
          "Result: 12 passed invalid suffix",
          "Result: 12/10 passed",
          "10 tests, 11 failures",
          "10 tests, 0 failures, 10 excluded",
          "1 test, 1 failure, 2 excluded",
          "Result: 9999999999 passed",
          String.duplicate("x", 8_388_609),
          "Result: 1 passed\nResult: 2 passed",
          "10 tests, 0 failures\nResult: 10 passed"
        ] do
      assert {:error, :invalid_summary} = ReferenceSummary.parse(output)
    end
  end

  test "process exit success is insufficient without a valid passing test summary" do
    assert ReferenceSummary.successful?(0, ReferenceSummary.parse("Result: 3 passed"))
    refute ReferenceSummary.successful?(1, ReferenceSummary.parse("Result: 3 passed"))
    refute ReferenceSummary.successful?(0, ReferenceSummary.parse("Result: 2/3 passed"))
    refute ReferenceSummary.successful?(0, ReferenceSummary.parse("no tests ran"))
  end
end
