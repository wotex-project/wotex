Code.require_file("../../../bin/support/child_environment.exs", __DIR__)
Code.require_file("../../../bin/support/reference_runner.exs", __DIR__)

defmodule Wotex.Lab.ReferenceRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Check.ReferenceRunner

  test "a native receipt binds cleanup, exit status and exact bounded output" do
    encoded =
      "WOTEX_REFERENCE_RUNNER cleanup=ok outcome=exit status=0 output_bytes=12\n" <>
        "tests passed"

    assert {:ok,
            %{
              cleanup: :ok,
              outcome: "exit",
              status: 0,
              output_bytes: 12,
              output: "tests passed"
            }} = ReferenceRunner.admit(encoded, 0, 1024)
  end

  test "missing, forged, inconsistent and oversized receipts fail closed" do
    valid = "WOTEX_REFERENCE_RUNNER cleanup=ok outcome=exit status=0 output_bytes=2\nok"

    assert {:error, :invalid_runner_receipt} = ReferenceRunner.admit("ok", 0, 1024)
    assert {:error, :invalid_runner_receipt} = ReferenceRunner.admit("prefix" <> valid, 0, 1024)
    assert {:error, :status_mismatch} = ReferenceRunner.admit(valid, 1, 1024)

    assert {:error, :output_size_mismatch} =
             ReferenceRunner.admit(
               "WOTEX_REFERENCE_RUNNER cleanup=ok outcome=exit status=0 output_bytes=1\nok",
               0,
               1024
             )

    assert {:error, :output_limit_exceeded} = ReferenceRunner.admit(valid, 0, 1)
    assert {:error, :invalid_runner_receipt} = ReferenceRunner.admit(nil, 0, 1)
  end
end
