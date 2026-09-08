defmodule WotexLabWorkbench.ChartPreviewTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Chart, Preview, Runs}

  test "native chart admission accepts only the closed constructor and enforces both ceilings" do
    assert Chart.limits() == %{series: 8, points: 2_000}

    assert {:error, %Error{code: :invalid_chart}} =
             Chart.new(%{"mark" => "line", "data" => %{"url" => "https://example.test"}})

    assert {:error, %Error{code: :invalid_chart}} = Chart.new(transform: [])
    assert {:error, %Error{code: :invalid_chart}} = Chart.new(series: :caller)

    too_many =
      for index <- 1..9 do
        %{name: "series-#{index}", points: [{index, index}]}
      end

    assert {:error, %Error{code: :too_many_series}} = Chart.new(series: too_many)

    points = Enum.map(1..2_001, &{&1, &1})

    assert {:error, %Error{code: :too_many_points}} =
             Chart.new(series: [%{name: "x", points: points}])
  end

  test "geometry and downsampling preserve gaps and extrema within the transfer budget" do
    points = Enum.map(1..4_000, &{&1, if(rem(&1, 499) == 0, do: nil, else: :math.sin(&1))})
    sampled = Preview.downsample(points)

    assert length(sampled.points) <= Preview.limits().points
    assert sampled.method == "minmax-bucket"
    assert sampled.dropped > 0
    assert Enum.any?(sampled.points, &(elem(&1, 1) == nil))

    assert %{points: [{1, 1.0}], method: "none", dropped: 0} =
             Preview.downsample([{1, 1.0}])

    assert {:ok, chart} =
             Chart.new(
               title: "Temperature",
               x: %{field: "time", title: "time"},
               y: %{field: "value", title: "Cel"},
               series: [%{name: "room", points: [{1, 20.0}, {2, nil}, {3, 22.0}]}]
             )

    geometry = Chart.geometry(chart, width: 320, height: 160)
    assert geometry.width == 320 and geometry.height == 160
    assert hd(geometry.series).gaps == 1
    assert length(hd(geometry.series).segments) == 2
  end

  test "plain evidence conversion remains bounded without a client chart runtime" do
    assert Runs.plain(%{pid: self(), nested: %{value: :ok}}) ==
             %{"pid" => "opaque", "nested" => %{"value" => "ok"}}

    assert Runs.assertion("x", true, "yes").status == :pass
    assert Runs.assertion("x", false, "no").status == :fail
    assert Runs.assertion("x", :not_run, "later").status == :not_run

    app_js = File.read!(Path.expand("../../priv/static/js/app.js", __DIR__))
    refute app_js =~ "vega"
    refute app_js =~ "WotexChart"
    assert app_js =~ "LiveSocket"

    assert WotexLabWorkbenchWeb.static_paths() == ~w(css js favicon.ico robots.txt)
    assert WotexLabWorkbenchWeb.ErrorHTML.render("404.html", %{}) == "Not Found"
  end

  test "missing and nonfinite preview values never masquerade as zero" do
    assert Preview.format(nil) == "missing"
    assert Preview.format(:nan) == "nonfinite (nan)"
    assert Preview.format(:infinity) == "nonfinite (+inf)"
    assert Preview.format(:neg_infinity) == "nonfinite (-inf)"
    assert Preview.format(2.5) == "2.500"
    assert Preview.format(:good) == "good"
    assert Preview.format(%{caller: String.duplicate("x", 100)}) =~ "%{caller:"
  end

  test "chart and preview edge cases remain bounded and return structured refusals" do
    assert {:ok, empty} = Chart.new(mark: "point", series: [])
    assert %{series: [], x_ticks: x_ticks, y_ticks: y_ticks} = Chart.geometry(empty)
    assert length(x_ticks) == 6 and length(y_ticks) == 5

    assert {:error, %Error{code: :invalid_axis}} = Chart.new(x: %{})

    assert {:error, %Error{code: :invalid_point}} =
             Chart.new(series: [%{name: "room", points: [:caller]}])

    assert {:error, %Error{code: :text_too_long}} =
             Chart.new(title: String.duplicate("x", 129))

    assert {:error, %Error{code: :invalid_chart}} = Chart.new(caller: true)

    assert {:error, %Error{code: :invalid_preview_budget}} =
             Preview.downsample([{1, 10}, {2, nil}, {3, -5}, {4, 20}], 2)

    assert Runs.series("temperature", "Cel", "observed", [{1, 2}]).points == [{1, 2}]

    assert {{:ok, :measured}, elapsed} = Runs.measure(fn -> {:ok, :measured} end)
    assert is_integer(elapsed) and elapsed >= 0
  end
end
