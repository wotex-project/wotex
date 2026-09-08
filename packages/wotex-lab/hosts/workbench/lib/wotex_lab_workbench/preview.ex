defmodule WotexLabWorkbench.Preview do
  @moduledoc """
  Bounded browser previews of tensors and timeseries.

  The server limits before anything is transferred: at most 100 rows and 32
  columns of a batch, and at most 2,000 points per series. Downsampling is
  min-max bucketing over fixed intervals: every bucket keeps its minimum and
  maximum in time order, and a bucket that contains a gap keeps the gap, so
  extrema and missing stretches survive. Missing, masked-out and nonfinite
  values are labelled as such and never rendered as zero. Full tensors are
  never realized for the browser beyond the preview window.
  """

  alias Wotex.Nx.{Encoded, Schema}

  @max_rows 100
  @max_columns 32
  @max_points 2_000

  @type point :: {number(), number() | nil}

  @doc "Row, column and point ceilings."
  @spec limits() :: %{rows: pos_integer(), columns: pos_integer(), points: pos_integer()}
  def limits, do: %{rows: @max_rows, columns: @max_columns, points: @max_points}

  @doc """
  Summarizes an encoded batch: dtype, shape and layout from the template,
  the backend name, units, mask and quality counts, and a bounded value
  preview realized through `Nx.Defn.Evaluator` on the batch only.
  """
  @spec tensor_summary(Encoded.t(), module()) :: map()
  def tensor_summary(encoded, backend) when is_atom(backend) do
    {values, masks, quality} = Encoded.template(encoded)
    features = encoded |> Encoded.schema() |> Schema.features()
    rows = Encoded.row_count(encoded)
    {realized_values, realized_masks, realized_quality} = realize(encoded)
    codes = Wotex.Nx.quality_codes()

    %{
      layout: Atom.to_string(Encoded.layout(encoded)),
      backend: inspect(backend),
      rows: rows,
      feature_order: Encoded.feature_order(encoded),
      features:
        features
        |> Enum.with_index()
        |> Enum.map(fn {feature, index} ->
          %{
            name: feature.name,
            dtype: dtype(elem(values, index)),
            shape: shape(elem(values, index)),
            mask_dtype: dtype(elem(masks, index)),
            unit: unit(feature),
            observed: Enum.count(Enum.at(realized_masks, index), &(&1 == 1)),
            filled: Enum.count(Enum.at(realized_masks, index), &(&1 == 0))
          }
        end),
      quality: %{dtype: dtype(quality), shape: shape(quality), codes: codes},
      preview:
        preview_rows(Encoded.timestamps(encoded), realized_values, realized_masks, realized_quality)
    }
  end

  @doc "Formats a value for display; nothing missing or nonfinite becomes a number."
  @spec format(term()) :: String.t()
  def format(nil), do: "missing"
  def format(:nan), do: "nonfinite (nan)"
  def format(:infinity), do: "nonfinite (+inf)"
  def format(:neg_infinity), do: "nonfinite (-inf)"
  def format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  def format(value) when is_integer(value), do: Integer.to_string(value)
  def format(value) when is_binary(value), do: value
  def format(value) when is_atom(value), do: Atom.to_string(value)
  def format(value), do: inspect(value, limit: 8, printable_limit: 64)

  @doc """
  Downsamples points to at most `max` by min-max bucketing; returns the
  points with the method, bucket interval and whether anything was dropped.
  """
  @spec downsample([point()], pos_integer()) :: %{
          points: [point()],
          method: String.t(),
          interval: number() | nil,
          dropped: non_neg_integer()
        }
  def downsample(points, max \\ @max_points) when is_list(points) and max >= 2 do
    points = Enum.map(points, &finite/1)
    count = length(points)

    if count <= max do
      %{points: points, method: "none", interval: nil, dropped: 0}
    else
      buckets = if(max == 2, do: 1, else: max(div(max, 3), 1))
      size = div(count + buckets - 1, buckets)

      kept =
        points
        |> Enum.chunk_every(size)
        |> Enum.flat_map(&bucket/1)
        |> Enum.take(max)

      %{
        points: kept,
        method: "minmax-bucket",
        interval: size,
        dropped: count - length(kept)
      }
    end
  end

  defp bucket(chunk) do
    present = Enum.reject(chunk, fn {_x, y} -> is_nil(y) end)
    gap = Enum.find(chunk, fn {_x, y} -> is_nil(y) end)

    extrema =
      case present do
        [] -> []
        _values -> [Enum.min_by(present, &elem(&1, 1)), Enum.max_by(present, &elem(&1, 1))]
      end

    (extrema ++ List.wrap(gap))
    |> Enum.uniq()
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp finite({x, y}) when is_number(y), do: {x, y}
  defp finite({x, _other}), do: {x, nil}

  defp realize(encoded) do
    {values, masks, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [encoded], compiler: Nx.Defn.Evaluator)

    {
      values |> Tuple.to_list() |> Enum.map(&column/1),
      masks |> Tuple.to_list() |> Enum.map(&column/1),
      quality |> Nx.to_list() |> Enum.take(@max_rows)
    }
  end

  defp column(tensor) do
    tensor
    |> Nx.to_list()
    |> Enum.take(@max_rows)
    |> Enum.map(fn
      row when is_list(row) -> row |> List.flatten() |> Enum.take(@max_columns)
      scalar -> scalar
    end)
  end

  defp preview_rows(timestamps, values, masks, quality) do
    timestamps
    |> Enum.take(@max_rows)
    |> Enum.with_index()
    |> Enum.map(fn {timestamp, row} ->
      %{
        timestamp: timestamp,
        cells:
          values
          |> Enum.with_index()
          |> Enum.map(fn {column, feature} ->
            mask = masks |> Enum.at(feature) |> Enum.at(row)
            code = quality |> Enum.at(row) |> List.wrap() |> Enum.at(feature)
            value = Enum.at(column, row)

            %{
              value: value,
              text: cell_text(value, mask),
              mask: mask,
              quality: code
            }
          end)
      }
    end)
  end

  defp cell_text(value, 0), do: format(value) <> " (filled, mask 0)"
  defp cell_text(value, _mask), do: format(value)

  defp dtype(%Nx.Tensor{} = tensor) do
    {kind, bits} = Nx.type(tensor)
    "#{kind}#{bits}"
  end

  defp shape(%Nx.Tensor{} = tensor), do: tensor |> Nx.shape() |> Tuple.to_list()

  defp unit(%{data_schema: schema}) do
    schema
    |> Map.from_struct()
    |> Map.get(:unit)
    |> case do
      nil -> Map.get(Wotex.DataSchema.to_map(schema), "unit", "none")
      unit -> unit
    end
  rescue
    _error -> "none"
  end
end
