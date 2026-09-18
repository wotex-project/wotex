defmodule WotexLabWorkbench.GreptimeDurableReadTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Metrics.{DurableQuery, GreptimeBridge, Request}
  alias WotexLabWorkbench.Observability.{Durable, DurableReader, Inspection, Provisioning}
  alias WotexLabWorkbench.Observability.QueryListener
  alias WotexLabWorkbench.Test.GreptimeReceiver

  @moduletag :greptime
  @moduletag timeout: 300_000

  @host WotexLabWorkbench.Observability.Supervisor
  @token "local-only-query-token-sentinel-with-32-bytes-min"
  @digest :crypto.hash(:sha256, @token)
  @database "wotex_lab_reads"

  test "durable reads through the operator listener equal local history for exported captures" do
    receiver = GreptimeReceiver.start()

    assert {:ok, %{database: @database}} =
             Provisioning.provision(receiver.base_url, database: @database, ttl: "1d")

    {:ok, durable} = Durable.configure(receiver.write_url, false)
    {:ok, durable} = Durable.put_database(durable, @database)
    {:ok, reader} = DurableReader.configure(receiver.base_url, @database)

    start_supervised!(
      {@host,
       history: [interval_ms: 60_000],
       durable: Keyword.put(durable, :interval_ms, 60_000),
       durable_query: reader}
    )

    bridge = Durable.Bridge

    captured =
      for _ <- 1..3 do
        assert {:ok, _} = Thermal.run()
        assert {:ok, _} = GreptimeBridge.scrape_now(bridge)
        at = System.system_time(:millisecond)
        Process.sleep(1_200)
        at
      end

    assert %{exported: 3, failed: 0, rejected_permanent: 0} = await_exported(bridge, 3, 300)
    # The receiver needs an evaluation grid aligned to the step in Unix time.
    start_at = div(hd(captured), 5_000) * 5_000 - 10_000
    end_at = div(List.last(captured), 5_000) * 5_000 + 10_000

    for {metric, aggregation} <- [
          {"nx_operations_total", "sum"},
          {"nx_batch_rows", "sum"},
          {"scenario_operations_total", "sum"}
        ] do
      body = Jason.encode!(request(metric, aggregation, start_at, end_at))
      history = Jason.decode!(call("/query", body).resp_body)
      assert history["source"] == "ets_history" and history["points"] != []
      durable = await_points(body, length(history["points"]), 100)
      assert durable["source"] == "durable_promql" and durable["instance"] == "workbench"
      assert durable["points"] == history["points"], metric
    end

    unaligned = Jason.encode!(request("nx_operations_total", "sum", start_at + 1_000, end_at))
    refused = call("/durable/query", unaligned)
    assert refused.status == 422
    assert %{"code" => "unsupported_query"} = Jason.decode!(refused.resp_body)
    assert Inspection.count() == 0

    {:ok, query} =
      Request.decode(
        request("nx_operations_total", "sum", start_at, end_at),
        %{instance: "workbench", session: "lane"},
        %{}
      )

    {:ok, public} = DurableReader.configure(receiver.base_url, nil)

    assert {:ok, %{points: [], series_matched: 0}} =
             DurableQuery.query(query, DurableReader.executor(public))

    {:ok, absent} = DurableReader.configure(receiver.base_url, "wotex_lab_absent")

    assert {:error, %Error{code: :durable_unavailable}} =
             DurableQuery.query(query, DurableReader.executor(absent))

    other = %{query | scope: %{instance: "other-host", session: "lane"}}

    assert {:ok, %{points: [], series_matched: 0}} =
             DurableQuery.query(other, DurableReader.executor(reader))
  end

  defp request(metric, aggregation, start_at, end_at) do
    %{
      "schema_version" => "1.0.0",
      "metric" => metric,
      "aggregation" => aggregation,
      "start_at" => DateTime.to_iso8601(DateTime.from_unix!(start_at, :millisecond)),
      "end_at" => DateTime.to_iso8601(DateTime.from_unix!(end_at, :millisecond)),
      "step_ms" => 5_000
    }
  end

  # Remote-write ingestion is asynchronous at the receiver.
  defp await_points(body, count, attempts) do
    response = call("/durable/query", body)
    answer = Jason.decode!(response.resp_body)

    cond do
      response.status == 200 and length(answer["points"]) >= count -> answer
      attempts == 0 -> flunk("durable answer stayed #{response.status}: #{response.resp_body}")
      true -> Process.sleep(200) && await_points(body, count, attempts - 1)
    end
  end

  defp await_exported(bridge, count, attempts) do
    stats = GreptimeBridge.stats(bridge)

    cond do
      stats.exported >= count -> stats
      attempts == 0 -> flunk("bridge exported #{inspect(stats)}")
      true -> Process.sleep(100) && await_exported(bridge, count, attempts - 1)
    end
  end

  defp call(path, body) do
    conn = Plug.Test.conn("POST", path, body)

    conn = %{
      conn
      | remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"authorization", "Bearer " <> @token},
          {"content-type", "application/json"},
          {"content-length", "#{byte_size(body)}"}
        ]
    }

    QueryListener.call(conn, QueryListener.init(@digest))
  end
end
