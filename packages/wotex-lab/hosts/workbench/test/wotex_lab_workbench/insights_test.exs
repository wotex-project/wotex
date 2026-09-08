defmodule WotexLabWorkbench.InsightsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Insights, Run}

  test "read-only analysis compares compatible units and preserves gaps and run evidence" do
    run = run()
    assert {:ok, result} = Insights.analyze(run, %{"mark" => "point", "from" => "1", "to" => "2"})
    assert result.run_id == run.id
    assert result.total_rows == 5
    assert length(result.charts) == 2
    assert Enum.map(result.charts, & &1.mark) == ["point", "point"]
    assert length(hd(result.charts).series) == 2
    assert {:ok, area} = Insights.analyze(run, %{"mark" => "area"})
    assert Enum.all?(area.charts, &(&1.mark == "area"))
    assert run == run()
    assert {:ok, selected} = Insights.analyze(run, %{"series" => "room", "from" => "2"})
    assert selected.total_rows == 1
    assert [%{"value" => nil, "state" => "missing"}] = selected.preview
    assert [%{"mean" => nil}] = selected.summary
    assert {:ok, empty} = Insights.analyze(run, %{"to" => "-1"})
    assert empty.total_rows == 0 and empty.charts == []
  end

  test "host rejects malformed controls, arbitrary descriptors and browser-selected scope" do
    for params <- [
          nil,
          [],
          %{"instance_id" => "other"},
          %{"series" => "other"},
          %{"mark" => "bar"},
          %{"mark" => %{}},
          %{"from" => 0},
          %{"from" => "0suffix"},
          %{"from" => "1e101"},
          %{"from" => String.duplicate("1", 65)},
          %{"from" => "2", "to" => "1"}
        ] do
      assert {:error, %Error{}} = Insights.analyze(run(), params)
    end

    invalid = %{run() | timeseries: [%{name: "bad", unit: "Cel", points: [{0, "bad"}]}]}
    assert {:error, %Error{code: :invalid_analysis_source}} = Insights.analyze(invalid, %{})
  end

  defp run do
    %Run{
      id: "run-1",
      experiment: "thermal",
      attempt: 1,
      params: [],
      status: :completed,
      source_mode: "simulation",
      backend: "binary",
      started_at: ~U[2026-09-08 00:00:00Z],
      record_digest: "sha256:unchanged",
      effect: nil,
      timeseries: [
        %{name: "room", unit: "Cel", points: [{0, 1}, {1, 2}, {2, nil}]},
        %{name: "outside", unit: "Cel", points: [{1, 3}, {2, 4}]},
        %{name: "meter", unit: "W", points: [{1, 50}]}
      ]
    }
  end
end
