defmodule WotexLabWorkbench.RunPresentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexLabWorkbench.{Chart, Run, RunPresentation}

  test "Run views are closed and legacy exact analysis links keep their meaning" do
    assert {:ok, :result} = RunPresentation.view(%{"id" => "run-1"})
    assert {:ok, :analysis} = RunPresentation.view(%{"id" => "run-1", "analysis" => %{}})
    assert {:ok, :review} = RunPresentation.view(%{"id" => "run-1", "view" => "review"})

    for params <- [
          %{"id" => "run-1", "view" => "approve"},
          %{"id" => "run-1", "view" => %{}},
          %{"id" => "run-1", "room" => "other"},
          %{"id" => "run-1", "view" => String.duplicate("a", 4_096)}
        ] do
      assert {:error, %{code: :invalid_run_view}} = RunPresentation.view(params)
    end
  end

  test "display time shares the original event origin and preserves gaps, negative and integer values" do
    run = %{
      run()
      | timeseries: [
          %{points: [{-10_000, -2}, {-9_000, nil}, {-8_000, 3}]},
          %{points: [{-11_000, 7}]}
        ]
    }

    {:ok, chart} =
      Chart.new(
        title: "Temperature (Cel)",
        x: %{field: "time", title: "event time"},
        y: %{field: "value", title: "Cel"},
        series: [%{name: "temperature", points: [{-10_000, -2}, {-9_000, nil}, {-8_000, 3}]}]
      )

    display = RunPresentation.display_chart(run, chart)
    assert display.x.title == "Elapsed (s)"
    assert display.y.title == "°C"
    assert hd(display.series).points == [{1.0, -2}, {2.0, nil}, {3.0, 3}]
    assert hd(chart.series).points == [{-10_000, -2}, {-9_000, nil}, {-8_000, 3}]
    assert hd(Chart.geometry(display).series).gaps == 1
  end

  test "one-point outputs and failed runs never invent a measured zero" do
    failed = run()
    assert RunPresentation.result(failed).value == "—"

    proposal = %{failed | status: :completed, proposal: %{"input" => 22.0}}
    assert %{value: "22.000", unit: "°C", note: "Inert proposal"} = RunPresentation.result(proposal)
    assert RunPresentation.report_path(proposal) == "/evidence/report.json?run=run-1"
  end

  defp run do
    %Run{
      id: "run-1",
      experiment: "thermal",
      attempt: 1,
      params: [],
      status: :failed,
      source_mode: "fixture",
      backend: "Nx.BinaryBackend",
      started_at: ~U[2026-10-22 00:00:00Z]
    }
  end
end
