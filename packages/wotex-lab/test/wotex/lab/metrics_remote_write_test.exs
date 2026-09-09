defmodule Wotex.Lab.MetricsRemoteWriteTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{RemoteWrite, Snappy, Snapshot}
  alias Wotex.Lab.Test.RemoteWriteDecoder

  @t 1_700_000_000_000

  defp snapshot(sequence, series, wall_time_ms \\ @t) do
    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: sequence,
        monotonic_ms: 0,
        wall_time_ms: wall_time_ms,
        series: series
      })

    snapshot
  end

  @counter %{
    name: "wotex_lab_nx_operations_total",
    type: :counter,
    labels: [{"profile", "test"}],
    sample: %{value: 3}
  }
  @gauge %{
    name: "wotex_lab_nx_queue_depth",
    type: :gauge,
    labels: [{"profile", "test"}],
    sample: %{value: 1.5}
  }
  @histogram %{
    name: "wotex_lab_nx_duration_seconds",
    type: :histogram,
    labels: [{"profile", "test"}],
    sample: %{buckets: [{0.005, 1}, {:infinity, 2}], sum: 0.25, count: 2}
  }

  test "encodes labels sorted with __name__, millisecond timestamps and expanded histograms" do
    {:ok, request} =
      RemoteWrite.encode(snapshot(1, [@counter, @gauge, @histogram]),
        labels: [{"instance", "lab-1"}]
      )

    assert request.headers == [
             {"content-encoding", "snappy"},
             {"content-type", "application/x-protobuf"},
             {"x-prometheus-remote-write-version", "0.1.0"}
           ]

    assert request.series == 6 and request.samples == 6
    assert request.bytes == byte_size(request.body) and request.raw_bytes > request.bytes
    timeseries = RemoteWriteDecoder.decode_body(request.body)
    names = Enum.map(timeseries, fn %{labels: labels} -> Enum.map(labels, &elem(&1, 0)) end)
    assert Enum.all?(names, &(&1 == Enum.sort(&1) and hd(&1) == "__name__"))

    by_name =
      Map.new(timeseries, fn series ->
        {List.keyfind(series.labels, "__name__", 0) |> elem(1), series}
      end)

    assert by_name["wotex_lab_nx_operations_total"].samples == [{@t, 3.0}]

    assert by_name["wotex_lab_nx_operations_total"].labels == [
             {"__name__", "wotex_lab_nx_operations_total"},
             {"instance", "lab-1"},
             {"profile", "test"}
           ]

    assert by_name["wotex_lab_nx_queue_depth"].samples == [{@t, 1.5}]
    assert by_name["wotex_lab_nx_duration_seconds_sum"].samples == [{@t, 0.25}]
    assert by_name["wotex_lab_nx_duration_seconds_count"].samples == [{@t, 2.0}]

    buckets =
      Enum.filter(
        timeseries,
        &(List.keyfind(&1.labels, "__name__", 0) ==
            {"__name__", "wotex_lab_nx_duration_seconds_bucket"})
      )

    assert Enum.map(buckets, &{List.keyfind(&1.labels, "le", 0), &1.samples}) == [
             {{"le", "+Inf"}, [{@t, 2.0}]},
             {{"le", "0.005"}, [{@t, 1.0}]}
           ]
  end

  test "batches order samples per series and refuse repeated timestamps or conflicting labels" do
    first = snapshot(1, [@counter], @t)
    second = snapshot(2, [%{@counter | sample: %{value: 5}}], @t + 5_000)

    {:ok, request} = RemoteWrite.encode([second, first])
    [series] = RemoteWriteDecoder.decode_body(request.body)
    assert series.samples == [{@t, 3.0}, {@t + 5_000, 5.0}]

    assert {:error, %Error{code: :unordered_samples}} =
             RemoteWrite.encode([first, snapshot(3, [@counter], @t)])

    assert {:error, %Error{code: :label_conflict}} =
             RemoteWrite.encode(first, labels: [{"profile", "host"}])

    assert {:error, %Error{code: :invalid_labels}} =
             RemoteWrite.encode(first, labels: [{"__name__", "x"}])

    assert {:error, %Error{code: :invalid_labels}} =
             RemoteWrite.encode(first, labels: [{"a", "1"}, {"a", "2"}])

    assert {:error, %Error{code: :invalid_labels}} =
             RemoteWrite.encode(first, labels: [{"1a", "x"}])

    assert {:error, %Error{code: :invalid_labels}} =
             RemoteWrite.encode(first, labels: for(i <- 1..9, do: {"l#{i}", "v"}))

    assert {:error, %Error{code: :invalid_batch}} = RemoteWrite.encode([])
    assert {:error, %Error{code: :invalid_batch}} = RemoteWrite.encode([%{not: :snapshot}])
    assert {:error, %Error{code: :invalid_batch}} = RemoteWrite.encode(:nope)
  end

  test "stale markers and special floats are protocol values with the documented bit patterns" do
    stale_histogram = %{
      @histogram
      | sample: %{buckets: [{0.005, 0}, {:infinity, 0}], sum: :stale, count: 0, stale: true}
    }

    series = [
      %{@gauge | sample: %{value: :stale}},
      %{@gauge | labels: [{"profile", "other"}], sample: %{value: :nan}},
      %{@gauge | labels: [{"profile", "http"}], sample: %{value: :infinity}},
      %{@gauge | labels: [{"profile", "mqtt"}], sample: %{value: :neg_infinity}},
      stale_histogram
    ]

    {:ok, request} = RemoteWrite.encode(snapshot(1, series))
    decoded = RemoteWriteDecoder.decode_body(request.body)
    values = Map.new(decoded, fn %{labels: labels, samples: [{_, value}]} -> {labels, value} end)

    stale = {:special, RemoteWrite.stale_marker()}
    assert stale == {:special, 0x7FF0000000000002}
    assert values[[{"__name__", "wotex_lab_nx_queue_depth"}, {"profile", "test"}]] == stale

    assert values[[{"__name__", "wotex_lab_nx_queue_depth"}, {"profile", "other"}]] ==
             {:special, 0x7FF8000000000001}

    assert values[[{"__name__", "wotex_lab_nx_queue_depth"}, {"profile", "http"}]] ==
             {:special, 0x7FF0000000000000}

    assert values[[{"__name__", "wotex_lab_nx_queue_depth"}, {"profile", "mqtt"}]] ==
             {:special, 0xFFF0000000000000}

    assert values[[{"__name__", "wotex_lab_nx_duration_seconds_sum"}, {"profile", "test"}]] == stale

    assert values[[{"__name__", "wotex_lab_nx_duration_seconds_count"}, {"profile", "test"}]] ==
             stale

    assert values[
             [
               {"__name__", "wotex_lab_nx_duration_seconds_bucket"},
               {"le", "+Inf"},
               {"profile", "test"}
             ]
           ] == stale
  end

  test "snappy blocks round-trip through the independent decoder and refuse malformed input" do
    inputs = [
      "",
      "a",
      "abcabcabcabcabcabcabcabcabcabc",
      String.duplicate(~s(wotex_lab_metric{profile="thermal"} 1\n), 700),
      :crypto.strong_rand_bytes(70_000),
      String.duplicate("x", 200_000),
      String.duplicate("0123456789", 100) <>
        String.duplicate("z", 70_000) <> String.duplicate("0123456789", 100)
    ]

    for input <- inputs do
      {:ok, block} = Snappy.compress(input)
      assert {:ok, ^input} = Snappy.decompress(block)
    end

    {:ok, block} = Snappy.compress(String.duplicate("x", 200_000))
    assert byte_size(block) < 20_000

    literal_only = <<3, 2::6, 0::2, "abc">>
    assert {:ok, "abc"} = Snappy.decompress(literal_only)
    copy_one = <<7, 2::6, 0::2, "abc", 0::3, 0::3, 1::2, 3>>
    assert {:ok, "abcabca"} = Snappy.decompress(copy_one)
    copy_four = <<6, 2::6, 0::2, "abc", 2::6, 3::2, 3::little-32>>
    assert {:ok, "abcabc"} = Snappy.decompress(copy_four)

    long_literal =
      <<byte_size(String.duplicate("y", 100)), 60::6, 0::2, 99::8,
        String.duplicate("y", 100)::binary>>

    assert {:ok, "yyyyyyyyyy" <> _} = Snappy.decompress(long_literal)

    assert {:error, %Error{code: :malformed_block}} =
             Snappy.decompress(<<255, 255, 255, 255, 255, 255>>)

    assert {:error, %Error{code: :malformed_block}} = Snappy.decompress(<<5, 1::6, 0::2, "ab">>)
    assert {:error, %Error{code: :malformed_block}} = Snappy.decompress(<<3, 0::6, 0::2, "abcd">>)
    assert {:error, %Error{code: :malformed_block}} = Snappy.decompress(<<4, 0::3, 0::3, 1::2, 9>>)

    assert {:error, %Error{code: :malformed_block}} =
             Snappy.decompress(<<3, 2::6, 0::2, "abc", 255>>)

    assert {:error, %Error{code: :oversized}} =
             Snappy.decompress(<<128, 128, 128, 128, 1>>, max_bytes: 10)

    assert {:error, %Error{code: :oversized}} = Snappy.compress("abcdef", max_bytes: 3)
    assert {:error, %Error{code: :invalid_input}} = Snappy.compress(:atom)
    assert {:error, %Error{code: :invalid_input}} = Snappy.decompress(nil)
  end
end
