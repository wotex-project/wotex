defmodule Wotex.Lab.Benchmark do
  @moduledoc """
  Bounded, data-only benchmark records for Lab evidence cohorts.

  `run/3` measures one zero-arity operation after a bounded warmup and returns
  a JSON-compatible record. Every record names the runner, backend, cohort,
  baseline and machine, carries the admitted input dimensions, process-memory
  observations and latency percentiles, and states explicitly that it is not
  correctness evidence.

  Shared runners and runs without a threshold are always informational. A
  percentile threshold is accepted only for a dedicated runner and is kept in
  the result with its pass/fail observation; crossing it does not change the
  result into a correctness failure. Callbacks are execution inputs and never
  appear in the public result.
  """

  alias Wotex.Lab.Error

  @schema_version "1.0.0"
  @dimension_keys ~w(bytes nodes depth forms rows width window queue sessions)a
  @option_keys ~w(dimensions runner backend cohort baseline machine samples warmup shared threshold)a
  @id ~r/\A[a-z0-9][a-z0-9._-]{0,127}\z/
  @secret ~r/(?i)(bearer\s|password\s*[=:]|passwd|secret\s*[=:]|token\s*[=:]|-----BEGIN)/
  @path ~r/\A(?:\/|~\/|\.\.?\/|[A-Za-z]:\\)/
  @max_samples 10_000
  @max_warmup 1_000
  @max_dimension 1_000_000_000_000

  @type dimension ::
          :bytes | :nodes | :depth | :forms | :rows | :width | :window | :queue | :sessions

  @doc "The closed benchmark input-dimension vocabulary."
  @spec dimensions() :: [dimension()]
  def dimensions, do: @dimension_keys

  @doc """
  Measures `operation` and returns a public benchmark result.

  Required options are `:dimensions`, `:runner`, `:backend`, `:cohort`,
  `:baseline` and `:machine`. `:samples` defaults to 20 and `:warmup` to 3.
  `:shared` defaults to `true`. A dedicated run may supply
  `threshold: %{p95_ns: positive_integer}`.
  """
  @spec run(String.t(), (-> term()), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def run(id, operation, opts) when is_function(operation, 0) and is_list(opts) do
    with :ok <- option_keys(opts),
         :ok <- identifier(id),
         {:ok, dimensions} <- dimensions(Keyword.get(opts, :dimensions)),
         {:ok, identity} <- identity(opts),
         {:ok, samples} <- count(Keyword.get(opts, :samples, 20), @max_samples, :samples),
         {:ok, warmup} <- count(Keyword.get(opts, :warmup, 3), @max_warmup, :warmup, 0),
         {:ok, shared} <- shared(Keyword.get(opts, :shared, true)),
         {:ok, threshold} <- threshold(Keyword.get(opts, :threshold), shared),
         :ok <- warm(operation, warmup),
         {:ok, observations} <- sample(operation, samples) do
      {:ok, result(id, dimensions, identity, samples, warmup, shared, threshold, observations)}
    end
  end

  def run(_id, _operation, _opts),
    do: {:error, Error.new(:invalid_benchmark, :admission, "benchmark inputs are invalid")}

  defp option_keys(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)
      unknown = keys -- @option_keys

      cond do
        length(keys) != length(Enum.uniq(keys)) ->
          invalid(:invalid_options, "benchmark options must not contain duplicate keys")

        unknown != [] ->
          invalid(:invalid_options, "benchmark options contain unknown keys", %{keys: unknown})

        true ->
          :ok
      end
    else
      invalid(:invalid_options, "benchmark options must be a keyword list")
    end
  end

  defp identifier(id) when is_binary(id) do
    if Regex.match?(@id, id),
      do: :ok,
      else: invalid(:invalid_identifier, "benchmark id is outside the admitted syntax")
  end

  defp identifier(_id), do: invalid(:invalid_identifier, "benchmark id must be a string")

  defp dimensions(value) when is_map(value) and map_size(value) > 0 do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, count}, {:ok, admitted} ->
      cond do
        key not in @dimension_keys ->
          {:halt, invalid(:invalid_dimension, "benchmark dimension is not admitted")}

        not is_integer(count) or count < 0 or count > @max_dimension ->
          {:halt,
           invalid(:invalid_dimension, "benchmark dimension count is outside its bound", %{
             dimension: key
           })}

        true ->
          {:cont, {:ok, Map.put(admitted, Atom.to_string(key), count)}}
      end
    end)
  end

  defp dimensions(_value),
    do: invalid(:invalid_dimensions, "benchmark dimensions must be a non-empty map")

  defp identity(opts) do
    [:runner, :backend, :cohort, :baseline, :machine]
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, identity} ->
      case identity_value(Keyword.get(opts, key), key) do
        {:ok, value} -> {:cont, {:ok, Map.put(identity, Atom.to_string(key), value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp identity_value(value, key) when is_binary(value) do
    if public_identity?(value), do: {:ok, value}, else: invalid_identity(key)
  end

  defp identity_value(_value, key), do: invalid_identity(key)

  defp invalid_identity(key) do
    invalid(:invalid_identity, "benchmark identity field is missing or unbounded", %{
      field: key
    })
  end

  defp public_identity?(value) do
    byte_size(value) in 1..128 and String.valid?(value) and not Regex.match?(@secret, value) and
      not Regex.match?(@path, value)
  end

  defp count(value, maximum, _field, minimum \\ 1)

  defp count(value, maximum, _field, minimum)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: {:ok, value}

  defp count(_value, _maximum, field, _minimum),
    do: invalid(:invalid_limit, "benchmark count is outside its bound", %{field: field})

  defp shared(value) when is_boolean(value), do: {:ok, value}
  defp shared(_value), do: invalid(:invalid_runner, "shared must be a boolean")

  defp threshold(nil, _shared), do: {:ok, nil}

  defp threshold(%{p95_ns: value}, false) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp threshold(%{p95_ns: _value}, true),
    do: invalid(:invalid_threshold, "shared-runner benchmarks cannot enforce thresholds")

  defp threshold(_value, _shared),
    do: invalid(:invalid_threshold, "threshold must contain one positive p95_ns bound")

  defp warm(_operation, 0), do: :ok

  defp warm(operation, count) do
    Enum.reduce_while(1..count, :ok, fn _index, :ok ->
      case invoke(operation) do
        {:ok, _observation} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp sample(operation, count) do
    Enum.reduce_while(1..count, {:ok, []}, fn _index, {:ok, observations} ->
      case invoke(operation) do
        {:ok, observation} -> {:cont, {:ok, [observation | observations]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      {:error, error} -> {:error, error}
    end)
  end

  defp invoke(operation) do
    before_memory = process_memory()
    started = System.monotonic_time()

    try do
      _result = operation.()
      duration = System.monotonic_time() - started
      after_memory = process_memory()

      {:ok,
       %{
         duration_ns: max(System.convert_time_unit(duration, :native, :nanosecond), 0),
         memory_bytes: max(before_memory, after_memory)
       }}
    rescue
      _exception -> benchmark_failed()
    catch
      _kind, _reason -> benchmark_failed()
    end
  end

  defp process_memory do
    {:memory, bytes} = Process.info(self(), :memory)
    bytes
  end

  defp result(id, dimensions, identity, samples, warmup, shared, threshold, observations) do
    durations = observations |> Enum.map(& &1.duration_ns) |> Enum.sort()
    memories = Enum.map(observations, & &1.memory_bytes)
    p95 = percentile(durations, 95)

    %{
      "schema_version" => @schema_version,
      "kind" => "wotex_lab_benchmark",
      "id" => id,
      "mode" => if(threshold, do: "threshold", else: "informational"),
      "correctness" => "not_evaluated",
      "shared_runner" => shared,
      "identity" => identity,
      "dimensions" => dimensions,
      "samples" => samples,
      "warmup" => warmup,
      "memory" => %{
        "unit" => "byte",
        "minimum" => Enum.min(memories),
        "maximum" => Enum.max(memories)
      },
      "latency" => %{
        "unit" => "nanosecond",
        "minimum" => hd(durations),
        "p50" => percentile(durations, 50),
        "p95" => p95,
        "p99" => percentile(durations, 99),
        "maximum" => List.last(durations),
        "mean" => div(Enum.sum(durations), samples)
      },
      "threshold" => threshold_result(threshold, p95)
    }
  end

  defp percentile(sorted, percentile) do
    index = max(div(percentile * length(sorted) + 99, 100) - 1, 0)
    Enum.at(sorted, index)
  end

  defp threshold_result(nil, _p95), do: nil

  defp threshold_result(maximum, p95) do
    %{
      "metric" => "p95_ns",
      "maximum" => maximum,
      "status" => if(p95 <= maximum, do: "pass", else: "fail")
    }
  end

  defp benchmark_failed,
    do: {:error, Error.new(:benchmark_failed, :execution, "benchmark operation failed")}

  defp invalid(code, message, details \\ %{}),
    do: {:error, Error.new(code, :admission, message, details: details)}
end
