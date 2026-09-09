# This profile is compiled only when the consumer explicitly selects Explorer.
if Code.ensure_loaded?(Explorer.DataFrame) do
  defmodule Wotex.Lab.Analytics do
    @moduledoc """
    Optional Explorer/Polars analysis shared by notebook and LiveView hosts.

    `analyze/2` accepts bounded named series, not a user dataframe, expression,
    module, SQL query, URL or filesystem path. It applies a closed range/series
    filter and computes per-series, per-unit counts, mean and extrema in Polars.
    Filtering and aggregation precede bounded materialization. Missing and
    nonfinite counts remain distinct; no nil-to-zero tensor conversion occurs.

    Results identify both the supplied preview and admitted query. They are
    derived insights, not replacement run evidence, training data, authorization
    or a guarantee about measurements omitted from the supplied preview.
    """

    alias Explorer.DataFrame, as: DF
    alias Explorer.Series, as: S
    alias Wotex.Lab.Analytics.{Query, Source}
    alias Wotex.Lab.Error
    alias Wotex.Lab.Evidence.Digest

    @dtypes [series: :string, unit: :string, x: :f64, value: :f64, state: :string, position: :s64]

    @doc "Analyzes an admitted run preview; opts are series, from, to and limit."
    @spec analyze(term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
    def analyze(series, opts \\ []) do
      with {:ok, source} <- Source.new(series),
           {:ok, query} <- Query.new(opts, Enum.map(source.series, & &1.name)) do
        execute(source, query)
      end
    end

    defp execute(source, query) do
      frame = source.rows |> columns() |> DF.new(backend: Explorer.PolarsBackend, dtypes: @dtypes)
      filtered = frame |> DF.lazy() |> select(query.series) |> range(query.from, query.to)

      summary =
        filtered
        |> DF.group_by(["series", "unit"])
        |> DF.summarise_with(&summary/1)
        |> DF.collect()
        |> DF.to_rows()

      total = Enum.sum(Enum.map(summary, &(&1["observed"] + &1["missing"] + &1["nonfinite"])))
      preview = filtered |> DF.head(query.limit) |> DF.collect() |> DF.to_rows()
      # Source admission caps all plot rows at eight series of 2,000 points.
      points = filtered |> DF.collect() |> DF.to_rows()

      {:ok,
       %{
         source: "run preview",
         source_digest: source.digest,
         query_digest: query_digest(source.digest, query),
         query: query,
         series: source.series,
         summary: Enum.sort_by(summary, & &1["series"]),
         preview: preview,
         total_rows: total,
         truncated: total > length(preview),
         plots: plots(points, source.series),
         backend: "Explorer.PolarsBackend",
         value_dtype: "f64"
       }}
    rescue
      _ ->
        {:error,
         Error.new(:analysis_unavailable, :analytics, "native analysis failed; no result admitted")}
    end

    defp query_digest(source, query),
      do:
        Digest.bytes(
          JSON.encode!([
            "wotex-analysis-query-1",
            source,
            query.series,
            query.from,
            query.to,
            query.limit
          ])
        )

    defp columns(rows) do
      Map.new(@dtypes, fn {key, _} ->
        field = Atom.to_string(key)
        {field, Enum.map(rows, & &1[field])}
      end)
    end

    defp select(frame, nil), do: frame
    defp select(frame, name), do: DF.filter_with(frame, &S.equal(&1["series"], name))

    defp range(frame, from, to) do
      frame =
        if is_nil(from), do: frame, else: DF.filter_with(frame, &S.greater_equal(&1["x"], from))

      if is_nil(to), do: frame, else: DF.filter_with(frame, &S.less_equal(&1["x"], to))
    end

    defp summary(frame) do
      [
        observed: S.count(frame["value"]),
        missing: frame["state"] |> S.equal("missing") |> S.cast(:s64) |> S.sum(),
        nonfinite:
          frame["state"] |> S.in(["nan", "infinity", "neg_infinity"]) |> S.cast(:s64) |> S.sum(),
        mean: S.mean(frame["value"]),
        minimum: S.min(frame["value"]),
        maximum: S.max(frame["value"])
      ]
    end

    defp plots(rows, series) do
      groups = Enum.group_by(rows, & &1["series"])

      Enum.flat_map(series, fn series ->
        case Map.fetch(groups, series.name) do
          {:ok, values} ->
            [
              %{
                name: series.name,
                unit: series.unit,
                points: Enum.map(values, &{&1["x"], &1["value"]})
              }
            ]

          :error ->
            []
        end
      end)
    end
  end
end
