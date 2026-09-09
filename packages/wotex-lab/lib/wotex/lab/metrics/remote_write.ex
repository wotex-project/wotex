defmodule Wotex.Lab.Metrics.RemoteWrite do
  @moduledoc """
  Prometheus Remote Write 1.0 encoder for admitted snapshots.

  The wire body is the `prometheus.WriteRequest` protobuf message compressed
  as one Snappy block. The message layout follows `prompb/remote.proto` and
  `prompb/types.proto` of the Prometheus repository (Apache-2.0), encoded by
  hand here so the base library needs no protobuf dependency:

  | Message | Field | Number | Wire type |
  | --- | --- | --- | --- |
  | `WriteRequest` | `timeseries` (repeated `TimeSeries`) | 1 | length-delimited |
  | `WriteRequest` | reserved | 2 | not written |
  | `WriteRequest` | `metadata` (repeated `MetricMetadata`) | 3 | not written |
  | `TimeSeries` | `labels` (repeated `Label`) | 1 | length-delimited |
  | `TimeSeries` | `samples` (repeated `Sample`) | 2 | length-delimited |
  | `Label` | `name` (string) | 1 | length-delimited |
  | `Label` | `value` (string) | 2 | length-delimited |
  | `Sample` | `value` (double) | 1 | 64-bit little-endian |
  | `Sample` | `timestamp` (int64, milliseconds) | 2 | varint |

  Every series carries `__name__` plus its snapshot labels and the optional
  host-supplied labels, sorted by name and unique; a histogram becomes its
  `_bucket` (with `le`), `_sum` and `_count` series. Samples are ordered by
  timestamp within a series and a repeated timestamp fails the batch. Stale
  markers are encoded as the Prometheus staleness NaN (`0x7ff0000000000002`)
  and `:nan`, `:infinity` and `:neg_infinity` as their IEEE-754 bit patterns;
  they are protocol values only and never enter observations or tensors. The
  reserved headers are exposed by `headers/0` as data. This is a bounded
  exporter encoder, not a query engine, and HTTP success never implies
  exactly-once or lossless delivery.
  """

  import Bitwise

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Snappy, Snapshot}

  @version "0.1.0"
  @stale_nan 0x7FF0000000000002
  @normal_nan 0x7FF8000000000001
  @positive_infinity 0x7FF0000000000000
  @negative_infinity 0xFFF0000000000000
  @max_extra_labels 8

  @type request :: %{
          body: binary(),
          raw_bytes: non_neg_integer(),
          bytes: non_neg_integer(),
          series: non_neg_integer(),
          samples: non_neg_integer(),
          headers: [{String.t(), String.t()}]
        }

  @doc "The reserved remote-write request headers."
  @spec headers() :: [{String.t(), String.t()}]
  def headers do
    [
      {"content-encoding", "snappy"},
      {"content-type", "application/x-protobuf"},
      {"x-prometheus-remote-write-version", @version}
    ]
  end

  @doc "Encodes one snapshot or an ordered batch into a compressed WriteRequest."
  @spec encode(Snapshot.t() | [Snapshot.t()], keyword()) ::
          {:ok, request()} | {:error, Error.t()}
  def encode(snapshots, opts \\ [])

  def encode(%Snapshot{} = snapshot, opts), do: encode([snapshot], opts)

  def encode(snapshots, opts) when is_list(snapshots) and is_list(opts) do
    with :ok <- snapshots?(snapshots),
         {:ok, extra} <- extra_labels(Keyword.get(opts, :labels, [])),
         {:ok, series} <- timeseries(snapshots, extra),
         raw = IO.iodata_to_binary(Enum.map(series, &field(1, message(&1)))),
         {:ok, body} <- Snappy.compress(raw) do
      {:ok,
       %{
         body: body,
         raw_bytes: byte_size(raw),
         bytes: byte_size(body),
         series: length(series),
         samples: series |> Enum.map(&length(&1.samples)) |> Enum.sum(),
         headers: headers()
       }}
    end
  end

  def encode(_, _),
    do: {:error, Error.new(:invalid_batch, :remote_write, "batch must be admitted snapshots")}

  @doc "The 64-bit pattern used for a stale marker."
  @spec stale_marker() :: non_neg_integer()
  def stale_marker, do: @stale_nan

  defp snapshots?(snapshots) do
    if snapshots != [] and Enum.all?(snapshots, &match?(%Snapshot{}, &1)),
      do: :ok,
      else: {:error, Error.new(:invalid_batch, :remote_write, "batch must be admitted snapshots")}
  end

  defp extra_labels(labels) when is_list(labels) and length(labels) <= @max_extra_labels do
    names = Enum.map(labels, &elem(&1, 0))

    if Enum.all?(labels, &label?/1) and names == Enum.uniq(names) and "__name__" not in names,
      do: {:ok, labels},
      else: {:error, Error.new(:invalid_labels, :remote_write, "labels must be unique pairs")}
  end

  defp extra_labels(_),
    do: {:error, Error.new(:invalid_labels, :remote_write, "too many labels")}

  defp label?({name, value}) when is_binary(name) and is_binary(value),
    do: Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, name) and byte_size(value) <= 128

  defp label?(_), do: false

  defp timeseries(snapshots, extra) do
    snapshots
    |> Enum.sort_by(& &1.wall_time_ms)
    |> Enum.flat_map(fn snapshot ->
      Enum.flat_map(snapshot.series, &expand(&1, snapshot.wall_time_ms))
    end)
    |> Enum.reduce_while({:ok, %{}}, fn {labels, sample}, {:ok, acc} ->
      case merge(labels, extra) do
        {:ok, merged} -> {:cont, {:ok, Map.update(acc, merged, [sample], &[sample | &1])}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, grouped} -> ordered(grouped)
      error -> error
    end
  end

  defp expand(%{type: :histogram} = series, timestamp) do
    %{buckets: buckets, sum: sum, count: count} = series.sample
    stale? = Map.get(series.sample, :stale, false)
    name = series.name

    Enum.map(buckets, fn {le, value} ->
      {[{"__name__", name <> "_bucket"}, {"le", format(le)} | series.labels],
       {timestamp, if(stale?, do: :stale, else: value)}}
    end) ++
      [
        {[{"__name__", name <> "_sum"} | series.labels], {timestamp, sum}},
        {[{"__name__", name <> "_count"} | series.labels],
         {timestamp, if(stale?, do: :stale, else: count)}}
      ]
  end

  defp expand(series, timestamp),
    do: [{[{"__name__", series.name} | series.labels], {timestamp, series.sample.value}}]

  defp merge(labels, extra) do
    merged = Enum.sort_by(labels ++ extra, &elem(&1, 0))
    names = Enum.map(merged, &elem(&1, 0))

    if names == Enum.uniq(names),
      do: {:ok, merged},
      else:
        {:error,
         Error.new(:label_conflict, :remote_write, "host label collides with a series label")}
  end

  defp ordered(grouped) do
    grouped
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {labels, samples}, {:ok, acc} ->
      samples = Enum.sort_by(samples, &elem(&1, 0))
      timestamps = Enum.map(samples, &elem(&1, 0))

      if timestamps == Enum.uniq(timestamps),
        do: {:cont, {:ok, [%{labels: labels, samples: samples} | acc]}},
        else:
          {:halt,
           {:error, Error.new(:unordered_samples, :remote_write, "a series repeats a timestamp")}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp message(%{labels: labels, samples: samples}) do
    IO.iodata_to_binary([
      Enum.map(labels, fn {name, value} -> field(1, string(1, name) <> string(2, value)) end),
      Enum.map(samples, fn {timestamp, value} ->
        field(2, double(1, value) <> int64(2, timestamp))
      end)
    ])
  end

  defp field(number, bytes), do: [key(number, 2), varint(byte_size(bytes)), bytes]

  defp string(number, value), do: IO.iodata_to_binary(field(number, value))

  defp double(number, value), do: IO.iodata_to_binary([key(number, 1), bits(value)])

  defp int64(number, value) when value >= 0,
    do: IO.iodata_to_binary([key(number, 0), varint(value)])

  defp int64(number, value),
    do: IO.iodata_to_binary([key(number, 0), varint(value + (1 <<< 64))])

  defp key(number, wire), do: varint(number <<< 3 ||| wire)

  defp varint(value) when value < 128, do: <<value>>
  defp varint(value), do: <<1::1, value::7, varint(value >>> 7)::binary>>

  defp bits(:stale), do: <<@stale_nan::unsigned-little-64>>
  defp bits(:nan), do: <<@normal_nan::unsigned-little-64>>
  defp bits(:infinity), do: <<@positive_infinity::unsigned-little-64>>
  defp bits(:neg_infinity), do: <<@negative_infinity::unsigned-little-64>>
  defp bits(value) when is_number(value), do: <<value * 1.0::little-float-64>>

  defp format(:infinity), do: "+Inf"
  defp format(value) when is_integer(value), do: Integer.to_string(value)
  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
end
