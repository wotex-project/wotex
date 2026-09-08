defmodule Wotex.Lab.MetricsBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Exposition, GreptimeBridge, History, ReqSink, Snapshot}
  alias Wotex.Lab.Test.{HttpServer, RemoteWriteServer}

  @secret "export-token-sentinel-4d2f"

  @exposition """
  # TYPE wotex_lab_nx_operations_total counter
  wotex_lab_nx_operations_total{profile="test"} 3
  # TYPE wotex_lab_nx_queue_depth gauge
  wotex_lab_nx_queue_depth{profile="test"} 2
  """

  defp server(script), do: RemoteWriteServer.start(script)

  defp req_sink(url),
    do: fn request, credential ->
      ReqSink.write(request, credential, %{url: url, receive_timeout: 500})
    end

  defp credential,
    do: %{reference: "export-ref", lookup: fn "export-ref" -> {:ok, {:bearer, @secret}} end}

  defp bridge(opts) do
    defaults = [
      id: System.unique_integer([:positive]),
      scrape: fn -> {:ok, @exposition} end,
      backoff_ms: 10,
      max_backoff_ms: 50,
      deadline_ms: 1_000
    ]

    start_supervised!({GreptimeBridge, Keyword.merge(defaults, opts)})
  end

  defp await(bridge, key, value, attempts \\ 300) do
    stats = GreptimeBridge.stats(bridge)

    cond do
      Map.get(stats, key) == value -> stats
      attempts == 0 -> flunk("expected #{key} == #{inspect(value)}, got #{inspect(stats)}")
      true -> Process.sleep(10) && await(bridge, key, value, attempts - 1)
    end
  end

  test "equal or rolled-back capture times are refused before history or sink admission" do
    {:ok, first} = Exposition.parse(@exposition, sequence: 1, wall_time_ms: 1_700_000_000_000)
    duplicate = %{first | sequence: 2}
    rollback = %{first | sequence: 3, wall_time_ms: first.wall_time_ms - 1}
    forged = %{first | sequence: 4, wall_time_ms: "not a timestamp"}
    next = %{first | sequence: 5, wall_time_ms: first.wall_time_ms + 1}
    snapshots = [first, duplicate, rollback, forged, next]
    calls = :counters.new(1, [])
    test = self()
    history = start_supervised!({History, id: :ordering})

    bridge =
      bridge(
        scrape: fn ->
          :counters.add(calls, 1, 1)
          {:ok, Enum.at(snapshots, :counters.get(calls, 1) - 1)}
        end,
        sink: fn request, _credential ->
          send(test, {:ordered_export, request})
          {:ok, %{status: 204}}
        end,
        history: history
      )

    assert {:ok, %{sequence: 1}} = GreptimeBridge.scrape_now(bridge)

    for _ <- 1..2 do
      assert {:error, %Error{code: :unordered_snapshot}} = GreptimeBridge.scrape_now(bridge)
    end

    assert {:error, %Error{code: :invalid_time}} = GreptimeBridge.scrape_now(bridge)
    assert {:ok, %{sequence: 5}} = GreptimeBridge.scrape_now(bridge)
    assert %{scraped: 5, admitted: 2, rejected: 3} = await(bridge, :exported, 2)
    assert [%{snapshot: ^first}, %{snapshot: ^next, gap: true}] = History.snapshots(history)
    assert_receive {:ordered_export, _first}
    assert_receive {:ordered_export, _next}
    refute_receive {:ordered_export, _rejected}
  end

  test "scrapes exposition, writes history and exports with redacted credentials" do
    %{url: url, controller: controller} = server([{:status, 204}, {:status, 204}])
    history = start_supervised!({History, id: :bridge})

    log =
      capture_log(fn ->
        bridge =
          bridge(
            sink: req_sink(url),
            credential: credential(),
            history: history,
            labels: [{"instance", "lab-1"}]
          )

        assert {:ok, %{sequence: 1, queue_depth: 1}} = GreptimeBridge.scrape_now(bridge)
        stats = await(bridge, :exported, 1)
        assert stats.scraped == 1 and stats.admitted == 1 and stats.queue_depth == 0
        assert stats.bytes > 0 and stats.last_error == nil and stats.in_flight == false
        refute inspect(stats) =~ @secret
        refute inspect(:sys.get_state(bridge)) =~ @secret

        [request] = RemoteWriteServer.await_requests(controller, 1)
        assert request.authorization == ["Bearer " <> @secret]
        assert {"content-encoding", "snappy"} in request.headers
        assert {"content-type", "application/x-protobuf"} in request.headers
        assert {"x-prometheus-remote-write-version", "0.1.0"} in request.headers
        names = Enum.map(request.timeseries, &List.keyfind(&1.labels, "__name__", 0))
        assert {"__name__", "wotex_lab_nx_operations_total"} in names
        assert Enum.all?(request.timeseries, &({"instance", "lab-1"} in &1.labels))

        assert [%{snapshot: %Snapshot{source: :exposition, sequence: 1}}] =
                 History.snapshots(history)

        vanished = fn ->
          {:ok,
           "# TYPE wotex_lab_nx_queue_depth gauge\nwotex_lab_nx_queue_depth{profile=\"test\"} 4\n"}
        end

        :sys.replace_state(bridge, &%{&1 | scrape: vanished})
        assert {:ok, %{sequence: 2}} = GreptimeBridge.scrape_now(bridge)
        await(bridge, :exported, 2)
        [_first, second] = RemoteWriteServer.await_requests(controller, 2)

        stale =
          Enum.find(
            second.timeseries,
            &({"__name__", "wotex_lab_nx_operations_total"} in &1.labels)
          )

        assert [{_t, {:special, 0x7FF0000000000002}}] = stale.samples
        assert [_, %{snapshot: %Snapshot{sequence: 2} = marked}] = History.snapshots(history)
        assert Enum.any?(marked.series, &(&1.sample == %{value: :stale}))
      end)

    refute log =~ @secret
  end

  test "a rejected or exhausted export cannot roll back capture admission" do
    for {status, counter} <- [{400, :rejected_permanent}, {503, :dropped_exhausted}] do
      {:ok, snapshot} = Exposition.parse(@exposition, sequence: 1, wall_time_ms: 1_700_000_000_000)
      %{url: url} = server([{:status, status}])
      bridge = bridge(scrape: fn -> {:ok, snapshot} end, sink: req_sink(url), max_attempts: 1)
      assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
      await(bridge, counter, 1)
      assert {:error, %Error{code: :unordered_snapshot}} = GreptimeBridge.scrape_now(bridge)
      assert %{admitted: 1, rejected: 1, exported: 0} = GreptimeBridge.stats(bridge)
    end
  end

  test "retries 5xx and bounded 429 with the same snapshot identity, never other 4xx" do
    script = [
      {:status, 500},
      {:status, 429, [{"retry-after", "0"}]},
      {:status, 204},
      {:status, 400},
      {:status, 204}
    ]

    %{url: url, controller: controller} = server(script)
    bridge = bridge(sink: req_sink(url))

    assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
    stats = await(bridge, :exported, 1)
    assert stats.retried == 2 and stats.rejected_permanent == 0
    assert stats.last_error == %{code: :rate_limited, class: :rate_limited, phase: :export}

    [first, second, third] = RemoteWriteServer.await_requests(controller, 3)
    assert first.timeseries == second.timeseries and second.timeseries == third.timeseries

    assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
    stats = await(bridge, :rejected_permanent, 1)
    assert stats.exported == 1 and stats.retried == 2 and stats.queue_depth == 0
    assert stats.last_error == %{code: :rejected, class: :permanent, phase: :export}
    assert length(RemoteWriteServer.requests(controller)) == 4

    assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
    assert await(bridge, :exported, 2).rejected_permanent == 1
    assert length(RemoteWriteServer.await_requests(controller, 5)) == 5
  end

  test "exhausted retries drop the snapshot and the deadline reports an ambiguous write" do
    %{url: url} = server(List.duplicate({:status, 503}, 10))
    bridge = bridge(sink: req_sink(url), max_attempts: 2)
    assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
    stats = await(bridge, :dropped_exhausted, 1)
    assert stats.retried == 1 and stats.exported == 0 and stats.queue_depth == 0
    assert stats.last_error.code == :server_error

    %{url: hanging} = server([:hang, {:status, 204}])
    slow = bridge(sink: req_sink(hanging), deadline_ms: 100, max_attempts: 3)
    assert {:ok, _} = GreptimeBridge.scrape_now(slow)
    stats = await(slow, :ambiguous, 1)
    assert stats.retried == 1
    assert stats.last_error.code in [:export_deadline, :timeout]
    await(slow, :exported, 1)
  end

  test "overload drops the oldest unsent snapshot, sink crashes are contained and stats stay honest" do
    test = self()

    blocking = fn _request, _credential ->
      send(test, {:sink_called, self()})

      receive do
        :release -> {:ok, %{status: 204, headers: []}}
      end
    end

    calls = :counters.new(1, [])

    scrape = fn ->
      :counters.add(calls, 1, 1)
      n = :counters.get(calls, 1)
      Exposition.parse(@exposition, sequence: n, wall_time_ms: 1_700_000_000_000 + n)
    end

    bridge = bridge(sink: blocking, queue_limit: 3, scrape: scrape)
    for _scrape <- 1..6, do: assert({:ok, _} = GreptimeBridge.scrape_now(bridge))
    assert_receive {:sink_called, exporter}

    stats = GreptimeBridge.stats(bridge)
    assert stats.in_flight and stats.queue_depth == 3 and stats.dropped_overload == 2
    :counters.put(calls, 1, 2)
    assert {:error, %Error{code: :unordered_snapshot}} = GreptimeBridge.scrape_now(bridge)
    assert %{admitted: 6, rejected: 1, dropped_overload: 2} = GreptimeBridge.stats(bridge)
    send(exporter, :release)
    await(bridge, :exported, 1)

    crashing = bridge(sink: fn _request, _credential -> raise "sink down" end, max_attempts: 1)

    capture_log(fn ->
      assert {:ok, _} = GreptimeBridge.scrape_now(crashing)
      stats = await(crashing, :dropped_exhausted, 1)
      assert stats.last_error.code == :export_crashed and Process.alive?(crashing)
    end)

    odd = bridge(sink: fn _request, _credential -> :whatever end)
    assert {:ok, _} = GreptimeBridge.scrape_now(odd)
    assert await(odd, :failed, 1).last_error.code == :invalid_sink_result

    unresolved =
      bridge(
        sink: fn _request, _credential -> flunk("must not be called") end,
        credential: %{reference: :r, lookup: fn _r -> :error end}
      )

    assert {:ok, _} = GreptimeBridge.scrape_now(unresolved)
    assert await(unresolved, :failed, 1).last_error.code == :unresolved_reference
  end

  test "scrape failures are rejected visibly and never take the bridge down" do
    %{url: url} = server([])
    calls = :counters.new(1, [])

    scrape = fn ->
      :counters.add(calls, 1, 1)

      case :counters.get(calls, 1) do
        1 -> raise "collector gone"
        2 -> {:ok, "# TYPE a summary\na 1\n"}
        3 -> {:error, Error.new(:unavailable, :test, "no scrape")}
        4 -> :nothing
        _later -> {:ok, @exposition}
      end
    end

    bridge =
      bridge(
        scrape: scrape,
        sink: req_sink(url),
        history: start_supervised!({History, id: :reject})
      )

    assert {:error, %Error{code: :scrape_failed}} = GreptimeBridge.scrape_now(bridge)
    assert {:error, %Error{code: :unsupported_type}} = GreptimeBridge.scrape_now(bridge)
    assert {:error, %Error{code: :unavailable}} = GreptimeBridge.scrape_now(bridge)
    assert {:error, %Error{code: :scrape_failed}} = GreptimeBridge.scrape_now(bridge)
    assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
    stats = await(bridge, :exported, 1)
    assert stats.rejected == 4 and stats.admitted == 1 and Process.alive?(bridge)
  end

  test "runs under a Lab instance on an interval and accepts admitted snapshots from a collector" do
    %{url: url, controller: controller} = server([])
    lab = start_supervised!({Lab, id: "bridge-lab", max_children: 4})
    {:ok, history} = Lab.start_child(lab, :sessions, {History, id: :h})

    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: 1,
        monotonic_ms: 0,
        wall_time_ms: 1_700_000_000_000,
        series: []
      })

    calls = :counters.new(1, [])

    {:ok, bridge} =
      Lab.start_child(
        lab,
        :sessions,
        {GreptimeBridge,
         id: :b,
         scrape: fn ->
           :counters.add(calls, 1, 1)
           n = :counters.get(calls, 1) - 1

           {:ok,
            %{snapshot | sequence: snapshot.sequence + n, wall_time_ms: snapshot.wall_time_ms + n}}
         end,
         sink: req_sink(url),
         history: history,
         interval_ms: 100}
      )

    assert RemoteWriteServer.await_requests(controller, 1) != []
    assert [%{snapshot: ^snapshot} | _later] = History.snapshots(history)
    assert GreptimeBridge.stats(bridge).admitted >= 1

    :ok = GenServer.stop(history)
    Process.sleep(150)
    assert GreptimeBridge.stats(bridge).history_failures >= 1 and Process.alive?(bridge)
  end

  test "configuration is explicit and bounded; the Req sink validates its own inputs" do
    scrape = fn -> {:ok, @exposition} end
    sink = fn _request, _credential -> {:ok, %{status: 204, headers: []}} end

    assert {:error, %Error{code: :invalid_options}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, url: "x")

    assert {:error, %Error{code: :invalid_bridge}} = GreptimeBridge.start_link(sink: sink)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: fn -> :ok end)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, queue_limit: 0)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, queue_limit: 257)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, deadline_ms: 60_001)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, interval_ms: 10)

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, credential: %{token: @secret})

    assert {:error, %Error{code: :invalid_bridge}} =
             GreptimeBridge.start_link(scrape: scrape, sink: sink, labels: %{})

    assert %{id: {GreptimeBridge, :x}, restart: :transient} = GreptimeBridge.child_spec(id: :x)

    {:ok, named} =
      GreptimeBridge.start_link(
        scrape: scrape,
        sink: sink,
        name: :"bridge-#{System.unique_integer([:positive])}"
      )

    :ok = GenServer.stop(named)

    request = %{body: "x", headers: []}
    assert {:error, %Error{code: :invalid_sink_config}} = ReqSink.write(request, nil, %{})

    assert {:error, %Error{code: :unsupported_credential}} =
             ReqSink.write(request, {:token, "x"}, %{url: "http://127.0.0.1:9/"})

    assert {:error, %Error{code: :invalid_sink_request}} =
             ReqSink.write(%{}, nil, %{url: "http://127.0.0.1:9/"})

    assert {:error, %Error{code: :invalid_sink_request}} =
             ReqSink.write(%{body: :not_binary, headers: []}, nil, %{
               url: "http://127.0.0.1:9/"
             })

    assert {:error, %Error{code: :invalid_sink_request}} =
             ReqSink.write(%{body: "x", headers: [{"x-test", "bad\r\nvalue"}]}, nil, %{
               url: "http://127.0.0.1:9/"
             })

    assert {:error, %Error{code: :unsupported_credential}} =
             ReqSink.write(request, {:bearer, "bad\r\ntoken"}, %{
               url: "http://127.0.0.1:9/"
             })

    assert {:error, %Error{code: :transport_failed, class: :unavailable}} =
             ReqSink.write(request, {:basic, "u", "p"}, %{url: "http://127.0.0.1:9/"})
  end

  test "sink verifies local TLS and refuses unpinned hosted destinations" do
    fixture = Path.expand("../../fixtures/tls", __DIR__)
    ca_certfile = Path.join(fixture, "ca-cert.pem")
    certfile = Path.join(fixture, "localhost-cert.pem")
    keyfile = Path.join(fixture, "localhost-key.pem")
    {:ok, server} = HttpServer.start(self(), scheme: :https, certfile: certfile, keyfile: keyfile)
    request = %{body: "bounded", headers: [{"content-type", "application/x-protobuf"}]}

    assert {:ok, %{status: 404}} =
             ReqSink.write(request, nil, %{
               url: "https://localhost:#{server.port}/v1/prometheus/write",
               tls_ca_certfile: ca_certfile
             })

    assert {:error, %Error{code: :transport_failed}} =
             ReqSink.write(request, nil, %{
               url: "https://127.0.0.1:#{server.port}/v1/prometheus/write",
               tls_ca_certfile: ca_certfile
             })

    private = fn _host, family ->
      if family == :inet, do: {:ok, [{127, 0, 0, 1}]}, else: {:ok, []}
    end

    assert {:error, %Error{code: :destination_not_admitted}} =
             ReqSink.write(request, nil, %{
               url: "https://metrics.example/v1/prometheus/write",
               profile: :hosted,
               audience: "https://metrics.example",
               resolver: private
             })

    for config <- [
          %{url: "https://metrics.example/v1/prometheus/write", profile: :hosted},
          %{
            url: "https://metrics.example/v1/prometheus/write",
            profile: :hosted,
            audience: "https://metrics.example",
            finch: :shared
          },
          %{url: "http://127.0.0.1:9/", receive_timeout: 0},
          %{url: "http://127.0.0.1:9/", unknown: true}
        ] do
      assert {:error, %Error{code: :invalid_sink_config}} = ReqSink.write(request, nil, config)
    end
  end
end
