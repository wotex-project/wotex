defmodule Wotex.Lab.MetricsDurableAdmissionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{DurableQuery, Gateway, Query, Request}

  @scope %{instance: "inspection", session: "server-session"}
  @start 1_767_225_600
  @request %{
    "schema_version" => "1.0.0",
    "metric" => "nx_queue_depth",
    "aggregation" => "sum",
    "filters" => %{},
    "start_at" => "2026-01-01T00:00:00Z",
    "end_at" => "2026-01-01T00:00:10Z",
    "step_ms" => 5_000
  }

  defp descriptor do
    {:ok, query} = Request.decode(@request, @scope, %{})
    query
  end

  defp series(values), do: %{"metric" => %{}, "values" => values}

  defp matrix(series),
    do: %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => series}}

  defp answer(values),
    do: DurableQuery.query(descriptor(), fn _ -> {:ok, matrix([series(values)])} end)

  test "only strictly increasing evaluation timestamps inside the requested grid are admitted" do
    for values <- [
          [[@start - 5, "1"]],
          [[@start + 15, "1"]],
          [[@start + 1, "1"]],
          [[@start + 0.0001, "1"]],
          [[@start + 4.9999, "1"]],
          [[@start, "1"], [@start, "2"]],
          [[@start, "NaN"], [@start, "2"]],
          [[@start + 5, "1"], [@start, "2"]],
          [[1.0e308, "1"]],
          [[-1.0e308, "1"]],
          [[Integer.pow(10, 400), "1"]],
          [["receiver-secret", "1"]]
        ] do
      assert {:error, %Error{code: :durable_invalid_response} = error} = answer(values)
      refute inspect(error) =~ "receiver-secret"
    end
  end

  test "endpoints and integer or float seconds preserve zero, gaps and quality markers" do
    assert {:ok, answer} = answer([[@start, "0"], [(@start + 10) / 1, "-2.5"]])

    assert answer.points == [
             %{t: @start * 1_000, value: 0},
             %{t: (@start + 10) * 1_000, value: -2.5}
           ]

    assert answer.freshness == %{latest_ms: (@start + 10) * 1_000, age_ms: 0}
    assert answer.markers == []

    for value <- ~w(NaN +Inf -Inf Inf) do
      assert {:ok, %{points: [], freshness: nil, markers: [%{t: time, kind: :nonfinite}]}} =
               answer([[@start, value]])

      assert time == @start * 1_000
    end

    for value <- ["receiver-secret", "1e999", "-1.0e999", <<255>>] do
      assert {:ok, %{points: [], markers: [%{kind: :invalid}]}} = answer([[@start, value]])
    end
  end

  test "fixed aggregate templates refuse multiple output series instead of flattening them" do
    for {metric, aggregation, opts} <- [
          {:nx_queue_depth, :sum, []},
          {:nx_queue_depth, :min, []},
          {:nx_queue_depth, :max, []},
          {:nx_operations_total, :increase, []},
          {:nx_operations_total, :rate, []},
          {:nx_duration_seconds, :increase, []},
          {:nx_duration_seconds, :histogram_quantile, [quantile: 0.95]}
        ] do
      {:ok, query} =
        Query.new(
          Keyword.merge(
            [
              scope: @scope,
              metric: metric,
              aggregation: aggregation,
              start_at: DateTime.from_unix!(@start),
              end_at: DateTime.from_unix!(@start + 10),
              step_ms: 5_000
            ],
            opts
          )
        )

      assert {:error, %Error{code: :durable_invalid_response}} =
               DurableQuery.query(query, fn _ ->
                 {:ok, matrix([series([[@start, "1"]]), series([[@start + 5, "2"]])])}
               end)
    end
  end

  test "point admission counts missing markers and refuses excess before timestamp conversion" do
    query = %{descriptor() | limits: %{descriptor().limits | points: 3}}
    values = [[@start, "0"], [@start + 5, "NaN"], [@start + 10, "1"]]

    assert {:ok, %{points: [_, _], markers: [_]}} =
             DurableQuery.query(query, fn _ -> {:ok, matrix([series(values)])} end)

    assert {:error, %Error{code: :query_too_large}} =
             DurableQuery.query(query, fn _ ->
               {:ok, matrix([series([[1.0e308, "receiver-secret"] | values])])}
             end)
  end

  test "executor raises, exits and throws become redacted unavailable results" do
    for executor <- [
          fn _ -> raise "receiver-secret" end,
          fn _ -> exit({:receiver_down, "receiver-secret"}) end,
          fn _ -> throw("receiver-secret") end
        ] do
      assert {:error, %Error{code: :durable_unavailable} = error} =
               DurableQuery.query(descriptor(), executor)

      refute inspect(error) =~ "receiver-secret"
    end
  end

  test "gateway delivers one typed failure and stays usable after malformed durable output" do
    owner = self()

    executor = fn _ ->
      send(owner, {:durable_worker, self()})
      receive do: ({:answer, body} -> {:ok, body})
    end

    gateway = start_supervised!({Gateway, durable: executor, scope: @scope, owner: self()})

    for {values, expected} <- [
          {[[1.0e308, "receiver-secret"]], {:error, :durable_invalid_response}},
          {[[@start, "1"], [@start, "NaN"]], {:error, :durable_invalid_response}},
          {[[@start + 5, "0"]], {:ok, 0}}
        ] do
      assert {:ok, reference} = Gateway.query(gateway, @request)
      assert_receive {:durable_worker, worker}
      send(worker, {:answer, matrix([series(values)])})
      assert_receive {:metric_query, ^gateway, ^reference, result}, 1_000

      case expected do
        {:error, code} -> assert {:error, %Error{code: ^code}} = result
        {:ok, value} -> assert {:ok, %{points: [%{value: ^value}]}} = result
      end

      refute inspect(result) =~ "receiver-secret"
      refute_receive {:metric_query, ^gateway, ^reference, _}, 10
    end

    assert %{completed: 1, failed: 2, active: 0} = Gateway.stats(gateway)
  end
end
