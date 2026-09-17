defmodule Wotex.Lab.MCPMetricsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.MCP.Server
  alias Wotex.Lab.Metrics.{History, Snapshot}

  @scope %{instance: "mcp-metrics", session: "mcp-session"}
  @arguments %{
    "metric" => "nx_queue_depth",
    "aggregation" => "last",
    "filters" => %{"profile" => "test"},
    "start_at" => "2026-01-01T00:00:00Z",
    "end_at" => "2026-01-01T00:00:10Z",
    "step_ms" => 5_000
  }

  setup do
    history = start_supervised!({History, instance: @scope.instance})
    for {offset, value} <- [{0, 3}, {5_000, 5}, {10_000, 7}], do: store(history, offset, value)
    %{history: history}
  end

  test "the tool is listed only for a host-bound history and answers inert catalogue data",
       %{history: history} do
    unbound = session([])
    refute "query_metrics" in tool_names(unbound)

    assert {%{"error" => %{"code" => -32_601}}, _} = call(unbound, @arguments)

    bound = session(metrics: %{history: history, scope: @scope})
    assert "query_metrics" in tool_names(bound)

    assert {%{"result" => %{"isError" => false, "structuredContent" => answer}}, _} =
             call(bound, @arguments)

    assert answer["source"] == "ets_history"
    assert answer["instance"] == "mcp-metrics"
    assert answer["metric"] == "nx_queue_depth"
    assert answer["aggregation"] == "last"
    assert answer["interval"]["step_ms"] == 5_000
    assert length(answer["points"]) == 3
    assert "sha256:" <> _ = answer["digest"]
    assert {:ok, _} = Wotex.JSON.encode(answer)
    assert gateways(history) == []
  end

  test "scope, limits and unknown fields cannot come from tool arguments", %{history: history} do
    bound = session(metrics: %{history: history, scope: @scope})

    for extra <- [
          %{"scope" => %{"instance" => "other", "session" => "other"}},
          %{"limits" => %{"points" => 1_000_000}},
          %{"schema_version" => "2.0.0"},
          %{"sql" => "SELECT * FROM secrets"}
        ] do
      assert {%{"error" => %{"code" => -32_602}}, _} = call(bound, Map.merge(@arguments, extra))
    end

    for {key, value} <- [
          {"metric", "secret-sentinel"},
          {"aggregation", "DROP TABLE"},
          {"end_at", "2026-01-02T12:00:00Z"},
          {"step_ms", 1}
        ] do
      assert {%{"result" => %{"isError" => true, "structuredContent" => failure}}, _} =
               call(bound, Map.put(@arguments, key, value))

      assert failure["available"] == false
      assert is_binary(failure["error"])
      refute inspect(failure) =~ "secret-sentinel"
    end

    other = session(metrics: %{history: history, scope: %{@scope | instance: "other"}})

    assert {%{"result" => %{"isError" => true, "structuredContent" => %{"error" => denied}}}, _} =
             call(other, @arguments)

    assert denied in ["scope_denied", "invalid_gateway"]
    assert gateways(history) == []
  end

  test "a dead history and malformed bindings fail closed", %{history: history} do
    for metrics <- [%{history: self()}, %{history: :history, scope: @scope}, :metrics] do
      assert {:error, %Error{code: :invalid_options}} = Server.new(metrics: metrics)
    end

    bound = session(metrics: %{history: history, scope: @scope})
    :ok = GenServer.stop(history)

    assert {%{"result" => %{"isError" => true, "structuredContent" => %{"error" => code}}}, _} =
             call(bound, @arguments)

    assert code in ["invalid_gateway", "history_unavailable", "scope_unavailable"]
  end

  defp store(history, offset, value) do
    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: div(offset, 5_000) + 1,
        monotonic_ms: offset,
        wall_time_ms: 1_767_225_600_000 + offset,
        identity: %{started_at: 1, generation: 0},
        series: [
          %{
            name: "wotex_lab_nx_queue_depth",
            type: :gauge,
            labels: [{"profile", "test"}],
            sample: %{value: value}
          }
        ]
      })

    assert {:ok, _} = History.put(history, snapshot)
  end

  defp session(opts) do
    {:ok, state} = Server.new(opts)

    {_, state} =
      Server.handle(state, request(1, "initialize", %{"protocolVersion" => "2025-11-25"}))

    {nil, state} =
      Server.handle(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    state
  end

  defp tool_names(state) do
    {reply, _} = Server.handle(state, request(2, "tools/list", %{}))
    Enum.map(reply["result"]["tools"], & &1["name"])
  end

  defp call(state, arguments) do
    Server.handle(
      state,
      request(3, "tools/call", %{"name" => "query_metrics", "arguments" => arguments})
    )
  end

  defp request(id, method, params),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  defp gateways(history) do
    {:monitored_by, monitors} = Process.info(history, :monitored_by)
    Enum.filter(monitors, &(is_pid(&1) and Process.alive?(&1) and &1 != self()))
  end
end
