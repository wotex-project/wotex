defmodule Wotex.Lab.Metrics.Snapshot do
  @moduledoc """
  The admitted metric snapshot: one bounded, schema-versioned reading of a
  series set at one point in time.

  The collector produces it from aggregated telemetry and the exposition parser
  produces the same shape from Prometheus text, so history, queries and
  the remote-write encoder never care where a snapshot came from. Every series
  carries a Prometheus name, a `:counter`, `:gauge` or `:histogram` type,
  sorted unique string labels and one sample: a number (or `:stale`, `:nan`,
  `:infinity`, `:neg_infinity` as protocol values that never become WoT
  observations) for counters and gauges, and cumulative `{le, count}` buckets
  ending in `:infinity` plus `sum` and `count` for histograms.

  `new/1` validates the shape and returns a typed error with a pointer path;
  `encoded_size/1` is the byte cost history charges against its budget;
  `stale_markers/2` names the series that disappeared between two snapshots so
  an exporter can emit stale markers instead of letting a last value linger.
  Missing, stale, dropped and zero therefore stay distinguishable: a series
  that is absent is missing, a `:stale` sample is stale, the `counters` map
  records what was dropped, and `0` is a measured zero.
  """

  alias Wotex.Lab.Error

  @schema_version "1.0.0"
  @types [:counter, :gauge, :histogram]
  @sources [:collector, :exposition]
  @specials [:stale, :nan, :infinity, :neg_infinity]
  @max_series 100_000
  @max_labels 16
  @name ~r/\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/
  @label_name ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @type special :: :stale | :nan | :infinity | :neg_infinity
  @type value :: number() | special()
  @type bucket :: {number() | :infinity, non_neg_integer()}
  @type label :: {String.t(), String.t()}

  @type series :: %{
          required(:name) => String.t(),
          required(:type) => :counter | :gauge | :histogram,
          required(:labels) => [label()],
          required(:sample) =>
            %{value: value()}
            | %{buckets: [bucket()], sum: value(), count: non_neg_integer()}
        }

  @type t :: %__MODULE__{
          schema_version: String.t(),
          source: :collector | :exposition,
          instance_slot: non_neg_integer(),
          sequence: non_neg_integer(),
          monotonic_ms: integer(),
          wall_time_ms: integer(),
          identity: %{started_at: integer(), generation: non_neg_integer()} | nil,
          series: [series()],
          counters: %{atom() => non_neg_integer()}
        }

  @enforce_keys [:source, :instance_slot, :sequence, :monotonic_ms, :wall_time_ms, :series]
  defstruct [
    {:schema_version, @schema_version},
    :source,
    :instance_slot,
    :sequence,
    :monotonic_ms,
    :wall_time_ms,
    :series,
    identity: nil,
    counters: %{}
  ]

  @doc "The snapshot schema version written and read by this module."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "Builds a validated snapshot; series are sorted by name and labels."
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{} = fields) do
    fields = Map.put_new(fields, :schema_version, @schema_version)

    with :ok <- check(fields[:schema_version] == @schema_version, :unsupported_schema_version, ""),
         :ok <- check(fields[:source] in @sources, :invalid_source, "/source"),
         :ok <- slot(fields[:instance_slot]),
         :ok <- check(non_neg?(fields[:sequence]), :invalid_sequence, "/sequence"),
         :ok <- check(is_integer(fields[:monotonic_ms]), :invalid_time, "/monotonic_ms"),
         :ok <- check(non_neg?(fields[:wall_time_ms]), :invalid_time, "/wall_time_ms"),
         :ok <- identity(fields[:identity]),
         :ok <- counters(Map.get(fields, :counters, %{})),
         {:ok, series} <- series(fields[:series]) do
      {:ok,
       struct!(__MODULE__, %{
         source: fields.source,
         instance_slot: fields.instance_slot,
         sequence: fields.sequence,
         monotonic_ms: fields.monotonic_ms,
         wall_time_ms: fields.wall_time_ms,
         identity: fields[:identity],
         series: series,
         counters: Map.get(fields, :counters, %{})
       })}
    end
  end

  def new(_fields), do: {:error, error(:invalid_snapshot, "", "snapshot fields must be a map")}

  @doc "Encoded size in bytes, the cost history charges against its byte budget."
  @spec encoded_size(t()) :: pos_integer()
  def encoded_size(%__MODULE__{} = snapshot), do: :erlang.external_size(snapshot)

  @doc "Series present in `previous` and absent in `current`, as stale-marker series."
  @spec stale_markers(t(), t()) :: [series()]
  def stale_markers(%__MODULE__{} = previous, %__MODULE__{} = current) do
    live = MapSet.new(current.series, &{&1.name, &1.labels})

    previous.series
    |> Enum.reject(&MapSet.member?(live, {&1.name, &1.labels}))
    |> Enum.map(&stale/1)
  end

  @doc "Normalizes a numeric sample: integral floats become integers so sources compare equal."
  @spec number(number() | special()) :: value()
  def number(value) when is_float(value) do
    if value == Float.floor(value) and abs(value) < 9.0e15, do: trunc(value), else: value
  end

  def number(value), do: value

  @doc "True for a sample value this schema admits."
  @spec value?(term()) :: boolean()
  def value?(value) when is_number(value), do: true
  def value?(value), do: value in @specials

  defp stale(%{type: :histogram} = series) do
    buckets = Enum.map(series.sample.buckets, fn {le, _count} -> {le, 0} end)
    %{series | sample: %{buckets: buckets, sum: :stale, count: 0, stale: true}}
  end

  defp stale(series), do: %{series | sample: %{value: :stale}}

  defp slot(slot) when is_integer(slot) and slot >= 0 and slot < 65_536, do: :ok

  defp slot(_slot),
    do: {:error, error(:invalid_instance_slot, "/instance_slot", "slot is unbounded")}

  defp identity(nil), do: :ok

  defp identity(%{started_at: started, generation: generation})
       when is_integer(started) and is_integer(generation) and generation >= 0,
       do: :ok

  defp identity(_identity),
    do: {:error, error(:invalid_identity, "/identity", "identity needs started_at and generation")}

  defp counters(map) when is_map(map) do
    if Enum.all?(map, fn {key, value} -> is_atom(key) and non_neg?(value) end),
      do: :ok,
      else: {:error, error(:invalid_counters, "/counters", "counters must be atom => count")}
  end

  defp counters(_map), do: {:error, error(:invalid_counters, "/counters", "counters must be a map")}

  defp series(list) when is_list(list) and length(list) <= @max_series do
    list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {series, index}, {:ok, acc} ->
      case one_series(series, "/series/#{index}") do
        {:ok, series} -> {:cont, {:ok, [series | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> unique(Enum.sort_by(acc, &{&1.name, &1.labels}))
      error -> error
    end
  end

  defp series(_list),
    do: {:error, error(:invalid_series, "/series", "series must be a bounded list")}

  defp unique(sorted) do
    duplicate =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [a, b] -> a.name == b.name and a.labels == b.labels end)

    case duplicate do
      nil -> {:ok, sorted}
      [a, _b] -> {:error, error(:duplicate_series, "/series", "duplicate series", %{name: a.name})}
    end
  end

  defp one_series(%{name: name, type: type, labels: labels, sample: sample}, path) do
    with :ok <- check(is_binary(name) and Regex.match?(@name, name), :invalid_name, path <> "/name"),
         :ok <- check(type in @types, :invalid_type, path <> "/type"),
         :ok <- labels(labels, path <> "/labels"),
         :ok <- sample(type, sample, path <> "/sample") do
      {:ok, %{name: name, type: type, labels: labels, sample: sample}}
    end
  end

  defp one_series(_series, path),
    do: {:error, error(:invalid_series, path, "series needs name, type, labels and sample")}

  defp labels(labels, path) when is_list(labels) and length(labels) <= @max_labels do
    cond do
      not Enum.all?(labels, &label?/1) ->
        {:error, error(:invalid_label, path, "labels must be short string pairs")}

      Enum.map(labels, &elem(&1, 0)) != Enum.sort(Enum.map(labels, &elem(&1, 0))) ->
        {:error, error(:unsorted_labels, path, "labels must be sorted by name")}

      Enum.uniq_by(labels, &elem(&1, 0)) != labels ->
        {:error, error(:duplicate_label, path, "label names must be unique")}

      true ->
        :ok
    end
  end

  defp labels(_labels, path),
    do: {:error, error(:invalid_label, path, "labels must be a short list")}

  defp label?({name, value}) when is_binary(name) and is_binary(value),
    do: Regex.match?(@label_name, name) and byte_size(value) <= 128 and String.valid?(value)

  defp label?(_label), do: false

  defp sample(:histogram, %{buckets: buckets, sum: sum, count: count} = sample, path)
       when is_list(buckets) and buckets != [] and
              (map_size(sample) == 3 or
                 (map_size(sample) == 4 and :erlang.map_get(:stale, sample) == true)),
       do: histogram_sample(buckets, sum, count, path)

  defp sample(type, %{value: value} = sample, path)
       when type in [:counter, :gauge] and map_size(sample) == 1 do
    check(value?(value) and (type == :gauge or counter?(value)), :invalid_sample, path)
  end

  defp sample(_type, _sample, path),
    do: {:error, error(:invalid_sample, path, "sample does not match the series type")}

  defp histogram_sample(buckets, sum, count, path) do
    cond do
      not (value?(sum) and non_neg?(count)) ->
        {:error, error(:invalid_sample, path, "histogram sum and count are invalid")}

      not Enum.all?(buckets, &bucket?/1) ->
        {:error, error(:invalid_sample, path <> "/buckets", "buckets must be {le, count}")}

      elem(List.last(buckets), 0) != :infinity ->
        {:error, error(:invalid_sample, path <> "/buckets", "buckets must end in +Inf")}

      not sorted_buckets?(buckets) ->
        {:error, error(:invalid_sample, path <> "/buckets", "buckets must be sorted cumulative")}

      elem(List.last(buckets), 1) != count ->
        {:error, error(:invalid_sample, path <> "/count", "count must equal the +Inf bucket")}

      true ->
        :ok
    end
  end

  defp counter?(value) when is_number(value), do: value >= 0
  defp counter?(value), do: value in [:stale, :nan]

  defp bucket?({le, count}), do: (is_number(le) or le == :infinity) and non_neg?(count)
  defp bucket?(_bucket), do: false

  defp sorted_buckets?(buckets) do
    buckets
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [{le_a, count_a}, {le_b, count_b}] ->
      count_a <= count_b and (le_b == :infinity or (le_a != :infinity and le_a < le_b))
    end)
  end

  defp non_neg?(value), do: is_integer(value) and value >= 0

  defp check(true, _code, _path), do: :ok
  defp check(false, code, path), do: {:error, error(code, path, "snapshot field is invalid")}

  defp error(code, path, message, details \\ %{}),
    do: Error.new(code, :snapshot, message, path: path, details: details)
end
