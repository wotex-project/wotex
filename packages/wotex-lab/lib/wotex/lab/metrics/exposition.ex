defmodule Wotex.Lab.Metrics.Exposition do
  @moduledoc """
  The pinned Prometheus text exposition contract (`text/plain; version=0.0.4`)
  as the input of the self-scraper, parsed into admitted snapshots.

  `parse/2` reads `# TYPE` declarations and samples, normalizes counters,
  gauges and classic histograms (`_bucket` with `le`, `_sum`, `_count`, `+Inf`)
  into the same `Wotex.Lab.Metrics.Snapshot` shape the collector produces, and
  fails the whole snapshot with a typed error naming the line for an unknown
  or unsupported type (summary, untyped, or a sample without a `TYPE`), a
  malformed line, a duplicate series, unsorted or duplicate labels, an
  incomplete or non-cumulative histogram, or text above `:max_bytes`
  (1 MiB). `+Inf`, `-Inf` and `NaN` become the protocol values `:infinity`,
  `:neg_infinity` and `:nan`; they never become observations. Sample
  timestamps are accepted and validated but the snapshot time comes from the
  caller (`:wall_time_ms`, `:monotonic_ms`, `:sequence`, `:instance_slot`).

  `render/1` writes a snapshot back in the same format with sorted labels,
  so a collector snapshot and its exposition parse to equal series.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Snapshot

  @content_type "text/plain; version=0.0.4; charset=utf-8"
  @max_bytes 1_048_576
  @types %{"counter" => :counter, "gauge" => :gauge, "histogram" => :histogram}
  @unsupported ~w(summary untyped)
  @name ~r/\A[a-zA-Z_:][a-zA-Z0-9_:]*/
  @label_name ~r/\A[a-zA-Z_][a-zA-Z0-9_]*/

  @doc "The pinned content type of the exposition format."
  @spec content_type() :: String.t()
  def content_type, do: @content_type

  @doc "Parses exposition text into an admitted snapshot."
  @spec parse(binary(), keyword()) :: {:ok, Snapshot.t()} | {:error, Error.t()}
  def parse(text, opts \\ [])

  def parse(text, opts) when is_binary(text) and is_list(opts) do
    max_bytes = Keyword.get(opts, :max_bytes, @max_bytes)

    with :ok <- size(text, max_bytes),
         {:ok, types, samples} <- lines(text),
         {:ok, series} <- assemble(types, samples) do
      Snapshot.new(%{
        source: :exposition,
        instance_slot: Keyword.get(opts, :instance_slot, 0),
        sequence: Keyword.get(opts, :sequence, 0),
        monotonic_ms: Keyword.get(opts, :monotonic_ms, System.monotonic_time(:millisecond)),
        wall_time_ms: Keyword.get(opts, :wall_time_ms, System.system_time(:millisecond)),
        series: series,
        counters: %{}
      })
    end
  end

  def parse(_, _), do: {:error, error(:invalid_exposition, "", "exposition must be text")}

  @doc "Renders a snapshot as exposition text."
  @spec render(Snapshot.t()) :: binary()
  def render(%Snapshot{series: series}) do
    series
    |> Enum.group_by(& &1.name)
    |> Enum.sort()
    |> Enum.map_join(fn {name, list} ->
      type = hd(list).type
      lines = Enum.flat_map(list, &sample_lines/1)
      "# TYPE #{name} #{type}\n" <> Enum.join(lines, "\n") <> "\n"
    end)
  end

  defp sample_lines(%{type: :histogram} = series) do
    %{buckets: buckets, sum: sum, count: count} = series.sample

    Enum.map(buckets, fn {le, value} ->
      labels = Enum.sort([{"le", format(le)} | series.labels])
      line(series.name <> "_bucket", labels, value)
    end) ++
      [
        line(series.name <> "_sum", series.labels, sum),
        line(series.name <> "_count", series.labels, count)
      ]
  end

  defp sample_lines(series), do: [line(series.name, series.labels, series.sample.value)]

  defp line(name, [], value), do: "#{name} #{format(value)}"

  defp line(name, labels, value) do
    pairs = Enum.map_join(labels, ",", fn {k, v} -> ~s(#{k}="#{escape(v)}") end)
    "#{name}{#{pairs}} #{format(value)}"
  end

  defp format(:infinity), do: "+Inf"
  defp format(:neg_infinity), do: "-Inf"
  defp format(special) when special in [:nan, :stale], do: "NaN"
  defp format(value) when is_integer(value), do: Integer.to_string(value)
  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp size(text, max_bytes) when byte_size(text) <= max_bytes, do: :ok

  defp size(_, max_bytes),
    do: {:error, error(:oversized, "", "exposition exceeds #{max_bytes} bytes")}

  defp lines(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}, []}, fn {line, number}, {:ok, types, samples} ->
      case parse_line(String.trim(line), number) do
        :skip -> {:cont, {:ok, types, samples}}
        {:type, name, type} -> {:cont, {:ok, Map.put(types, name, type), samples}}
        {:sample, sample} -> {:cont, {:ok, types, [sample | samples]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, types, samples} -> {:ok, types, Enum.reverse(samples)}
      error -> error
    end
  end

  defp parse_line("", _), do: :skip

  defp parse_line("# TYPE " <> rest, number) do
    case String.split(String.trim(rest), ~r/\s+/) do
      [name, type] when is_map_key(@types, type) -> {:type, name, Map.fetch!(@types, type)}
      [_, type] when type in @unsupported -> {:error, line_error(:unsupported_type, number)}
      _ -> {:error, line_error(:malformed_line, number)}
    end
  end

  defp parse_line("#" <> _, _), do: :skip

  defp parse_line(line, number) do
    with {:ok, name, rest} <- token(line, @name, number),
         {:ok, labels, rest} <- labels(rest, number),
         {:ok, value, rest} <- value(String.trim_leading(rest), number),
         :ok <- timestamp(String.trim(rest), number) do
      {:sample, %{name: name, labels: labels, value: value, line: number}}
    end
  end

  defp token(text, regex, number) do
    case Regex.run(regex, text) do
      [match] ->
        {:ok, match, binary_part(text, byte_size(match), byte_size(text) - byte_size(match))}

      nil ->
        {:error, line_error(:malformed_line, number)}
    end
  end

  defp labels("{" <> rest, number), do: label_pairs(String.trim_leading(rest), [], number)
  defp labels(rest, _), do: {:ok, [], rest}

  defp label_pairs("}" <> rest, acc, number) do
    labels = Enum.reverse(acc)
    names = Enum.map(labels, &elem(&1, 0))

    cond do
      names != Enum.sort(names) -> {:error, line_error(:unsorted_labels, number)}
      names != Enum.uniq(names) -> {:error, line_error(:duplicate_label, number)}
      true -> {:ok, labels, rest}
    end
  end

  defp label_pairs(text, acc, number) do
    with {:ok, name, rest} <- token(text, @label_name, number),
         "=" <> rest <- String.trim_leading(rest),
         "\"" <> rest <- String.trim_leading(rest),
         {:ok, value, rest} <- quoted(rest, [], number) do
      case String.trim_leading(rest) do
        "," <> rest -> label_pairs(String.trim_leading(rest), [{name, value} | acc], number)
        "}" <> _ = rest -> label_pairs(rest, [{name, value} | acc], number)
        _ -> {:error, line_error(:malformed_line, number)}
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, line_error(:malformed_line, number)}
    end
  end

  defp quoted("\"" <> rest, acc, _),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp quoted("\\\\" <> rest, acc, number), do: quoted(rest, ["\\" | acc], number)
  defp quoted("\\\"" <> rest, acc, number), do: quoted(rest, ["\"" | acc], number)
  defp quoted("\\n" <> rest, acc, number), do: quoted(rest, ["\n" | acc], number)

  defp quoted(<<char::utf8, rest::binary>>, acc, number),
    do: quoted(rest, [<<char::utf8>> | acc], number)

  defp quoted(_, _, number), do: {:error, line_error(:malformed_line, number)}

  defp value(text, number) do
    {token, rest} =
      case String.split(text, ~r/\s+/, parts: 2) do
        [token] -> {token, ""}
        [token, rest] -> {token, rest}
      end

    case number(token) do
      {:ok, value} -> {:ok, value, rest}
      :error -> {:error, line_error(:malformed_line, number)}
    end
  end

  defp number("+Inf"), do: {:ok, :infinity}
  defp number("Inf"), do: {:ok, :infinity}
  defp number("-Inf"), do: {:ok, :neg_infinity}
  defp number("NaN"), do: {:ok, :nan}

  defp number(token) do
    case Integer.parse(token) do
      {integer, ""} ->
        {:ok, integer}

      _ ->
        case Float.parse(token) do
          {float, ""} -> {:ok, Snapshot.number(float)}
          _ -> :error
        end
    end
  end

  defp timestamp("", _), do: :ok

  defp timestamp(token, number) do
    case Integer.parse(token) do
      {_, ""} -> :ok
      _ -> {:error, line_error(:malformed_line, number)}
    end
  end

  defp assemble(types, samples) do
    samples
    |> Enum.reduce_while({:ok, %{}, %{}}, fn sample, {:ok, scalars, histograms} ->
      case classify(types, sample) do
        {:scalar, type} -> put_scalar(scalars, histograms, sample, type)
        {:histogram, base, part} -> put_part(scalars, histograms, sample, base, part)
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, scalars, histograms} -> build(scalars, histograms)
      error -> error
    end
  end

  defp classify(types, %{name: name} = sample) do
    case Map.fetch(types, name) do
      {:ok, :histogram} -> {:error, line_error(:malformed_histogram, sample.line)}
      {:ok, type} -> {:scalar, type}
      :error -> histogram_part(types, sample)
    end
  end

  defp histogram_part(types, %{name: name, line: line}) do
    Enum.find_value(["_bucket", "_sum", "_count"], {:error, line_error(:untyped_series, line)}, fn
      suffix ->
        base = String.replace_suffix(name, suffix, "")

        if base != name and Map.get(types, base) == :histogram,
          do: {:histogram, base, suffix},
          else: nil
    end)
  end

  defp put_scalar(scalars, histograms, sample, type) do
    key = {sample.name, sample.labels}

    if Map.has_key?(scalars, key),
      do: {:halt, {:error, line_error(:duplicate_series, sample.line)}},
      else: {:cont, {:ok, Map.put(scalars, key, {type, sample.value}), histograms}}
  end

  defp put_part(scalars, histograms, sample, base, "_bucket") do
    with {{"le", le}, labels} <- List.keytake(sample.labels, "le", 0),
         {:ok, le} <- bucket_bound(le),
         true <- is_integer(sample.value) and sample.value >= 0 do
      put_bucket(scalars, histograms, {base, labels}, le, sample)
    else
      _ -> {:halt, {:error, line_error(:malformed_histogram, sample.line)}}
    end
  end

  defp put_part(scalars, histograms, sample, base, suffix) do
    field = if suffix == "_sum", do: :sum, else: :count
    key = {base, sample.labels}
    entry = Map.get(histograms, key, %{buckets: [], sum: nil, count: nil})

    if Map.get(entry, field) != nil,
      do: {:halt, {:error, line_error(:duplicate_series, sample.line)}},
      else: {:cont, {:ok, scalars, Map.put(histograms, key, Map.put(entry, field, sample.value))}}
  end

  defp bucket_bound(text) do
    case number(text) do
      {:ok, le} when is_number(le) or le == :infinity -> {:ok, le}
      _ -> :error
    end
  end

  defp put_bucket(scalars, histograms, key, le, sample) do
    entry = Map.get(histograms, key, %{buckets: [], sum: nil, count: nil})

    if List.keymember?(entry.buckets, le, 0) do
      {:halt, {:error, line_error(:duplicate_series, sample.line)}}
    else
      entry = %{entry | buckets: [{le, sample.value} | entry.buckets]}
      {:cont, {:ok, scalars, Map.put(histograms, key, entry)}}
    end
  end

  defp build(scalars, histograms) do
    scalar_series =
      Enum.map(scalars, fn {{name, labels}, {type, value}} ->
        %{name: name, type: type, labels: labels, sample: %{value: value}}
      end)

    histograms
    |> Enum.reduce_while({:ok, scalar_series}, fn {key, entry}, {:ok, acc} ->
      case histogram_series(key, entry) do
        {:ok, series} -> {:cont, {:ok, [series | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp histogram_series({name, labels}, entry) do
    buckets =
      Enum.sort_by(entry.buckets, fn {le, _} ->
        if le == :infinity, do: {1, 0}, else: {0, le}
      end)

    if entry.sum != nil and is_integer(entry.count) and buckets != [] do
      sample = %{buckets: buckets, sum: entry.sum, count: entry.count}
      {:ok, %{name: name, type: :histogram, labels: labels, sample: sample}}
    else
      {:error, error(:malformed_histogram, "/series", "histogram is incomplete", %{name: name})}
    end
  end

  defp line_error(code, number),
    do: error(code, "/line/#{number}", "exposition line #{number} is not admitted")

  defp error(code, path, message, details \\ %{}),
    do: Error.new(code, :exposition, message, path: path, details: details)
end
