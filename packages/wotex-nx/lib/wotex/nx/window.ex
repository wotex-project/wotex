defmodule Wotex.Nx.Window do
  @moduledoc """
  Selects observations into deterministic, caller-defined temporal rows.

  The consumer supplies the start coordinate, positive step, row count,
  selection strategy, and optional maximum age. The module never reads a clock.
  Stable timestamp and observation-ID tie-breaking makes replayed windows
  byte-for-byte interpretable by downstream numerical code.
  """

  alias Wotex.Nx.{Error, Observation, Options, Row, Schema}

  @new_options [:start, :step, :count, :strategy, :max_age]
  @resample_options [:max_observations, :max_work]

  @typedoc "A clock-free temporal grid and its deterministic selection policy."
  @opaque t :: %__MODULE__{
            start: integer(),
            step: pos_integer(),
            count: pos_integer(),
            strategy: :exact | :latest | :nearest,
            max_age: non_neg_integer() | nil
          }

  @enforce_keys [:start, :step, :count, :strategy, :max_age]
  defstruct @enforce_keys

  @doc """
  Builds a bounded temporal window without reading a clock.

  `:start`, `:step`, and `:count` are required integers. `:strategy` is
  `:latest`, `:nearest`, or `:exact`; `:max_age` is a non-negative coordinate
  distance or `nil`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @new_options, :invalid_window_options, :construction) do
      build(opts)
    end
  end

  def new(_),
    do:
      {:error,
       Error.new(:invalid_window_options, :construction, "window options must be a keyword list")}

  defp build(opts) do
    start = Keyword.get(opts, :start)
    step = Keyword.get(opts, :step)
    count = Keyword.get(opts, :count)
    strategy = Keyword.get(opts, :strategy, :latest)
    max_age = Keyword.get(opts, :max_age)

    with :ok <- validate_start(start),
         :ok <- validate_step(step),
         :ok <- validate_count(count),
         :ok <- validate_strategy(strategy),
         :ok <- validate_max_age(max_age) do
      {:ok,
       %__MODULE__{
         start: start,
         step: step,
         count: count,
         strategy: strategy,
         max_age: max_age
       }}
    end
  end

  defp validate_start(start) when is_integer(start), do: :ok

  defp validate_start(_) do
    {:error, Error.new(:invalid_window_start, :construction, "window start must be an integer")}
  end

  defp validate_step(step) when is_integer(step) and step > 0, do: :ok

  defp validate_step(_) do
    {:error, Error.new(:invalid_window_step, :construction, "window step must be positive")}
  end

  defp validate_count(count) when is_integer(count) and count > 0, do: :ok

  defp validate_count(_) do
    {:error, Error.new(:invalid_window_count, :construction, "window count must be positive")}
  end

  defp validate_strategy(strategy) when strategy in [:exact, :latest, :nearest], do: :ok

  defp validate_strategy(_) do
    {:error, Error.new(:invalid_window_strategy, :construction, "window strategy is unsupported")}
  end

  defp validate_max_age(nil), do: :ok
  defp validate_max_age(max_age) when is_integer(max_age) and max_age >= 0, do: :ok

  defp validate_max_age(_) do
    {:error, Error.new(:invalid_max_age, :construction, "max_age must be non-negative or nil")}
  end

  @doc """
  Selects observations into schema-ordered rows using stable tie-breaking.

  Optional `:max_observations` and `:max_work` bounds are validated before
  indexing. The window count must also fit the schema's row limit. Missing
  selections remain `nil` for the encoder's explicit missing-value policy.
  """
  @spec resample([Observation.t()], Schema.t(), t(), keyword()) ::
          {:ok, [Row.t()]} | {:error, Error.t()}
  def resample(observations, schema, window, opts \\ [])

  def resample(observations, %Schema{} = schema, %__MODULE__{} = window, opts)
      when is_list(observations) and is_list(opts) do
    with :ok <- Options.validate(opts, @resample_options, :invalid_window_input, :window),
         max_observations = Keyword.get(opts, :max_observations, 10_000),
         max_work = Keyword.get(opts, :max_work, 5_000_000),
         feature_count = length(schema.features),
         work = length(observations) * window.count * feature_count,
         :ok <- validate_limits(max_observations, max_work),
         :ok <- validate_observation_count(observations, max_observations),
         :ok <- validate_row_count(window, schema),
         :ok <- validate_work(work, max_work),
         :ok <- validate_observations(observations) do
      observations
      |> index()
      |> build_rows(schema.features, window)
    end
  end

  def resample(_, _, _, _),
    do: {:error, Error.new(:invalid_window_input, :window, "window input is invalid")}

  defp validate_limits(max_observations, max_work)
       when is_integer(max_observations) and max_observations > 0 and is_integer(max_work) and
              max_work > 0,
       do: :ok

  defp validate_limits(_, _) do
    {:error, Error.new(:invalid_window_limit, :limit, "window limits must be positive")}
  end

  defp validate_observation_count(observations, max_observations)
       when length(observations) <= max_observations,
       do: :ok

  defp validate_observation_count(observations, max_observations) do
    {:error,
     Error.new(:observation_limit_exceeded, :limit, "observation limit exceeded", %{
       count: length(observations),
       max_observations: max_observations
     })}
  end

  defp validate_row_count(window, schema) when window.count <= schema.max_rows, do: :ok

  defp validate_row_count(window, schema) do
    {:error,
     Error.new(:row_limit_exceeded, :limit, "window exceeds schema max_rows", %{
       count: window.count,
       max_rows: schema.max_rows
     })}
  end

  defp validate_work(work, max_work) when work <= max_work, do: :ok

  defp validate_work(work, max_work) do
    {:error,
     Error.new(:window_work_limit_exceeded, :limit, "window selection work limit exceeded", %{
       work: work,
       max_work: max_work
     })}
  end

  defp validate_observations(observations) do
    if Enum.all?(observations, &match?(%Observation{}, &1)) do
      :ok
    else
      {:error,
       Error.new(:invalid_observations, :window, "window input must contain Observation values")}
    end
  end

  defp index(observations) do
    observations
    |> Enum.group_by(&{&1.thing_id, &1.affordance_type, &1.affordance_name})
    |> Map.new(fn {key, values} ->
      sorted = Enum.sort_by(values, &{&1.observed_at, &1.id})
      {key, sorted}
    end)
  end

  defp build_rows(index, features, window) do
    rows =
      for offset <- 0..(window.count - 1) do
        timestamp = window.start + offset * window.step

        observations =
          Map.new(features, fn feature ->
            candidates =
              Map.get(
                index,
                {feature.thing_id, feature.affordance_type, feature.affordance_name},
                []
              )

            {feature.name, select(candidates, timestamp, window.strategy, window.max_age)}
          end)

        {:ok, row} = Row.new(timestamp, observations)
        row
      end

    {:ok, rows}
  end

  defp select(candidates, timestamp, :exact, max_age) do
    candidates
    |> Enum.filter(&(&1.observed_at == timestamp))
    |> Enum.min_by(& &1.id, fn -> nil end)
    |> enforce_age(timestamp, max_age)
  end

  defp select(candidates, timestamp, :latest, max_age) do
    candidates
    |> Enum.filter(&(&1.observed_at <= timestamp))
    |> Enum.sort_by(&{-&1.observed_at, &1.id})
    |> List.first()
    |> enforce_age(timestamp, max_age)
  end

  defp select(candidates, timestamp, :nearest, max_age) do
    candidates
    |> Enum.min_by(&{abs(&1.observed_at - timestamp), &1.observed_at, &1.id}, fn -> nil end)
    |> enforce_age(timestamp, max_age)
  end

  defp enforce_age(nil, _, _), do: nil
  defp enforce_age(observation, _, nil), do: observation

  defp enforce_age(observation, timestamp, max_age) do
    if abs(timestamp - observation.observed_at) <= max_age, do: observation, else: nil
  end
end
