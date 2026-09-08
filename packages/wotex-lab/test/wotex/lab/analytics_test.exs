defmodule Wotex.Lab.AnalyticsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Analytics
  alias Wotex.Lab.Analytics.{Query, Source}
  alias Wotex.Lab.Error

  test "native summaries distinguish observed zero, missing and each nonfinite state" do
    backend = Nx.default_backend()
    sources = [series([{3, 0}, {1, nil}, {2, :nan}, {4, :infinity}, {5, :neg_infinity}, {6, 12}])]
    assert {:ok, result} = Analytics.analyze(sources)
    assert result.backend == "Explorer.PolarsBackend"
    assert result.value_dtype == "f64"
    assert result.total_rows == 6
    assert [%{"observed" => 2, "missing" => 1, "nonfinite" => 3} = summary] = result.summary
    assert summary["mean"] == 6.0
    assert summary["minimum"] == 0.0
    assert summary["maximum"] == 12.0

    assert Enum.map(result.preview, & &1["state"]) ==
             ~w(observed missing nan infinity neg_infinity observed)

    assert [%{points: [{3.0, +0.0}, {1.0, nil}, {2.0, nil}, {4.0, nil}, {5.0, nil}, {6.0, 12.0}]}] =
             result.plots

    assert Nx.default_backend() == backend
  end

  test "inclusive range and series filters operate before summaries and previews" do
    sources = [series([{0, 1}, {1, 2}, {2, 3}]), %{series([{1, 20}]) | name: "power", unit: "W"}]
    assert {:ok, all} = Analytics.analyze(sources)
    assert Enum.map(all.summary, & &1["unit"]) == ["W", "Cel"]

    assert {:ok, result} =
             Analytics.analyze(sources, series: "temperature", from: 1, to: 2, limit: 1)

    assert [%{"value" => 2.0}] = result.preview
    assert [%{"mean" => 2.5, "observed" => 2}] = result.summary
    assert result.total_rows == 2 and result.truncated
    assert result.source_digest == all.source_digest
    refute result.query_digest == all.query_digest

    assert {:ok, ^result} =
             Analytics.analyze(sources, limit: 1, to: 2, from: 1, series: "temperature")

    assert {:ok, lower} = Analytics.analyze(sources, from: 2)
    assert lower.total_rows == 1
    assert {:ok, upper} = Analytics.analyze(sources, to: 0)
    assert upper.total_rows == 1
  end

  test "empty and wholly unobserved data never report a measured zero" do
    assert {:ok, empty} = Analytics.analyze([])
    assert empty.summary == [] and empty.plots == [] and empty.preview == []
    assert empty.total_rows == 0 and not empty.truncated

    assert empty.source_digest ==
             "sha256:017b7efafaa509766cf685f3f8757cb18d7457e027c3e15dc5e3e4edf97f7fdb"

    assert empty.query_digest ==
             "sha256:9aa8161b5d4378ace533ab2c1b6cefdf7c9a781bb31500179b1135ac6e028074"

    assert {:ok, missing} = Analytics.analyze([series([{0, nil}, {1, :nan}])])
    assert [%{"observed" => 0, "missing" => 1, "nonfinite" => 1} = summary] = missing.summary
    assert is_nil(summary["mean"]) and is_nil(summary["minimum"]) and is_nil(summary["maximum"])
    assert {:ok, filtered} = Analytics.analyze([series([{0, 1}])], from: 9)
    assert filtered.summary == [] and filtered.plots == []
  end

  test "browser rows are capped before materialization while admitted plots retain their order" do
    assert %{rows: 100, columns: 32, series: 8, points: 2_000, bytes: 1_048_576} = Source.limits()
    points = Enum.map(1..2_000, &{&1, &1})
    assert {:ok, result} = Analytics.analyze([series(points)])
    assert length(result.preview) == 100
    assert result.total_rows == 2_000 and result.truncated
    assert length(hd(result.plots).points) == 2_000
    assert hd(result.series).method == "none"

    sampled =
      Map.merge(series([{0, 1}]), %{
        source: "sampled fixture",
        method: "minmax-bucket",
        interval: 2,
        dropped: 10
      })

    assert {:ok, result} = Analytics.analyze([sampled])

    assert [%{source: "sampled fixture", method: "minmax-bucket", interval: 2, dropped: 10}] =
             result.series
  end

  test "source identity binds metadata, order, values and missing state without map order" do
    source = series([{0, nil}, {1, 2}])
    assert {:ok, original} = Source.new([source])
    assert {:ok, ^original} = Source.new([source |> Map.to_list() |> Enum.reverse() |> Map.new()])

    for changed <- [
          Map.put(source, :unit, "K"),
          Map.put(source, :source, "different"),
          Map.put(source, :points, [{0, :nan}, {1, 2}]),
          Map.put(source, :points, [{1, 2}, {0, nil}])
        ] do
      assert {:ok, admitted} = Source.new([changed])
      refute admitted.digest == original.digest
    end
  end

  test "source admission refuses malformed, lossy and oversized input before native work" do
    valid = series([{0, 1}])

    for bad <- [
          nil,
          %{},
          "https://example.invalid/data",
          [nil],
          [%{}],
          [valid, valid],
          List.duplicate(valid, 9),
          [Map.put(valid, :extra, true)],
          [Map.put(valid, :name, "")],
          [Map.put(valid, :unit, <<255>>)],
          [Map.put(valid, :source, String.duplicate("a", 129))],
          [Map.put(valid, :method, "arbitrary")],
          [Map.put(valid, :interval, -1)],
          [Map.put(valid, :dropped, -1)],
          [Map.put(valid, :points, [{0, "1"}])],
          [Map.put(valid, :points, [[0, 1]])],
          [Map.put(valid, :points, [{:nan, 0}])],
          [Map.put(valid, :points, [{0, 9_007_199_254_740_992}])],
          [Map.put(valid, :points, [{0, 1.0e101}])],
          [Map.put(valid, :points, List.duplicate({0, 1}, 2_001))]
        ] do
      assert {:error, %Error{code: :invalid_analysis_source}} = Analytics.analyze(bad)
    end

    large =
      for n <- 1..8,
          do: %{
            valid
            | name: String.duplicate("a", 126) <> "#{n}",
              points: List.duplicate({0, 1}, 2_000)
          }

    assert {:error, %Error{code: :analysis_source_too_large}} = Analytics.analyze(large)
  end

  test "query admission is a closed descriptor, not a native expression or scope selector" do
    for opts <- [
          nil,
          %{},
          [limit: 1, limit: 2],
          [sql: "select *"],
          [instance_id: "other"],
          [backend: Explorer.PolarsBackend],
          [series: "unknown"],
          [limit: 0],
          [limit: 101],
          [limit: 1.5],
          [from: "1"],
          [to: :infinity],
          [from: 2, to: 1],
          [from: 1.0e101]
        ] do
      assert {:error, %Error{}} = Query.new(opts, ["temperature"])
      assert {:error, %Error{}} = Analytics.analyze([series([])], opts)
    end
  end

  defp series(points), do: %{name: "temperature", unit: "Cel", points: points}
end
