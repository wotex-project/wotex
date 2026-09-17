defmodule Wotex.Lab.OtlpExporterTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Otlp.{Exporter, GreptimeSink}
  alias Wotex.Lab.Telemetry
  alias Wotex.Lab.Test.OtlpDecoder

  @ok_response {:ok, %{status: 200, body: ""}}

  test "options are closed and bounded" do
    sink = fn _, _ -> @ok_response end

    for opts <- [
          [sink: sink],
          [id: "exporter"],
          [id: "exporter", sink: fn _ -> :ok end],
          [id: "Exporter", sink: sink],
          [id: "exporter", sink: sink, signals: []],
          [id: "exporter", sink: sink, signals: [:metrics]],
          [id: "exporter", sink: sink, signals: [:traces, :traces]],
          [id: "exporter", sink: sink, service_instance: "Lab A"],
          [id: "exporter", sink: sink, interval_ms: 99],
          [id: "exporter", sink: sink, max_buffer: 0],
          [id: "exporter", sink: sink, max_batch: 1_025],
          [id: "exporter", sink: sink, deadline_ms: 60_001],
          [id: "exporter", sink: sink, url: "http://127.0.0.1:4000"]
        ] do
      assert {:error, %Error{code: :invalid_otlp_exporter}} = Exporter.start_link(opts)
    end

    assert %{id: {Exporter, "exporter"}, restart: :transient} =
             Exporter.child_spec(id: "exporter", sink: sink)
  end

  test "closing spans export as traces and exceptions also as logs, without payload metadata" do
    exporter = start(sink: reply_sink(self(), @ok_response), service_instance: "lab-a")

    assert :ok =
             Telemetry.span(:nx, :encode, %{profile: :thermal, thing_ref: "thing:secret"}, fn ->
               :ok
             end)

    assert_raise RuntimeError, fn ->
      Telemetry.span(:policy, :dispatch, %{scenario_id: "private"}, fn -> raise "reason" end)
    end

    stats = Exporter.flush(exporter)
    assert stats.traces.exported == 2 and stats.logs.exported == 1
    assert stats.buffered == %{traces: 0, logs: 0} and stats.last_error == nil

    assert_received {:sink, :traces,
                     %{body: traces, headers: [{"content-type", "application/x-protobuf"}]}}

    assert_received {:sink, :logs, %{body: logs}}
    refute traces =~ "secret" or traces =~ "private" or logs =~ "reason"

    decoded = OtlpDecoder.traces(traces)
    assert decoded.resource == [{"service.name", "wotex_lab"}, {"service.instance.id", "lab-a"}]
    assert Enum.map(decoded.records, & &1.name) == ["nx.encode", "policy.dispatch"]
    assert Enum.map(decoded.records, & &1.status) == [[1], [2]]

    assert Enum.all?(
             decoded.records,
             &(byte_size(&1.trace_id) == 16 and byte_size(&1.span_id) == 8)
           )

    assert [%{body: "wotex.lab span exception", severity_text: "ERROR"}] =
             OtlpDecoder.logs(logs).records
  end

  test "partial success, rejected statuses, sink errors, crashes and deadlines are counted" do
    partial = IO.iodata_to_binary([<<0x08, 1>>, <<0x12, 4>>, "full"])

    cases = [
      {{:ok, %{status: 200, body: <<0x0A, byte_size(partial)>> <> partial}},
       %{exported: 1, rejected: 1, failed: 0}, :partial_success},
      {{:ok, %{status: 400, body: "{\"error\":\"secret\"}"}},
       %{exported: 0, rejected: 0, failed: 2}, :rejected_status},
      {{:ok, %{status: 200, body: <<0x0A, 9>>}}, %{exported: 0, rejected: 0, failed: 2},
       :malformed_otlp_response},
      {{:error, Error.new(:transport_failed, :export, "down")},
       %{exported: 0, rejected: 0, failed: 2}, :transport_failed},
      {:unexpected, %{exported: 0, rejected: 0, failed: 2}, :invalid_sink_result},
      {:crash, %{exported: 0, rejected: 0, failed: 2}, :export_crashed},
      {:hang, %{exported: 0, rejected: 0, failed: 2}, :export_deadline}
    ]

    for {response, expected, error} <- cases do
      sink = fn
        _, _ when response == :crash -> exit(:boom)
        _, _ when response == :hang -> Process.sleep(:infinity)
        _, _ -> response
      end

      exporter = start(sink: sink, signals: [:traces], deadline_ms: 100)
      for _ <- 1..2, do: Telemetry.span(:nx, :decode, %{}, fn -> :ok end)
      stats = Exporter.flush(exporter)
      assert Map.take(stats.traces, [:exported, :rejected, :failed]) == expected
      assert stats.last_error == error
      refute inspect(stats) =~ "secret"
      assert stats.logs == %{exported: 0, rejected: 0, failed: 0, dropped: 0}
      stop_supervised!({Exporter, "otlp-test"})
    end
  end

  test "buffers and batches are bounded and the handler detaches on stop" do
    exporter =
      start(sink: reply_sink(self(), @ok_response), max_buffer: 2, max_batch: 1, signals: [:traces])

    for _ <- 1..5, do: Telemetry.span(:nx, :encode, %{}, fn -> :ok end)
    stats = Exporter.flush(exporter)
    assert stats.traces.exported == 2
    assert stats.traces.dropped + stats.handler_dropped == 3

    for _ <- 1..2, do: assert_received({:sink, :traces, _})
    refute_received {:sink, _, _}

    handlers = :telemetry.list_handlers([:wotex, :lab, :nx, :encode, :stop])
    assert Enum.any?(handlers, &match?({Exporter, ^exporter, _}, &1.id))
    stop_supervised!({Exporter, "otlp-test"})
    handlers = :telemetry.list_handlers([:wotex, :lab, :nx, :encode, :stop])
    refute Enum.any?(handlers, &match?({Exporter, ^exporter, _}, &1.id))
  end

  test "the periodic tick exports without a flush call" do
    exporter = start(sink: reply_sink(self(), @ok_response), interval_ms: 100, signals: [:traces])
    Telemetry.span(:mqtt, :request, %{}, fn -> :timeout end)
    assert_receive {:sink, :traces, %{body: body}}, 2_000
    assert [%{status: [2]}] = OtlpDecoder.traces(body).records
    assert %{traces: %{exported: 1}} = eventually_stats(exporter)
  end

  test "the GreptimeDB sink admits its base URL and adds signal headers" do
    for config <- [
          %{url: "http://127.0.0.1:4000/v1/prometheus/write"},
          %{url: "http://127.0.0.1:4000/v1/otlp?db=public"},
          %{url: "http://user@127.0.0.1:4000/v1/otlp"},
          %{url: "http://127.0.0.1:4000/v1/otlp", database: "public"},
          %{url: "http://127.0.0.1:4000/v1/otlp", finch: :shared},
          %{url: "http://127.0.0.1:4000/v1/otlp", credential: {:bearer, "token"}},
          %{url: 7},
          nil
        ] do
      assert {:error, %Error{code: :invalid_otlp_sink}} = GreptimeSink.new(config)
    end

    {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(listener)

    {:ok, sink} =
      GreptimeSink.new(%{
        url: "http://127.0.0.1:#{port}/v1/otlp",
        database: "wotex_lab",
        receive_timeout: 2_000
      })

    request = %{body: "body", headers: [{"content-type", "application/x-protobuf"}]}

    for {signal, path, pipeline?} <- [
          {:traces, "/v1/otlp/v1/traces", true},
          {:logs, "/v1/otlp/v1/logs", false}
        ] do
      task = Task.async(fn -> sink.(signal, request) end)
      {:ok, socket} = :gen_tcp.accept(listener, 2_000)
      raw = read_request(socket, "")
      assert raw =~ "POST #{path} HTTP/1.1"
      assert raw =~ "x-greptime-db-name: wotex_lab"
      assert raw =~ "x-greptime-pipeline-name: greptime_trace_v1" == pipeline?

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: application/x-protobuf\r\ncontent-length: 0\r\n\r\n"
        )

      :gen_tcp.close(socket)
      assert {:ok, %{status: 200, body: ""}} = Task.await(task)
    end

    token = "otlp-bearer-sentinel-with-a-bounded-token-value"
    parent = self()

    credential = fn ->
      send(parent, :credential_resolved)
      {:ok, {:bearer, token}}
    end

    {:ok, authenticated} =
      GreptimeSink.new(%{
        url: "http://127.0.0.1:#{port}/v1/otlp",
        credential: credential,
        receive_timeout: 2_000
      })

    for signal <- [:traces, :logs] do
      task = Task.async(fn -> authenticated.(signal, request) end)
      {:ok, socket} = :gen_tcp.accept(listener, 2_000)
      assert read_request(socket, "") =~ "authorization: Bearer " <> token
      assert_received :credential_resolved

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: application/x-protobuf\r\ncontent-length: 0\r\n\r\n"
        )

      :gen_tcp.close(socket)
      assert {:ok, %{status: 200}} = Task.await(task)
    end

    for lookup <- [fn -> :error end, fn -> {:ok, nil} end] do
      {:ok, refused} =
        GreptimeSink.new(%{url: "http://127.0.0.1:#{port}/v1/otlp", credential: lookup})

      assert {:error, %Error{code: :credential_unavailable}} = refused.(:traces, request)
      assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
    end

    :gen_tcp.close(listener)
    assert {:error, %Error{}} = sink.(:traces, request)
  end

  defp start(opts) do
    start_supervised!({Exporter, Keyword.merge([id: "otlp-test", interval_ms: 60_000], opts)})
  end

  defp reply_sink(parent, response) do
    fn signal, request ->
      send(parent, {:sink, signal, request})
      response
    end
  end

  defp eventually_stats(exporter, attempts \\ 50) do
    stats = Exporter.stats(exporter)

    cond do
      stats.traces.exported > 0 -> stats
      attempts == 0 -> flunk("exporter never exported")
      true -> Process.sleep(20) && eventually_stats(exporter, attempts - 1)
    end
  end

  defp read_request(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 2_000)
    acc = acc <> data
    if String.contains?(acc, "\r\n\r\nbody"), do: acc, else: read_request(socket, acc)
  end
end
