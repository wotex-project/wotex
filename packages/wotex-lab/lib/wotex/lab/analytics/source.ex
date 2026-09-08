defmodule Wotex.Lab.Analytics.Source do
  @moduledoc """
  Admission of bounded run-series previews, before any native dataframe work.

  Values are finite numbers, nil or explicit Nx nonfinite atoms. Missing and
  nonfinite states are retained separately. This is not WoT observation
  admission, a full-tensor conversion, a durable dataset or training data.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest

  @keys ~w(name unit source points method interval dropped)a
  @max_points 2_000
  @max_series 8
  @max_bytes 1_048_576

  @doc "Returns the hard source and browser-preview ceilings."
  @spec limits() :: map()
  def limits,
    do: %{series: @max_series, points: @max_points, bytes: @max_bytes, rows: 100, columns: 32}

  @doc "Validates series and returns their content identity, metadata and scalar rows."
  @spec new(term()) :: {:ok, map()} | {:error, Error.t()}
  def new(series) when is_list(series) and length(series) <= @max_series do
    with :ok <- validate_series(series),
         metadata = Enum.map(series, &metadata/1),
         rows = Enum.flat_map(series, &rows/1),
         canonical = canonical(metadata, rows),
         true <- byte_size(canonical) <= @max_bytes do
      {:ok, %{series: metadata, rows: rows, digest: Digest.bytes(canonical)}}
    else
      {:error, error} -> {:error, error}
      false -> error(:analysis_source_too_large)
    end
  end

  def new(_source), do: error(:invalid_analysis_source)

  defp validate_series(series) do
    Enum.reduce_while(series, MapSet.new(), fn series, names ->
      if valid_series?(series) and not MapSet.member?(names, series.name),
        do: {:cont, MapSet.put(names, series.name)},
        else: {:halt, error(:invalid_analysis_source)}
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp valid_series?(%{name: name, unit: unit, points: points} = series)
       when is_list(points) and length(points) <= @max_points do
    Enum.all?(Map.keys(series), &(&1 in @keys)) and
      text?(name) and text?(unit) and text?(Map.get(series, :source, "run preview")) and
      Map.get(series, :method, "none") in ["none", "minmax-bucket"] and
      interval?(Map.get(series, :interval)) and dropped?(Map.get(series, :dropped, 0)) and
      Enum.all?(points, &point?/1)
  end

  defp valid_series?(_series), do: false
  defp interval?(nil), do: true
  defp interval?(value), do: is_number(value) and value > 0 and value <= 1.0e100
  defp dropped?(value), do: is_integer(value) and value in 0..1_000_000
  defp point?({x, y}), do: number?(x) and (number?(y) or y in [nil, :nan, :infinity, :neg_infinity])
  defp point?(_point), do: false
  defp number?(value) when is_integer(value), do: abs(value) <= 9_007_199_254_740_991
  defp number?(value), do: is_float(value) and abs(value) <= 1.0e100
  defp text?(value), do: is_binary(value) and byte_size(value) in 1..128 and String.valid?(value)

  defp metadata(series) do
    %{
      name: series.name,
      unit: series.unit,
      source: Map.get(series, :source, "run preview"),
      method: Map.get(series, :method, "none"),
      interval: Map.get(series, :interval),
      dropped: Map.get(series, :dropped, 0),
      points: length(series.points)
    }
  end

  # Fixed arrays, not map enumeration order, make identities stable across VMs.
  defp canonical(metadata, rows) do
    sources =
      Enum.map(
        metadata,
        &[&1.name, &1.unit, &1.source, &1.method, &1.interval, &1.dropped, &1.points]
      )

    values =
      Enum.map(rows, &[&1["series"], &1["unit"], &1["x"], &1["value"], &1["state"], &1["position"]])

    JSON.encode!(["wotex-analysis-source-1", sources, values])
  end

  defp rows(series) do
    series.points
    |> Enum.with_index()
    |> Enum.map(fn {{x, y}, index} ->
      %{
        "series" => series.name,
        "unit" => series.unit,
        "x" => x,
        "value" => if(is_number(y), do: y),
        "state" => state(y),
        "position" => index
      }
    end)
  end

  defp state(nil), do: "missing"
  defp state(value) when is_number(value), do: "observed"
  defp state(value), do: Atom.to_string(value)

  defp error(code),
    do: {:error, Error.new(code, :analytics, "source is outside the bounded run-series contract")}
end
