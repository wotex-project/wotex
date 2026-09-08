defmodule WotexLabWorkbench.Chart do
  @moduledoc """
  Closed Vega-Lite charts with equivalent missing-aware SVG geometry.

  Admission accepts only line, area or point marks, scalar quantitative axes
  and bounded inline data. `new/1` and `validate/1` return structured refusals
  before rendering. No caller expression, selection, URL or arbitrary renderer
  configuration survives normalization. Area marks use a zero baseline.
  """

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Chart.Admission

  @schema "https://vega.github.io/schema/vega-lite/v6.json"
  @type series :: %{name: String.t(), points: [{number(), number() | nil}]}
  @type t :: %__MODULE__{
          title: String.t(),
          mark: String.t(),
          x: %{field: String.t(), title: String.t()},
          y: %{field: String.t(), title: String.t()},
          series: [series()],
          spec: map()
        }
  @enforce_keys [:title, :mark, :x, :y, :series, :spec]
  defstruct @enforce_keys

  @doc "Series and point ceilings."
  @spec limits() :: %{series: pos_integer(), points: pos_integer()}
  def limits, do: %{series: 8, points: 2_000}

  @doc "Builds an admitted chart from title, mark, x/y axes and named point series."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) do
    with {:ok, spec} <- Admission.build(opts), do: validate(spec)
  end

  @doc "Normalizes a closed Vega-Lite subset; never forwards caller configuration."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(spec) do
    with {:ok, fields} <- Admission.normalize(spec) do
      {:ok, struct!(__MODULE__, Map.put(fields, :spec, specification(fields)))}
    end
  end

  @doc "Projects series, gaps, axes and a zero area baseline into an SVG box."
  @spec geometry(t(), keyword()) :: map()
  def geometry(%__MODULE__{} = chart, opts \\ []) do
    width = Keyword.get(opts, :width, 640)
    height = Keyword.get(opts, :height, 280)
    pad = %{left: 64, right: 16, top: 16, bottom: 48}
    xs = for %{points: points} <- chart.series, {x, _y} <- points, do: x
    ys = for %{points: points} <- chart.series, {_x, y} <- points, is_number(y), do: y
    {x0, x1} = domain(xs)
    {y0, y1} = domain(if(chart.mark == "area", do: [0 | ys], else: ys))
    inner_w = width - pad.left - pad.right
    inner_h = height - pad.top - pad.bottom
    sx = fn x -> pad.left + (x - x0) / (x1 - x0) * inner_w end
    sy = fn y -> pad.top + inner_h - (y - y0) / (y1 - y0) * inner_h end

    %{
      width: width,
      height: height,
      plot: %{x: pad.left, y: pad.top, width: inner_w, height: inner_h},
      x_ticks: ticks(x0, x1, 5) |> Enum.map(&%{value: &1, px: sx.(&1)}),
      y_ticks: ticks(y0, y1, 4) |> Enum.map(&%{value: &1, px: sy.(&1)}),
      series: Enum.map(chart.series, &project(&1, sx, sy))
    }
  end

  defp specification(chart) do
    %{
      "$schema" => @schema,
      "title" => chart.title,
      "mark" => %{"type" => chart.mark, "invalid" => "break-paths-show-domains"},
      "data" => %{
        "values" =>
          Enum.flat_map(chart.series, fn series ->
            series.points
            |> Enum.with_index()
            |> Enum.map(fn {{x, y}, index} ->
              %{"x" => x, "y" => y, "series" => series.name, "position" => index}
            end)
          end)
      },
      "encoding" => %{
        "x" => %{
          "field" => "x",
          "type" => "quantitative",
          "title" => chart.x.title,
          "scale" => %{"zero" => false}
        },
        "y" => %{
          "field" => "y",
          "type" => "quantitative",
          "title" => chart.y.title,
          "scale" => %{"zero" => chart.mark == "area"}
        },
        "color" => %{"field" => "series", "type" => "nominal"},
        "order" => %{"field" => "position", "type" => "quantitative"}
      }
    }
  end

  defp project(series, sx, sy) do
    chunks =
      series.points
      |> Enum.chunk_by(&is_nil(elem(&1, 1)))
      |> Enum.reject(fn [{_x, y} | _] -> is_nil(y) end)

    segments = Enum.map(chunks, &Enum.map_join(&1, " ", fn {x, y} -> pair(sx.(x), sy.(y)) end))

    areas =
      Enum.zip_with(chunks, segments, fn chunk, segment ->
        {first, _y} = hd(chunk)
        {last, _y} = List.last(chunk)
        "#{pair(sx.(first), sy.(0))} #{segment} #{pair(sx.(last), sy.(0))}"
      end)

    %{
      name: series.name,
      segments: segments,
      areas: areas,
      points: for({x, y} <- series.points, is_number(y), do: %{x: sx.(x), y: sy.(y)}),
      gaps: Enum.count(series.points, &is_nil(elem(&1, 1)))
    }
  end

  defp domain([]), do: {0, 1}

  defp domain(values) do
    {min, max} = Enum.min_max(values)
    pad = max(abs(min) * 0.05, 1)
    if min == max, do: {min - pad, max + pad}, else: {min, max}
  end

  defp ticks(low, high, count), do: Enum.map(0..count, &(low + &1 * ((high - low) / count)))
  defp pair(x, y), do: "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}"
end
