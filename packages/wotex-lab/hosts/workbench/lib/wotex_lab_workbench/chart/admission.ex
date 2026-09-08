defmodule WotexLabWorkbench.Chart.Admission do
  @moduledoc "Closed, bounded normalization for the workbench's native SVG charts."

  alias Wotex.Lab.Error

  @marks ~w(line area point)
  @max_text 128

  @doc "Builds a renderer-neutral chart after admitting the series and option envelope."
  @spec build(term()) :: {:ok, map()} | {:error, Error.t()}
  def build(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in [:title, :mark, :x, :y, :series])),
         series when is_list(series) and length(series) <= 8 <- Keyword.get(opts, :series, []),
         :ok <- input_series(series),
         {:ok, x} <- input_axis(Keyword.get(opts, :x, %{field: "x", title: "x"})),
         {:ok, y} <- input_axis(Keyword.get(opts, :y, %{field: "y", title: "y"})),
         title = Keyword.get(opts, :title, "Chart"),
         mark = Keyword.get(opts, :mark, "line"),
         :ok <- text(title, "/title"),
         true <- mark in @marks,
         true <- x.field != y.field do
      {:ok, %{title: title, mark: mark, x: x, y: y, series: series}}
    else
      {:error, error} -> {:error, error}
      series when is_list(series) and length(series) > 8 -> error(:too_many_series)
      _invalid -> error(:invalid_chart)
    end
  end

  def build(_opts), do: error(:invalid_chart)

  defp input_series(series) do
    Enum.reduce_while(series, MapSet.new(), fn
      %{name: name, points: points} = item, names
      when map_size(item) == 2 and is_list(points) and length(points) <= 2_000 ->
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

  defp point?({x, y}), do: number?(x) and (is_nil(y) or number?(y))
  defp point?(_point), do: false

  defp input_axis(%{field: field, title: title} = axis) when map_size(axis) == 2 do
    if field != "series" and text(field, "") == :ok and text(title, "") == :ok,
      do: {:ok, axis},
      else: error(:invalid_axis)
  end

  defp input_axis(_axis), do: error(:invalid_axis)

  defp number?(value), do: is_number(value) and abs(value) <= 1.0e100

  defp text(value, path) when is_binary(value) and byte_size(value) in 1..@max_text,
    do: if(String.valid?(value), do: :ok, else: error(:invalid_chart, path))

  defp text(value, path) when is_binary(value), do: error(:text_too_long, path)
  defp text(_value, path), do: error(:invalid_chart, path)

  defp error(code, path \\ ""),
    do:
      {:error, Error.new(code, :chart, "chart is outside the admitted bounded subset", path: path)}
end
