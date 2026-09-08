defmodule Wotex.Lab.MetricsExpositionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Collector, Exposition, Snapshot}

  @fixtures Application.app_dir(:wotex_lab, "priv/fixtures/metrics")

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp native(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  test "parses counters, gauges, histograms, escapes, timestamps and special floats" do
    assert {:ok, %Snapshot{source: :exposition} = snapshot} =
             Exposition.parse(fixture("basic.txt"),
               sequence: 7,
               instance_slot: 3,
               wall_time_ms: 5,
               monotonic_ms: 4
             )

    assert snapshot.sequence == 7 and snapshot.instance_slot == 3
    assert snapshot.wall_time_ms == 5 and snapshot.monotonic_ms == 4 and snapshot.identity == nil
    by_name = Enum.group_by(snapshot.series, & &1.name)

    assert [
             %{type: :counter, labels: [{"outcome", "error"}, {"path", "x"}], sample: %{value: 0}},
             escaped
           ] =
             by_name["demo_requests_total"]

    assert escaped.labels == [{"outcome", "ok"}, {"path", "a\"b\\c\n"}] and
             escaped.sample.value == 12

    values = Map.new(by_name["demo_temperature_celsius"], &{&1.labels, &1.sample.value})
    assert values[[]] == 21.5 and values[[{"room", "lab"}]] == -32.5
    assert values[[{"room", "nan"}]] == :nan and values[[{"room", "inf"}]] == :infinity
    assert values[[{"room", "neg"}]] == :neg_infinity

    assert [%{type: :histogram, sample: sample}] = by_name["demo_latency_seconds"]
    assert sample == %{buckets: [{0.005, 1}, {0.05, 3}, {:infinity, 4}], sum: 0.75, count: 4}
    assert [%{labels: [], sample: %{value: 7}}] = by_name["demo_empty_labels"]
    assert Exposition.content_type() == "text/plain; version=0.0.4; charset=utf-8"
  end

  test "rendering a parsed snapshot and parsing it again yields the same series" do
    {:ok, snapshot} = Exposition.parse(fixture("basic.txt"))
    text = Exposition.render(snapshot)
    assert text =~ ~s(demo_requests_total{outcome="ok",path="a\\"b\\\\c\\n"} 12)
    assert text =~ ~s(demo_temperature_celsius{room="nan"} NaN)
    assert text =~ ~s(demo_latency_seconds_bucket{le="+Inf",profile="test"} 4)
    {:ok, again} = Exposition.parse(text)
    assert again.series == snapshot.series

    stale = %{snapshot | series: [%{hd(snapshot.series) | sample: %{value: :stale}}]}
    assert Exposition.render(stale) =~ "NaN"
  end

  test "unknown types, malformed lines, duplicate series and label faults fail the snapshot" do
    expected = %{
      "unsupported-type.txt" => {:unsupported_type, "/line/1"},
      "untyped.txt" => {:untyped_series, "/line/1"},
      "unsorted-labels.txt" => {:unsorted_labels, "/line/2"},
      "duplicate-label.txt" => {:duplicate_label, "/line/2"},
      "duplicate-series.txt" => {:duplicate_series, "/line/3"},
      "malformed-line.txt" => {:malformed_line, "/line/2"},
      "unterminated-label.txt" => {:malformed_line, "/line/2"},
      "bad-type-line.txt" => {:malformed_line, "/line/1"},
      "histogram-bare.txt" => {:malformed_histogram, "/line/2"},
      "histogram-incomplete.txt" => {:malformed_histogram, "/series"},
      "histogram-missing-inf.txt" => {:invalid_sample, "/series/0/sample/buckets"},
      "histogram-noncumulative.txt" => {:invalid_sample, "/series/0/sample/buckets"}
    }

    for {name, {code, path}} <- expected do
      assert {:error, %Error{code: ^code, path: ^path}} =
               Exposition.parse(fixture("malformed/" <> name)),
             "expected #{code} for #{name}"
    end

    assert {:error, %Error{code: :oversized}} =
             Exposition.parse(String.duplicate("#", 20), max_bytes: 10)

    assert {:error, %Error{code: :invalid_exposition}} = Exposition.parse(:atom)

    assert {:error, %Error{code: :malformed_line}} =
             Exposition.parse("# TYPE a gauge\na{b=\"1\"} 1 later\n")

    assert {:error, %Error{code: :malformed_line}} = Exposition.parse("# TYPE a gauge\na{b=1} 1\n")

    assert {:error, %Error{code: :malformed_line}} =
             Exposition.parse("# TYPE a gauge\na{b=\"1\";} 1\n")

    assert {:error, %Error{code: :malformed_line}} =
             Exposition.parse("# TYPE a gauge\n{b=\"1\"} 1\n")

    assert {:error, %Error{code: :duplicate_series}} =
             Exposition.parse("# TYPE h histogram\nh_sum 1\nh_sum 2\n")

    assert {:error, %Error{code: :duplicate_series}} =
             Exposition.parse(
               ~s(# TYPE h histogram\nh_bucket{le="+Inf"} 1\nh_bucket{le="+Inf"} 1\n)
             )

    assert {:error, %Error{code: :malformed_histogram}} =
             Exposition.parse("# TYPE h histogram\nh_bucket 1\n")

    assert {:error, %Error{code: :malformed_histogram}} =
             Exposition.parse("# TYPE h histogram\nh_bucket{le=\"x\"} 1\n")

    assert {:error, %Error{code: :malformed_histogram}} =
             Exposition.parse("# TYPE h histogram\nh_bucket{le=\"1\"} 1.5\n")

    assert {:ok, %Snapshot{series: []}} = Exposition.parse("# HELP a b\n\n# just a comment\n")
  end

  test "a collector snapshot and the parsed exposition of the same series are equal fixtures" do
    collector = start_supervised!({Collector, id: :equality, backend_class: :binary})
    execute = &:telemetry.execute/3

    execute.([:wotex, :lab, :nx, :encode, :stop], %{duration: native(2)}, %{
      profile: :thermal,
      outcome: :ok
    })

    execute.([:wotex, :lab, :nx, :encode, :stop], %{duration: native(30)}, %{
      profile: :thermal,
      outcome: :ok
    })

    execute.([:wotex, :lab, :nx, :encode, :measurement], %{rows: 2, width: 1, fill: 0.5}, %{
      profile: :thermal
    })

    execute.([:wotex, :lab, :directory, :directory, :stop], %{duration: native(1)}, %{
      operation: :fetch,
      profile: :ets,
      outcome: :not_found
    })

    execute.([:wotex, :lab, :directory, :directory, :stop], %{duration: native(1)}, %{
      operation: :put,
      profile: :ets,
      outcome: :revision_mismatch
    })

    execute.([:wotex, :lab, :sse, :parse, :measurement], %{bytes: 512}, %{profile: :http})

    execute.([:wotex, :lab, :policy, :dispatch, :exception], %{duration: native(5)}, %{
      kind: :error,
      outcome: :exception
    })

    {:ok, collected} = Collector.snapshot(collector)
    text = fixture("equality/exposition.txt")
    {:ok, parsed} = Exposition.parse(text, sequence: collected.sequence)
    assert parsed.series == collected.series
    assert Exposition.render(collected) == text

    expected = fixture("equality/snapshot.json") |> JSON.decode!()
    assert expected["schema_version"] == Snapshot.schema_version()
    assert Enum.map(collected.series, &json_series/1) == expected["series"]

    manifest = fixture("equality/manifest.json") |> JSON.decode!()
    assert manifest["input_sha256"] == :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  defp json_series(series) do
    sample =
      case series.sample do
        %{buckets: buckets, sum: sum, count: count} ->
          %{
            "buckets" =>
              Enum.map(buckets, fn {le, n} -> [if(le == :infinity, do: "+Inf", else: le), n] end),
            "sum" => sum,
            "count" => count
          }

        %{value: value} ->
          %{"value" => value}
      end

    %{
      "name" => series.name,
      "type" => Atom.to_string(series.type),
      "labels" => Enum.map(series.labels, &Tuple.to_list/1),
      "sample" => sample
    }
  end
end
