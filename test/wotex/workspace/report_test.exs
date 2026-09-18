defmodule Wotex.Workspace.ReportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Report

  describe "table/2" do
    test "without rows renders the header and the rule" do
      assert Report.table([]) == """
             package | result | seconds
             --------+--------+--------
             """
    end

    test "makes each column as wide as its widest cell" do
      rows = [
        %{package: "a", result: "ok", seconds: 0.4},
        %{package: "wotex-binding-http", result: "test failed (2)", seconds: 125.04}
      ]

      assert Report.table(rows) == """
             package            | result          | seconds
             -------------------+-----------------+--------
             a                  | ok              | 0.4
             wotex-binding-http | test failed (2) | 125.0
             """
    end

    test "shows the named columns in order and leaves a missing key blank" do
      rows = [
        %{step: "compile", gate: "fast", result: "ok"},
        %{step: "dialyzer", result: "skipped"}
      ]

      assert Report.table(rows, [:result, :step, :gate]) == """
             result  | step     | gate
             --------+----------+-----
             ok      | compile  | fast
             skipped | dialyzer |
             """
    end

    test "measures cells in characters, not bytes" do
      assert Report.table([%{package: "é", result: "ok", seconds: 1}]) == """
             package | result | seconds
             --------+--------+--------
             é       | ok     | 1.0
             """
    end
  end

  describe "seconds/1" do
    test "formats integers and floats with one decimal" do
      assert Report.seconds(0) == "0.0"
      assert Report.seconds(3) == "3.0"
      assert Report.seconds(12.345) == "12.3"
      assert Report.seconds(0.04) == "0.0"
      assert Report.seconds(59.96) == "60.0"
      assert Report.seconds(1234.56) == "1234.6"
    end
  end
end
