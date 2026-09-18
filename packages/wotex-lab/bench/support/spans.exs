defmodule Wotex.Lab.Bench.Spans do
  @moduledoc false

  # Request spans over the three transports, each with one of the 21 closed
  # actions and one of eight results, so the workload has 504 distinct label
  # sets. Span `i` carries label set `rem(i, 504)`: a larger workload fills
  # more of the collector's series. Every span feeds the catalogue's
  # `transport_requests_total` counter and its
  # `transport_request_duration_seconds` histogram.

  alias Wotex.Lab.{Error, Telemetry}
  alias Wotex.Lab.Metrics.{Collector, Exposition, RemoteWrite, Snapshot}

  @series_budget 1_024
  @transports [runtime: :loopback, http: :http, mqtt: :mqtt]
  @actions ~w(fetch list put delete create update readproperty writeproperty invokeaction
              observeproperty unobserveproperty subscribeevent unsubscribeevent get post
              patch head encode decode publish other)a
  @wall_time_ms 1_789_000_000_000

  @type span :: {Telemetry.component(), map(), term()}

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"8 spans" => 8, "64 spans" => 64, "512 spans" => 512}

  @spec collector_options() :: keyword()
  def collector_options, do: [series_budget: @series_budget]

  @spec parse_options() :: keyword()
  def parse_options, do: [sequence: 1, monotonic_ms: 0, wall_time_ms: @wall_time_ms]

  @spec input(pos_integer(), pid()) :: map()
  def input(count, lab) do
    spans = spans(count)
    {:ok, collector} = Wotex.Lab.start_child(lab, :sessions, {Collector, collector_options()})
    ^count = emit(spans)
    {:ok, snapshot} = Collector.snapshot(collector)
    :ok = Wotex.Lab.stop_child(lab, :sessions, collector)
    text = Exposition.render(snapshot)
    {:ok, %Snapshot{series: series}} = Exposition.parse(text, parse_options())
    ^series = snapshot.series
    {:ok, request} = RemoteWrite.encode(snapshot)

    %{
      spans: spans,
      count: count,
      series: length(snapshot.series),
      snapshot: snapshot,
      text: text,
      body: request.body
    }
  end

  @spec start_collector(map(), pid()) :: map()
  def start_collector(input, lab) do
    {:ok, collector} = Wotex.Lab.start_child(lab, :sessions, {Collector, collector_options()})
    count = input.count
    ^count = emit(input.spans)

    %{invalid_samples: 0, dropped_series: 0, dropped_samples: 0, negative_durations: 0} =
      Collector.stats(collector)

    Map.put(input, :collector, collector)
  end

  @spec emit([span()]) :: non_neg_integer()
  def emit(spans) do
    Enum.reduce(spans, 0, fn {component, metadata, result}, count ->
      ^result = Telemetry.span(component, :request, metadata, fn -> result end)
      count + 1
    end)
  end

  defp spans(count) do
    transports = length(@transports)
    results = results()

    Enum.map(0..(count - 1), fn index ->
      {component, profile} = Enum.at(@transports, rem(index, transports))
      result = Enum.at(results, rem(div(index, transports), length(results)))
      action = Enum.at(@actions, rem(div(index, transports * length(results)), length(@actions)))
      {component, %{operation: action, profile: profile}, result}
    end)
  end

  defp results do
    [
      {:ok, 21.5},
      {:error, Error.new(:timeout, :request, "request timed out")},
      {:error, Error.new(:not_found, :request, "resource not found")},
      {:error, Error.new(:unauthorized, :request, "request refused")},
      {:error, Error.new(:transport_failed, :request, "transport failed")},
      {:error, Error.new(:unsupported_operation, :request, "operation unsupported")},
      {:error, Error.new(:precondition_failed, :request, "precondition failed")},
      {:error, :closed}
    ]
  end
end
