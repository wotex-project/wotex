defmodule WotexLabWorkbench.Preview do
  @moduledoc """
  Bounded browser previews of tensors and timeseries.

  The server limits before anything is transferred: at most 100 rows and 32
  columns of a batch, and at most 2,000 points per series. Downsampling is
  min-max bucketing over fixed intervals: every bucket keeps its minimum and
  maximum in input order, with gap sentinels before, between and after those
  extrema as needed. Missing stretches may coalesce, but no retained line
  crosses an omitted gap. Missing, masked-out and nonfinite
  values are labelled as such and never rendered as zero. Full tensors are
  never copied to host lists beyond the preview window.
  """

  alias Wotex.Lab.Error
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
  preview. The lazy batch is split before stacking, unselected features are
  not built, and selected tensors are sliced before host list conversion.
  Counts describe preview elements only, not the entire encoded batch.
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
      feature_order: encoded |> Encoded.feature_order() |> Enum.take(@max_columns),
      preview_bounds: %{
        rows: min(rows, @max_rows),
        features: min(length(features), @max_columns),
        total_features: length(features),
        elements_per_feature: @max_columns,
        truncated:
          rows > @max_rows or length(features) > @max_columns or
            Enum.any?(features, &(Tuple.product(&1.shape) > @max_columns))
      },
      features:
        features
        |> Enum.take(@max_columns)
        |> Enum.with_index()
        |> Enum.map(fn {feature, index} ->
          %{
            name: feature.name,
            dtype: dtype(elem(values, index)),
            shape: shape(elem(values, index)),
            mask_dtype: dtype(elem(masks, index)),
            unit: unit(feature),
            observed: realized_masks |> Enum.at(index) |> List.flatten() |> Enum.count(&(&1 == 1)),
            filled: realized_masks |> Enum.at(index) |> List.flatten() |> Enum.count(&(&1 == 0))
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
  points with the method, bucket interval (input points) and dropped count.
  A downsampling budget below five cannot guarantee extrema and gap sentinels
  together and is refused. The absolute ceiling remains 2,000 points.
  """
  @spec downsample([point()], pos_integer()) ::
          %{
            points: [point()],
            method: String.t(),
            interval: number() | nil,
            dropped: non_neg_integer()
          }
          | {:error, Error.t()}
  def downsample(points, max \\ @max_points)

  def downsample(points, max) when is_list(points) and is_integer(max) and max in 2..@max_points do
    points = Enum.map(points, &finite/1)
    count = length(points)

    cond do
      count <= max ->
        %{points: points, method: "none", interval: nil, dropped: 0}

      max < 5 ->
        invalid_budget()

      true ->
        buckets = div(max, 5)
        size = div(count + buckets - 1, buckets)

        kept =
          points
          |> Enum.chunk_every(size)
          |> Enum.flat_map(&bucket/1)

        %{
          points: kept,
          method: "minmax-bucket",
          interval: size,
          dropped: count - length(kept)
        }
    end
  end

  def downsample(_points, _max), do: invalid_budget()

  defp invalid_budget,
    do:
      {:error,
       Error.new(
         :invalid_preview_budget,
         :preview,
         "cannot preserve extrema and gaps within this budget"
       )}

  defp bucket(chunk) do
    indexed = Enum.with_index(chunk)
    {gaps, present} = Enum.split_with(indexed, fn {{_x, y}, _index} -> is_nil(y) end)

    case present do
      [] ->
        [hd(chunk)]

      _values ->
        extrema = [
          Enum.min_by(present, fn {{_x, y}, _i} -> y end),
          Enum.max_by(present, fn {{_x, y}, _i} -> y end)
        ]

        {first, last} = extrema |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

        sentinels =
          gaps
          |> Enum.group_by(fn {_point, i} -> gap_position(i, first, last) end)
          |> Enum.map(fn {_position, values} -> hd(values) end)

        (extrema ++ sentinels)
        |> Enum.uniq()
        |> Enum.sort_by(&elem(&1, 1))
        |> Enum.map(&elem(&1, 0))
    end
  end

  defp gap_position(i, first, _last) when i < first, do: :before
  defp gap_position(i, _first, last) when i > last, do: :after
  defp gap_position(_i, _first, _last), do: :between

  defp finite({x, y}) when is_number(y), do: {x, y}
  defp finite({x, _other}), do: {x, nil}

  defp realize(encoded) do
    {batch, _rest} = encoded |> Encoded.batch() |> Nx.Batch.split(@max_rows)

    {_template, reversed} =
      Nx.LazyContainer.traverse(batch, [], fn template, build, builders ->
        {template, [build | builders]}
      end)

    count = encoded |> Encoded.feature_order() |> length()
    {values, rest} = reversed |> Enum.reverse() |> Enum.split(count)
    {masks, [quality]} = Enum.split(rest, count)

    {
      values |> Enum.take(@max_columns) |> Enum.map(&column/1),
      masks |> Enum.take(@max_columns) |> Enum.map(&column/1),
      quality.() |> bounded_matrix() |> Nx.to_list()
    }
  end

  defp column(build) do
    tensor = build.()

    if Nx.rank(tensor) == 1,
      do: Nx.to_list(tensor),
      else: tensor |> bounded_matrix() |> Nx.to_list()
  end

  defp bounded_matrix(tensor) do
    matrix = Nx.reshape(tensor, {Nx.axis_size(tensor, 0), :auto})
    Nx.slice_along_axis(matrix, 0, min(Nx.axis_size(matrix, 1), @max_columns), axis: 1)
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

  defp cell_text(value, mask) when is_list(mask) do
    if Enum.all?(List.flatten(mask), &(&1 == 0)),
      do: format(value) <> " (filled, mask 0)",
      else: format(value)
  end

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
