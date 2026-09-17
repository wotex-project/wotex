defmodule Wotex.Lab.MetricsRetentionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Retention

  doctest Retention

  test "plans admit a non-reserved database and whole-hour or whole-day TTL bounds" do
    assert Retention.default_ttl() == "7d"
    assert {:ok, %Retention{ttl: "1h", seconds: 3_600}} = Retention.plan(database: "lab", ttl: "1h")

    assert {:ok, %Retention{ttl: "3650d", seconds: 315_360_000}} =
             Retention.plan(database: "wotex_lab_metrics", ttl: "3650d")

    assert {:ok, %Retention{seconds: 315_360_000}} =
             Retention.plan(database: "lab", ttl: "87600h")

    for opts <- [
          [database: "public"],
          [database: "information_schema"],
          [database: "greptime_private"],
          [database: "Lab"],
          [database: "1lab"],
          [database: "lab-metrics"],
          [database: String.duplicate("a", 64)],
          [database: :lab],
          [],
          [database: "lab", ttl: "0h"],
          [database: "lab", ttl: "30m"],
          [database: "lab", ttl: "7 d"],
          [database: "lab", ttl: "1w"],
          [database: "lab", ttl: "3651d"],
          [database: "lab", ttl: "7D"],
          [database: "lab", ttl: "forever"],
          [database: "lab", ttl: 7],
          [database: "lab", ttl: "7d'; DROP DATABASE public; --"],
          [database: "lab", database: "other"],
          [database: "lab", sql: "SELECT 1"]
        ] do
      assert {:error, %Error{code: :invalid_retention}} = Retention.plan(opts)
    end
  end

  test "statements and verification are fixed templates over the admitted plan" do
    {:ok, plan} = Retention.plan(database: "lab", ttl: "36h")

    assert Retention.statements(plan) == [
             "CREATE DATABASE IF NOT EXISTS lab WITH (ttl = '36h')",
             "ALTER DATABASE lab SET 'ttl' = '36h'"
           ]

    assert Retention.verification(plan) ==
             "SELECT options FROM information_schema.schemata WHERE schema_name = 'lab'"
  end

  test "normalized GreptimeDB TTL text converts to exact seconds" do
    for {text, seconds} <- [
          {"7days", 604_800},
          {"1day", 86_400},
          {"12h", 43_200},
          {"2h 30m", 9_000},
          {"59s", 59},
          {"2months 29days 2h 52m 48s", 90 * 86_400},
          {"9years 11months 27days 21h 50m 24s", 3_650 * 86_400},
          {"1week", 604_800}
        ] do
      assert Retention.seconds(text) == {:ok, seconds}
    end

    for text <- ["forever", "", "0s", "7 days", "10ms", "1y", nil, String.duplicate("1s ", 50)] do
      assert {:error, %Error{code: :retention_unverified}} = Retention.seconds(text)
    end
  end

  test "provisioning runs every statement, then verifies the effective seconds" do
    {:ok, plan} = Retention.plan(database: "lab", ttl: "90d")
    parent = self()

    executor = fn sql ->
      send(parent, {:sql, sql})

      if String.starts_with?(sql, "SELECT"),
        do: rows("'ttl'='2months 29days 2h 52m 48s'\n"),
        else: {:ok, %{"output" => [%{"affectedrows" => 0}]}}
    end

    assert {:ok, %{database: "lab", ttl: "90d", seconds: 7_776_000}} =
             Retention.provision(plan, executor)

    for statement <- Retention.statements(plan) ++ [Retention.verification(plan)] do
      assert_received {:sql, ^statement}
    end
  end

  test "refusals, unavailable answers, missing options and TTL drift fail closed" do
    {:ok, plan} = Retention.plan(database: "lab", ttl: "7d")
    ok = {:ok, %{"output" => [%{"affectedrows" => 1}]}}

    cases = [
      {fn _ -> {:ok, %{"code" => 1004, "error" => "secret-bearing detail"}} end, :retention_refused,
       %{step: 1, code: 1004}},
      {fn _ -> {:ok, %{"output" => []}} end, :retention_refused, %{step: 1, code: nil}},
      {fn _ -> {:error, :econnrefused} end, :retention_unavailable, %{step: 1}},
      {fn _ -> :unexpected end, :retention_unavailable, %{step: 1}},
      {answer(ok, rows("'ttl'='6days'\n")), :retention_not_applied,
       %{expected_seconds: 604_800, effective_seconds: 518_400}},
      {answer(ok, rows("'ttl'='forever'\n")), :retention_unverified, %{}},
      {answer(ok, rows("")), :retention_unverified, %{}},
      {answer(ok, {:ok, %{"output" => [%{"records" => %{"rows" => []}}]}}), :retention_unverified,
       %{}},
      {answer(ok, {:error, :timeout}), :retention_unavailable, %{step: 3}}
    ]

    for {executor, code, details} <- cases do
      assert {:error, %Error{code: ^code, phase: phase, details: ^details} = error} =
               Retention.provision(plan, executor)

      assert phase == :retention
      refute inspect(error) =~ "secret-bearing"
    end
  end

  defp answer(statement, verification) do
    fn sql -> if String.starts_with?(sql, "SELECT"), do: verification, else: statement end
  end

  defp rows(options), do: {:ok, %{"output" => [%{"records" => %{"rows" => [[options]]}}]}}
end
