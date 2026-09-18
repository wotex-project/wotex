Code.require_file("support/spans.exs", __DIR__)

alias Wotex.Lab.Bench.Spans
alias Wotex.Lab.Metrics.{Collector, Exposition, RemoteWrite, Snapshot}

{:ok, lab} = Wotex.Lab.start_link(id: "bench-metrics", max_children: 8)
inputs = Map.new(Spans.sizes(), fn {label, count} -> {label, Spans.input(count, lab)} end)

[small, medium, large] =
  Spans.sizes()
  |> Enum.sort_by(&elem(&1, 1))
  |> Enum.map(fn {label, _} -> inputs[label].series end)

Benchee.run(
  %{
    "record spans into the collector" => fn %{spans: spans, count: count} ->
      ^count = Spans.emit(spans)
    end,
    "snapshot the collector" => fn %{collector: collector, series: count} ->
      {:ok, %Snapshot{series: series}} = Collector.snapshot(collector)
      ^count = length(series)
    end,
    "render exposition text" => fn %{snapshot: snapshot, text: text} ->
      ^text = Exposition.render(snapshot)
    end,
    "parse exposition text" => fn %{text: text, snapshot: snapshot} ->
      series = snapshot.series
      {:ok, %Snapshot{series: ^series}} = Exposition.parse(text, Spans.parse_options())
    end,
    "encode remote write" => fn %{snapshot: snapshot, body: body} ->
      {:ok, %{body: ^body}} = RemoteWrite.encode(snapshot)
    end
  },
  inputs: inputs,
  before_scenario: &Spans.start_collector(&1, lab),
  after_scenario: fn %{collector: collector} ->
    :ok = Wotex.Lab.stop_child(lab, :sessions, collector)
  end,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/metrics.md",
     title: "# Metrics collection, snapshots and export encodings",
     description: """
     The Lab's metrics path from telemetry to the wire over workloads of 8,
     64 and 512 request spans. The spans run over the runtime, HTTP and MQTT
     transports with 21 actions and eight results (504 distinct label sets),
     so the larger workloads fill more series: the snapshots hold #{small},
     #{medium} and #{large} series. Each scenario places a
     `Wotex.Lab.Metrics.Collector` with a series budget of 1,024 under a Lab
     instance and records its workload once before the measurement; nothing
     is dropped or rejected.

     `record spans into the collector` runs every span through
     `Wotex.Lab.Telemetry.span/4`: metadata allowlisting, the start and stop
     events and the collector's handler, which maps the outcome, action,
     profile and component to closed label values and updates the counter
     and histogram rows in its ETS table. `snapshot the collector` is
     `Wotex.Lab.Metrics.Collector.snapshot/1`, an admitted and sorted
     `Wotex.Lab.Metrics.Snapshot`. `render exposition text` and
     `parse exposition text` are `Wotex.Lab.Metrics.Exposition.render/1` and
     `Wotex.Lab.Metrics.Exposition.parse/2`, the self-scraper's Prometheus
     text format; the parse must return the rendered snapshot's series.
     `encode remote write` is
     `Wotex.Lab.Metrics.RemoteWrite.encode/2`: the hand-written
     `prometheus.WriteRequest` protobuf compressed by the Lab's own Snappy
     block encoder. Every job compares its result with the value computed
     before the run. Memory is that of the calling process: the collector
     builds its snapshot in its own process, so that job's memory column
     shows little more than the reply.
     """}
  ]
)

Supervisor.stop(lab)
