defmodule WotexLabWorkbench.Chart.Admission do
  @moduledoc "Closed, bounded normalization for the workbench's Vega-Lite subset."

  alias Wotex.Lab.Error

  @schema "https://vega.github.io/schema/vega-lite/v6.json"
  @marks ~w(line area point)
  @max_text 128

  @doc "Builds a specification after admitting the series and option envelope."
  @spec build(term()) :: {:ok, map()} | {:error, Error.t()}
  def build(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in [:title, :mark, :x, :y, :series])),
         series when is_list(series) and length(series) <= 8 <- Keyword.get(opts, :series, []),
         :ok <- input_series(series),
         {:ok, x} <- input_axis(Keyword.get(opts, :x, %{field: "x", title: "x"})),
         {:ok, y} <- input_axis(Keyword.get(opts, :y, %{field: "y", title: "y"})),
         true <- x.field != y.field do
      {:ok,
       %{
         "$schema" => @schema,
         "title" => Keyword.get(opts, :title, "Chart"),
         "mark" => Keyword.get(opts, :mark, "line"),
         "data" => %{"values" => values(series, x.field, y.field)},
         "encoding" => %{
           "x" => %{"field" => x.field, "type" => "quantitative", "title" => x.title},
           "y" => %{"field" => y.field, "type" => "quantitative", "title" => y.title},
           "color" => %{"field" => "series", "type" => "nominal"}
         }
       }}
    else
      {:error, error} -> {:error, error}
      series when is_list(series) and length(series) > 8 -> error(:too_many_series)
      _invalid -> error(:invalid_chart)
    end
  end

  def build(_opts), do: error(:invalid_chart)

  @doc "Admits only a fixed dialect, scalar axes and bounded inline point records."
  @spec normalize(term()) :: {:ok, map()} | {:error, Error.t()}
  def normalize(%{"data" => %{"url" => _url}}), do: error(:external_data, "/data/url")

  def normalize(%{"mark" => mark, "data" => %{"values" => values} = data, "encoding" => enc} = spec)
      when mark in @marks and is_list(values) and length(values) <= 16_000 and is_map(enc) do
    with :ok <- keys(spec, ~w($schema title mark data encoding), ""),
         :ok <- keys(data, ~w(values), "/data"),
         :ok <- keys(enc, ~w(x y color), "/encoding"),
         true <- Map.get(spec, "$schema", @schema) == @schema,
         :ok <- text(Map.get(spec, "title", "Chart"), "/title"),
         {:ok, x} <- axis(enc["x"], "/encoding/x"),
         {:ok, y} <- axis(enc["y"], "/encoding/y"),
         {:ok, color} <- color(enc["color"]),
         true <- x.field != y.field and color not in [x.field, y.field],
         {:ok, series} <- collect(values, x.field, y.field, color) do
      {:ok, %{title: Map.get(spec, "title", "Chart"), mark: mark, x: x, y: y, series: series}}
    else
      {:error, error} -> {:error, error}
      _invalid -> error(:invalid_chart)
    end
  end

  def normalize(_spec), do: error(:invalid_chart)

  defp input_series(series) do
    Enum.reduce_while(series, MapSet.new(), fn
      %{name: name, points: points}, names when is_list(points) and length(points) <= 2_000 ->
        valid =
          not MapSet.member?(names, name) and text(name, "/series/name") == :ok and
            Enum.all?(points, &point?/1)

        if valid,
          do: {:cont, MapSet.put(names, name)},
          else: {:halt, error(:invalid_point)}

      %{points: points}, _names when is_list(points) and length(points) > 2_000 ->
        {:halt, error(:too_many_points)}

      _invalid, _names ->
        {:halt, error(:invalid_chart)}
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp values(series, xf, yf) do
    Enum.flat_map(series, fn %{name: name, points: points} ->
      Enum.map(points, fn {x, y} -> %{xf => x, yf => y, "series" => name} end)
    end)
  end

  defp point?({x, y}), do: number?(x) and (is_nil(y) or number?(y))
  defp point?(_point), do: false

  defp input_axis(%{field: field, title: title} = axis) when map_size(axis) == 2 do
    if field != "series" and text(field, "") == :ok and text(title, "") == :ok,
      do: {:ok, axis},
      else: error(:invalid_axis)
  end

  defp input_axis(_axis), do: error(:invalid_axis)

  defp axis(%{"field" => field} = axis, path) do
    with :ok <- keys(axis, ~w(field type title), path),
         :ok <- text(field, path <> "/field"),
         :ok <- text(Map.get(axis, "title", field), path <> "/title"),
         true <- Map.get(axis, "type", "quantitative") == "quantitative" do
      {:ok, %{field: field, title: Map.get(axis, "title", field)}}
    else
      {:error, error} -> {:error, error}
      _invalid -> error(:invalid_axis, path)
    end
  end

  defp axis(_axis, path), do: error(:invalid_axis, path)

  defp color(nil), do: {:ok, nil}

  defp color(%{"field" => field} = color) do
    with :ok <- keys(color, ~w(field type), "/encoding/color"),
         :ok <- text(field, "/encoding/color/field"),
         true <- Map.get(color, "type", "nominal") == "nominal" do
      {:ok, field}
    else
      {:error, error} -> {:error, error}
      _invalid -> error(:invalid_axis)
    end
  end

  defp color(_color), do: error(:invalid_axis)

  defp collect(values, xf, yf, color) do
    values
    |> Enum.reduce_while({%{}, []}, &collect_point(&1, &2, xf, yf, color))
    |> case do
      {:error, error} -> {:error, error}
      {groups, order} -> {:ok, Enum.map(order, &%{name: &1, points: Enum.reverse(groups[&1])})}
    end
  end

  defp collect_point(value, acc, xf, yf, color) do
    with :ok <- keys(value, [xf, yf | List.wrap(color)], "/data/values"),
         true <- point?({value[xf], value[yf]}),
         name = if(color, do: Map.get(value, color, "series"), else: "series"),
         :ok <- text(name, "/data/values/series"),
         {:ok, next} <- put(acc, name, {value[xf], value[yf]}) do
      {:cont, next}
    else
      {:error, error} -> {:halt, {:error, error}}
      _invalid -> {:halt, error(:invalid_point)}
    end
  end

  defp put({groups, order}, name, point) do
    points = Map.get(groups, name, [])

    cond do
      points == [] and map_size(groups) == 8 ->
        error(:too_many_series)

      length(points) == 2_000 ->
        error(:too_many_points)

      true ->
        {:ok,
         {Map.put(groups, name, [point | points]),
          if(points == [], do: order ++ [name], else: order)}}
    end
  end

  defp keys(map, allowed, path) when is_map(map) do
    case Enum.find_value(Map.keys(map), &if(&1 not in allowed, do: {:unknown, &1})) do
      nil ->
        :ok

      {:unknown, key} when is_binary(key) ->
        error(:forbidden_key, path <> "/" <> String.slice(key, 0, 128))

      _key ->
        error(:forbidden_key, path)
    end
  end

  defp keys(_value, _allowed, _path), do: error(:invalid_point)
  defp number?(value), do: is_number(value) and abs(value) <= 1.0e100

  defp text(value, path) when is_binary(value) and byte_size(value) in 1..@max_text,
    do: if(String.valid?(value), do: :ok, else: error(:invalid_chart, path))

  defp text(value, path) when is_binary(value), do: error(:text_too_long, path)
  defp text(_value, path), do: error(:invalid_chart, path)

  defp error(code, path \\ ""),
    do:
      {:error, Error.new(code, :chart, "chart is outside the admitted bounded subset", path: path)}
end
