defmodule WotexLabWorkbench.Chart do
  @moduledoc """
  Bounded Vega-Lite line and area charts with a server-side geometry.

  `new/1` builds a specification from named series and `validate/1` admits
  one: a single `line`, `area` or `point` mark, inline `data.values` only
  (never `data.url`), string fields for x, y and the optional colour series,
  at most #{8} series and #{2_000} points per series, no `transform`,
  `expr`, `signal`, `calculate` or `format` keys anywhere, and no string
  longer than 128 bytes. Missing y values stay gaps. `geometry/1` projects
  the admitted series to SVG coordinates so HEEx can render the chart and
  its table without any client code.
  """

  alias Wotex.Lab.Error

  @max_series 8
  @max_points 2_000
  @max_text 128
  @marks ~w(line area point)
  @forbidden_keys ~w(transform expr signal calculate format url datasets projection params)
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
  def limits, do: %{series: @max_series, points: @max_points}

  @doc """
  Builds and validates a chart from `:title`, `:mark`, `:x` and `:y`
  (`%{field:, title:}`) and `:series` (`[%{name:, points:}]`).
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    x = Keyword.get(opts, :x, %{field: "x", title: "x"})
    y = Keyword.get(opts, :y, %{field: "y", title: "y"})
    series = Keyword.get(opts, :series, [])

    values =
      Enum.flat_map(series, fn %{name: name, points: points} ->
        Enum.map(points, fn {px, py} -> %{x.field => px, y.field => py, "series" => name} end)
      end)

    validate(%{
      "$schema" => @schema,
      "title" => Keyword.get(opts, :title, "Chart"),
      "mark" => Keyword.get(opts, :mark, "line"),
      "data" => %{"values" => values},
      "encoding" => %{
        "x" => %{"field" => x.field, "type" => "quantitative", "title" => x.title},
        "y" => %{"field" => y.field, "type" => "quantitative", "title" => y.title},
        "color" => %{"field" => "series", "type" => "nominal"}
      }
    })
  end

  @doc "Admits a Vega-Lite specification map into a chart."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%{"mark" => mark, "data" => %{"values" => values}, "encoding" => encoding} = spec)
      when mark in @marks and is_list(values) and is_map(encoding) do
    with :ok <- forbid(spec, ""),
         {:ok, x} <- axis(encoding, "x"),
         {:ok, y} <- axis(encoding, "y"),
         {:ok, series} <- series(values, x.field, y.field, encoding),
         :ok <- bounded(series) do
      {:ok,
       %__MODULE__{
         title: text(Map.get(spec, "title", "Chart")),
         mark: mark,
         x: x,
         y: y,
         series: series,
         spec: spec
       }}
    end
  end

  def validate(%{"data" => %{"url" => _url}}),
    do: {:error, Error.new(:external_data, :chart, "data.url is not admitted", path: "/data/url")}

  def validate(_spec),
    do: {:error, Error.new(:invalid_chart, :chart, "spec needs mark, inline data and encoding")}

  @doc "Projects the series onto a `width` by `height` SVG box with axis ticks."
  @spec geometry(t(), keyword()) :: map()
  def geometry(%__MODULE__{} = chart, opts \\ []) do
    width = Keyword.get(opts, :width, 640)
    height = Keyword.get(opts, :height, 240)
    pad = %{left: 56, right: 16, top: 12, bottom: 32}
    xs = for %{points: points} <- chart.series, {x, _y} <- points, do: x
    ys = for %{points: points} <- chart.series, {_x, y} <- points, is_number(y), do: y
    {x0, x1} = domain(xs)
    {y0, y1} = domain(ys)
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
      series:
        Enum.map(chart.series, fn %{name: name, points: points} ->
          segments =
            points
            |> Enum.chunk_by(fn {_x, y} -> is_nil(y) end)
            |> Enum.reject(fn [{_x, y} | _rest] -> is_nil(y) end)
            |> Enum.map(fn segment ->
              Enum.map_join(segment, " ", fn {x, y} ->
                "#{round_px(sx.(x))},#{round_px(sy.(y))}"
              end)
            end)

          %{name: name, segments: segments, gaps: Enum.count(points, fn {_x, y} -> is_nil(y) end)}
        end)
    }
  end

  defp axis(encoding, key) do
    case Map.get(encoding, key) do
      %{"field" => field} = axis when is_binary(field) and byte_size(field) in 1..@max_text ->
        {:ok, %{field: field, title: text(Map.get(axis, "title", field))}}

      _other ->
        {:error,
         Error.new(:invalid_axis, :chart, "axis needs a string field", path: "/encoding/" <> key)}
    end
  end

  defp series(values, xf, yf, encoding) do
    key = series_key(encoding)

    values
    |> Enum.reduce_while({%{}, []}, &collect_point(&1, &2, key, xf, yf))
    |> collected_series()
  end

  defp series_key(encoding) do
    case Map.get(encoding, "color") do
      %{"field" => field} when is_binary(field) -> field
      _none -> nil
    end
  end

  defp collect_point(value, {acc, order}, key, xf, yf) when is_map(value) do
    name = if key, do: text(Map.get(value, key, "series")), else: "series"

    case point(Map.get(value, xf), Map.get(value, yf)) do
      {:ok, point} -> {:cont, put_point(acc, order, name, point)}
      :error -> {:halt, invalid_point()}
    end
  end

  defp collect_point(_value, _collected, _key, _xf, _yf), do: {:halt, invalid_point()}

  defp put_point(acc, order, name, point) do
    order = if Map.has_key?(acc, name), do: order, else: order ++ [name]
    {Map.update(acc, name, [point], &[point | &1]), order}
  end

  defp collected_series({:error, %Error{} = error}), do: {:error, error}

  defp collected_series({acc, order}),
    do: {:ok, Enum.map(order, &%{name: &1, points: Enum.reverse(acc[&1])})}

  defp invalid_point,
    do: {:error, Error.new(:invalid_point, :chart, "x must be a finite number")}

  defp point(x, y) when is_number(x) and (is_number(y) or is_nil(y)), do: {:ok, {x, y}}
  defp point(_x, _y), do: :error

  defp bounded(series) do
    cond do
      length(series) > @max_series ->
        {:error, Error.new(:too_many_series, :chart, "at most #{@max_series} series")}

      Enum.any?(series, &(length(&1.points) > @max_points)) ->
        {:error, Error.new(:too_many_points, :chart, "at most #{@max_points} points per series")}

      true ->
        :ok
    end
  end

  defp forbid(map, path) when is_map(map) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      cond do
        not is_binary(key) or key in @forbidden_keys ->
          {:halt,
           {:error,
            Error.new(:forbidden_key, :chart, "key is not admitted",
              path: path <> "/" <> to_string(key)
            )}}

        is_binary(value) and byte_size(value) > @max_text ->
          {:halt,
           {:error,
            Error.new(:text_too_long, :chart, "string exceeds #{@max_text} bytes",
              path: path <> "/" <> key
            )}}

        true ->
          {:cont, forbid(value, path <> "/" <> key)}
      end
    end)
  end

  defp forbid(list, path) when is_list(list) do
    Enum.reduce_while(list, :ok, fn value, :ok -> {:cont, forbid(value, path)} end)
  end

  defp forbid(_value, _path), do: :ok

  defp text(value) when is_binary(value), do: String.slice(value, 0, @max_text)
  defp text(value), do: value |> inspect(limit: 4) |> String.slice(0, @max_text)

  defp domain([]), do: {0, 1}

  defp domain(values) do
    {min, max} = Enum.min_max(values)
    if min == max, do: {min - 1, max + 1}, else: {min, max}
  end

  defp ticks(low, high, count) do
    step = (high - low) / count
    Enum.map(0..count, &(low + &1 * step))
  end

  defp round_px(value), do: Float.round(value * 1.0, 1)
end
