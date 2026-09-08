defmodule Wotex.Lab.BenchmarkTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.{Benchmark, Error}

  test "bounded informational cohorts record every input dimension, memory and percentiles" do
    json = ~s({"items":[{"href":"https://example.test/a"},{"href":"https://example.test/b"}]})

    operations = [
      {"json-parse", %{bytes: byte_size(json), nodes: 5, depth: 0, forms: 2},
       fn ->
         Wotex.JSON.decode(json)
       end},
      {"nx-window", %{rows: 16, width: 3, window: 4},
       fn ->
         Nx.iota({16, 3}) |> Nx.reshape({4, 4, 3})
       end},
      {"queue-session", %{queue: 32, sessions: 4},
       fn ->
         Enum.reduce(1..32, :queue.new(), &:queue.in/2)
       end}
    ]

    results =
      Enum.map(operations, fn {id, dimensions, operation} ->
        assert {:ok, result} = Benchmark.run(id, operation, options(dimensions))
        assert result["kind"] == "wotex_lab_benchmark"
        assert result["mode"] == "informational"
        assert result["correctness"] == "not_evaluated"
        assert result["shared_runner"] == true
        assert result["samples"] == 8 and result["warmup"] == 2
        assert result["memory"]["minimum"] <= result["memory"]["maximum"]
        assert result["memory"]["unit"] == "byte"

        latency = result["latency"]
        assert latency["unit"] == "nanosecond"
        assert latency["minimum"] <= latency["p50"]
        assert latency["p50"] <= latency["p95"]
        assert latency["p95"] <= latency["p99"]
        assert latency["p99"] <= latency["maximum"]
        assert is_integer(latency["mean"]) and latency["mean"] >= 0
        assert {:ok, _json} = Wotex.JSON.encode(result)
        result
      end)

    dimensions = results |> Enum.flat_map(&Map.keys(&1["dimensions"])) |> Enum.sort()
    assert dimensions == Benchmark.dimensions() |> Enum.map(&Atom.to_string/1) |> Enum.sort()
  end

  test "only a dedicated, identified cohort may evaluate a p95 threshold" do
    assert {:error, %Error{code: :invalid_threshold, phase: :admission}} =
             Benchmark.run(
               "shared",
               fn -> :ok end,
               options(%{bytes: 1}, threshold: %{p95_ns: 1_000_000})
             )

    assert {:ok, result} =
             Benchmark.run(
               "dedicated",
               fn -> :ok end,
               options(%{bytes: 1}, shared: false, threshold: %{p95_ns: 9_223_372_036_854_775_807})
             )

    assert result["mode"] == "threshold"

    assert result["threshold"] == %{
             "metric" => "p95_ns",
             "maximum" => 9_223_372_036_854_775_807,
             "status" => "pass"
           }

    assert result["identity"] == %{
             "runner" => "ci-macos-arm64-dedicated",
             "backend" => "Nx.BinaryBackend",
             "cohort" => "elixir-1.20-otp-29",
             "baseline" => "wotex-lab-0.1.0",
             "machine" => "apple-silicon-arm64"
           }
  end

  test "malformed cohorts and failed callbacks return typed, payload-free errors" do
    assert {:error, %Error{code: :invalid_identity, details: %{field: :runner}}} =
             Benchmark.run("missing", fn -> :ok end, Keyword.delete(options(%{bytes: 1}), :runner))

    assert {:error, %Error{code: :invalid_identity}} =
             Benchmark.run(
               "secret",
               fn -> :ok end,
               options(%{bytes: 1}, machine: "/private/operator-machine")
             )

    assert {:error, %Error{code: :invalid_dimension}} =
             Benchmark.run("unknown", fn -> :ok end, options(%{payload: 1}))

    assert {:error, %Error{code: :invalid_limit}} =
             Benchmark.run("empty", fn -> :ok end, options(%{bytes: 0}, samples: 0))

    for operation <- [fn -> raise "credential=do-not-leak" end, fn -> throw(:private) end] do
      assert {:error, %Error{code: :benchmark_failed} = error} =
               Benchmark.run("failure", operation, options(%{bytes: 1}))

      refute inspect(error) =~ "do-not-leak"
      refute inspect(error) =~ "private"
    end

    assert {:error, %Error{code: :benchmark_failed}} =
             Benchmark.run(
               "sample-failure",
               fn -> raise "sample" end,
               options(%{bytes: 1}, warmup: 0)
             )
  end

  test "the closed schema rejects malformed identifiers, options, limits and thresholds" do
    assert {:error, %Error{code: :invalid_benchmark}} = Benchmark.run(:bad, :bad, %{})

    assert {:error, %Error{code: :invalid_options}} =
             Benchmark.run("bad-options", fn -> :ok end, [:not_a_keyword])

    assert {:error, %Error{code: :invalid_options}} =
             Benchmark.run(
               "duplicates",
               fn -> :ok end,
               options(%{bytes: 1}) ++ [samples: 2]
             )

    assert {:error, %Error{code: :invalid_options}} =
             Benchmark.run("unknown-option", fn -> :ok end, options(%{bytes: 1}, other: 1))

    for id <- ["UPPER", "contains space", 1] do
      assert {:error, %Error{code: :invalid_identifier}} =
               Benchmark.run(id, fn -> :ok end, options(%{bytes: 1}))
    end

    assert {:error, %Error{code: :invalid_dimensions}} =
             Benchmark.run("empty-dimensions", fn -> :ok end, options(%{}))

    for dimensions <- [%{bytes: -1}, %{bytes: 1_000_000_000_001}] do
      assert {:error, %Error{code: :invalid_dimension}} =
               Benchmark.run("invalid-dimension", fn -> :ok end, options(dimensions))
    end

    assert {:error, %Error{code: :invalid_runner}} =
             Benchmark.run("invalid-shared", fn -> :ok end, options(%{bytes: 1}, shared: :yes))

    for threshold <- [%{}, %{p95_ns: 0}, %{p50_ns: 1}] do
      assert {:error, %Error{code: :invalid_threshold}} =
               Benchmark.run(
                 "invalid-threshold",
                 fn -> :ok end,
                 options(%{bytes: 1}, shared: false, threshold: threshold)
               )
    end
  end

  test "a dedicated threshold may record an informational regression" do
    assert {:ok, result} =
             Benchmark.run(
               "slow-dedicated",
               fn -> Process.sleep(1) end,
               options(%{bytes: 1},
                 shared: false,
                 threshold: %{p95_ns: 1},
                 samples: 1,
                 warmup: 0
               )
             )

    assert result["threshold"]["status"] == "fail"
    assert result["correctness"] == "not_evaluated"
  end

  defp options(dimensions, overrides \\ []) do
    Keyword.merge(
      [
        dimensions: dimensions,
        runner: "ci-macos-arm64-dedicated",
        backend: "Nx.BinaryBackend",
        cohort: "elixir-1.20-otp-29",
        baseline: "wotex-lab-0.1.0",
        machine: "apple-silicon-arm64",
        samples: 8,
        warmup: 2,
        shared: true
      ],
      overrides
    )
  end
end
