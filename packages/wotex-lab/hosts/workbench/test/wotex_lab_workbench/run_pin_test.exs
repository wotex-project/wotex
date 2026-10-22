defmodule WotexLabWorkbench.RunPinTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Evidence.Record
  alias Wotex.Lab.Island.Encoder
  alias WotexLabWorkbench.{Board, BoardHistory, Canvas, Evidence, Run, RunPin, Runs}

  test "captures the outcome, exact record and elapsed chart without mutating the Run" do
    run = fixture()
    assert {:ok, pin} = RunPin.new(run, 0, nil)
    assert pin.outcome.value == "22.000" and pin.outcome.unit == "°C"
    assert pin.record == Record.to_map(run.record)
    assert pin.record_digest == run.record_digest
    assert hd(pin.result.chart.series).points == [{0.0, 20.0}, {1.0, 22.0}]
    assert pin.path == "/runs/run-1" and pin.paused
    assert hd(run.timeseries).points == [{0, 20.0}, {1000, 22.0}]
    assert {:ok, board} = Board.change(Board.empty(), {:pin_run, run, 0, nil})
    props = Board.decorate(Canvas.props([], [], %{}), board)
    assert {:ok, ^props} = Encoder.encode("canvas", props)
    assert hd(props["pins"])["kind"] == "run"
    refute Map.has_key?(hd(props["pins"]), "metric")
  end

  test "comparison captures retain the exact query, mark, negative values, gaps and original origin" do
    run = fixture([%{name: "test", unit: "Cel", points: [{0, 9}, {1000, nil}, {2000, -4}]}])
    query = %{"from" => "1000", "to" => "2000", "mark" => "point", "series" => ""}
    assert {:ok, pin} = RunPin.new(run, 0, query)
    assert pin.result.chart.mark == "point"
    assert hd(pin.result.chart.series).points == [{1.0, nil}, {2.0, -4.0}]
    assert pin.query["from"] == "1.0e3"
    assert pin.path =~ "analysis[mark]=point"
    assert {:ok, area} = RunPin.new(run, 0, Map.put(query, "mark", "area"))
    refute pin.id == area.id
    assert hd(area.result.chart.series).points == hd(pin.result.chart.series).points
    assert {:error, _} = RunPin.new(run, 0, Map.put(query, "authority", "grant"))
  end

  test "bounds refuse truncation, bad identities and all-missing or unrecorded charts" do
    points = for n <- 0..511, do: {n * 1000, n}
    run = fixture([%{name: "bounded", unit: "W", points: points}])
    assert {:ok, pin} = RunPin.new(run, 0, nil)
    assert length(hd(pin.result.chart.series).points) == 512

    too_many = %{
      run
      | timeseries: [%{hd(run.timeseries) | points: for(n <- 0..512, do: {n * 1000, n})}]
    }

    assert {:error, _} = RunPin.new(too_many, 0, nil)
    assert {:error, _} = RunPin.new(%{run | record: nil}, 0, nil)
    assert {:error, _} = RunPin.new(run, 8, nil)
    assert {:error, _} = RunPin.new(run, 0, %{"from" => "no"})
    missing = %{run | timeseries: [%{hd(run.timeseries) | points: [{0, nil}]}]}
    assert {:error, _} = RunPin.new(missing, 0, nil)
  end

  test "deduplication retains renamed titles and layout; sixteen shared slots are enforced" do
    run = fixture()
    {:ok, board} = Board.change(Board.empty(), {:pin_run, run, 0, nil})
    [pin] = board.pins
    {:ok, board} = Board.change(board, {:rename, pin.id, "Thermal comparison"})

    layout = %{
      "positions" => [%{"id" => pin.id, "x" => 20, "y" => 30, "width" => 440, "height" => 320}],
      "viewport" => %{"x" => 0, "y" => 0, "zoom" => 1}
    }

    {:ok, board} = Board.change(board, {:layout, layout, []})
    assert {:ok, same} = Board.change(board, {:pin_run, run, 0, nil})
    assert length(same.pins) == 1 and hd(same.pins).title == "Thermal comparison"
    assert same.layout == layout

    full =
      Enum.reduce(2..16, same, fn n, b ->
        {:ok, next} = Board.change(b, {:pin_run, %{run | id: "run-#{n}"}, 0, nil})
        next
      end)

    assert length(full.pins) == 16
    assert {:error, _} = Board.change(full, {:pin_run, %{run | id: "run-17"}, 0, nil})
    assert {:ok, _} = Board.change(full, {:pin_run, run, 0, nil})
  end

  test "captures never enter history refresh and room teardown clears their numerical data" do
    run = fixture()
    {:ok, board} = Board.change(Board.empty(), {:pin_run, run, 0, nil})
    [pin] = board.pins
    assert BoardHistory.load(%{}, [pin]) == []
    assert {:error, _} = Board.change(board, {:pause, pin.id, false})
    assert {:ok, ^board} = Board.change(board, {:refresh, [{:unavailable, [pin.id], 1000}]})
    cleared = Board.clear_results(board)
    assert [%{result: nil, record: nil, outcome: nil, error: "Room ended"}] = cleared.pins
    props = Board.decorate(Canvas.props([], [], %{}), cleared)
    assert {:ok, ^props} = Encoder.encode("canvas", props)
    assert hd(props["pins"])["series"] == []
  end

  defp fixture(series \\ nil) do
    {:ok, result} = Runs.Thermal.run(backend: Nx.BinaryBackend)

    run = %Run{
      id: "run-1",
      experiment: "thermal",
      attempt: 1,
      params: [backend: Nx.BinaryBackend],
      status: :completed,
      source_mode: "test fixture",
      backend: "Nx.BinaryBackend",
      started_at: ~U[2026-10-22 00:00:00Z],
      duration_ms: result.duration_ms,
      summary: result.summary,
      tensor: result.tensor,
      timeseries: series || result.timeseries,
      proposal: result.proposal
    }

    {:ok, record, digest} =
      Evidence.record(run, Map.take(result, [:outcomes, :inputs, :seed, :budgets]))

    %{run | record: record, record_digest: digest}
  end
end
