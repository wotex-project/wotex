defmodule WotexLabWorkbench.ChartContractTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbenchWeb.Components.Chart, as: Component

  @base %{
    "mark" => "line",
    "data" => %{"values" => [%{"x" => 1, "y" => 2}]},
    "encoding" => %{"x" => %{"field" => "x"}, "y" => %{"field" => "y"}}
  }

  test "unknown active keys cannot be hidden in siblings, axes, colors or data rows" do
    for key <- ~w(params layer repeat concat config usermeta transform datasets projection) do
      assert {:error, %Error{code: :forbidden_key}} = Chart.validate(Map.put(@base, key, %{}))
    end

    for key <- ~w(expr signal calculate aggregate bin timeUnit scale) do
      assert {:error, %Error{code: :forbidden_key}} =
               Chart.validate(put_in(@base, ["encoding", "x", key], %{"expr" => "evil"}))
    end

    for field <- ["a.b", "a[0]", "__proto__"] do
      spec =
        @base
        |> put_in(["encoding", "x", "field"], field)
        |> put_in(["data", "values"], [%{field => 1, "y" => 2}])

      assert {:ok, chart} = Chart.validate(spec)
      assert chart.spec["encoding"]["x"]["field"] == "x"

      assert chart.spec["data"]["values"] ==
               [%{"x" => 1, "y" => 2, "series" => "series", "position" => 0}]
    end

    assert {:error, %Error{}} =
             Chart.validate(
               put_in(@base, ["data", "values"], [%{"x" => 1, "y" => 2, "expr" => "evil"}])
             )

    assert {:error, %Error{}} =
             Chart.validate(
               put_in(@base, ["encoding", "color"], %{"field" => "s", "legend" => %{}})
             )

    assert {:error, %Error{}} = Chart.validate(put_in(@base, ["encoding", "color"], "s"))
  end

  test "malformed constructors, aliases, dialects and numeric overflow are refused" do
    for options <- [
          :invalid,
          [nil],
          [title: "a", title: "b"],
          [unknown: 1],
          [x: nil],
          [series: [:invalid]],
          [series: [%{name: "x", points: [:invalid]}]],
          [series: [%{name: "x", points: [{1, 1.0e200}]}]],
          [x: %{field: "y", title: "same"}]
        ] do
      assert {:error, %Error{}} = Chart.new(options)
    end

    for update <- [
          Map.put(@base, "$schema", "https://vega.github.io/schema/vega-lite/v5.json"),
          put_in(@base, ["encoding", "x", "type"], "temporal"),
          put_in(@base, ["encoding", "color"], %{"field" => "x"}),
          put_in(@base, ["encoding", "color"], %{"field" => "s", "type" => "quantitative"}),
          put_in(@base, ["data", "values"], [%{"x" => 1, "y" => :nan}]),
          put_in(@base, ["data", "values"], Enum.map(1..16_001, &%{"x" => &1, "y" => 1}))
        ] do
      assert {:error, %Error{}} = Chart.validate(update)
    end

    assert {:error, %Error{}} =
             Chart.new(series: [%{name: "x", points: []}, %{name: "x", points: []}])

    assert {:error, %Error{code: :too_many_points}} =
             Chart.validate(
               put_in(@base, ["data", "values"], Enum.map(1..2_001, &%{"x" => &1, "y" => 1}))
             )

    assert {:ok, _chart} = Chart.new(series: [%{name: "flat", points: [{1.0e100, 1.0e100}]}])
    assert {:error, %Error{code: :forbidden_key}} = Chart.validate(Map.put(@base, nil, true))
    assert {:error, %Error{}} = Chart.new(title: <<255>>)
  end

  test "fallback dispatches marks, preserves gaps and labels axes, legends and missing data" do
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
      refute html =~ "<script>escaped</script>"
      assert chart.spec["mark"]["invalid"] == "break-paths-show-domains"

      if Enum.any?(points, &is_number(elem(&1, 1))) do
        assert html =~ %{"line" => "<polyline", "point" => "<circle", "area" => "<polygon"}[mark]
      end

      if mark == "area" do
        assert chart.spec["encoding"]["y"]["scale"]["zero"]
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
    assert length(chart.spec["data"]["values"]) == 2_000
  end
end
