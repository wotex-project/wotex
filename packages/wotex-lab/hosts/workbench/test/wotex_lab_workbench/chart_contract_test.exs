defmodule WotexLabWorkbench.ChartContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbenchWeb.Components.Chart, as: Component

  test "the native descriptor admits only its closed constructor envelope" do
    for options <- [
          %{"mark" => "line"},
          [params: %{}],
          [transform: []],
          [config: %{}],
          [title: "a", title: "b"],
          [x: %{field: "x", title: "x", scale: %{zero: true}}],
          [series: [%{name: "room", points: [{1, 2}], color: "red"}]]
        ] do
      assert {:error, %Error{}} = Chart.new(options)
    end

    for axis <- [
          %{},
          %{field: "x"},
          %{field: "series", title: "series"},
          %{field: "x", title: "x", caller: true}
        ] do
      assert {:error, %Error{code: :invalid_axis}} = Chart.new(x: axis)
    end
  end

  test "malformed constructors and numeric overflow are refused" do
    for options <- [
          :invalid,
          [nil],
          [x: nil],
          [series: [:invalid]],
          [series: [%{name: "x", points: [:invalid]}]],
          [series: [%{name: "x", points: [{1, 1.0e200}]}]],
          [x: %{field: "y", title: "same"}]
        ] do
      assert {:error, %Error{}} = Chart.new(options)
    end

    assert {:error, %Error{}} =
             Chart.new(series: [%{name: "x", points: []}, %{name: "x", points: []}])

    assert {:error, %Error{code: :too_many_points}} =
             Chart.new(series: [%{name: "room", points: Enum.map(1..2_001, &{&1, 1})}])

    assert {:ok, _} = Chart.new(series: [%{name: "flat", points: [{1.0e100, 1.0e100}]}])
    assert {:error, %Error{}} = Chart.new(title: <<255>>)
  end

  test "server SVG dispatches marks, preserves gaps and labels accessible context" do
    for mark <- ~w(line point area),
        points <- [[{0, -2}, {1, nil}, {2, -4}], [{0, nil}], [{0, 3}, {1, 3}], []] do
      assert {:ok, chart} =
               Chart.new(
                 title: "<script>escaped</script>",
                 mark: mark,
                 x: %{field: "x", title: "event time"},
                 y: %{field: "y", title: "Cel"},
                 series: [%{name: "room", points: points}]
               )

      html = render_component(&Component.chart/1, id: "fixture", chart: chart)
      assert html =~ "aria-describedby=\"fixture-description\""
      assert html =~ "event time"
      assert html =~ "Cel"
      assert html =~ "&lt;script&gt;escaped&lt;/script&gt;"
      assert html =~ "class=\"wl-chart-svg\""
      refute html =~ "<script>escaped</script>"
      refute html =~ "phx-hook"
      refute html =~ "data-spec"

      if Enum.any?(points, &is_number(elem(&1, 1))) do
        assert html =~ %{"line" => "<polyline", "point" => "<circle", "area" => "<polygon"}[mark]
      end

      if mark == "area" do
        assert Enum.any?(Chart.geometry(chart).y_ticks, &(&1.value == 0)) or points == []
      end
    end
  end

  test "the table never embeds more than 100 rows while the chart retains its points" do
    {:ok, chart} = Chart.new(series: [%{name: "room", points: Enum.map(1..2_000, &{&1, &1})}])
    html = render_component(&Component.chart/1, id: "bounded", chart: chart)
    assert length(Regex.scan(~r/<tr>/, html)) == 101
    assert html =~ "100 of 2000 points"
    assert html =~ "Preview truncated"
    assert length(hd(chart.series).points) == 2_000
  end
end
