defmodule Wotex.Nx.Window do
  @moduledoc "Caller-bounded deterministic temporal resampling window."

  alias Wotex.Nx.{Error, Observation, Row, Schema}

  @opaque t :: %__MODULE__{
            start: integer(),
            step: pos_integer(),
            count: pos_integer(),
            strategy: :exact | :latest | :nearest,
            max_age: non_neg_integer() | nil
          }

  @enforce_keys [:start, :step, :count, :strategy, :max_age]
  defstruct @enforce_keys

  @doc "Builds a window without reading a clock."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    start = Keyword.get(opts, :start)
    step = Keyword.get(opts, :step)
    count = Keyword.get(opts, :count)
    strategy = Keyword.get(opts, :strategy, :latest)
    max_age = Keyword.get(opts, :max_age)

    cond do
      not is_integer(start) ->
        {:error, Error.new(:invalid_window_start, :construction, "window start must be an integer")}

      not (is_integer(step) and step > 0) ->
        {:error, Error.new(:invalid_window_step, :construction, "window step must be positive")}

      not (is_integer(count) and count > 0) ->
        {:error, Error.new(:invalid_window_count, :construction, "window count must be positive")}

      strategy not in [:exact, :latest, :nearest] ->
        {:error,
         Error.new(:invalid_window_strategy, :construction, "window strategy is unsupported")}

      not (is_nil(max_age) or (is_integer(max_age) and max_age >= 0)) ->
        {:error, Error.new(:invalid_max_age, :construction, "max_age must be non-negative or nil")}

      true ->
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

  def new(_opts),
    do:
      {:error,
       Error.new(:invalid_window_options, :construction, "window options must be a keyword list")}

  @doc "Selects observations into rows using stable timestamp/id tie-breaking."
  @spec resample([Observation.t()], Schema.t(), t(), keyword()) ::
          {:ok, [Row.t()]} | {:error, Error.t()}
  def resample(observations, schema, window, opts \\ [])

  def resample(observations, %Schema{} = schema, %__MODULE__{} = window, opts)
      when is_list(observations) and is_list(opts) do
    max_observations = Keyword.get(opts, :max_observations, 10_000)
    max_work = Keyword.get(opts, :max_work, 5_000_000)
    feature_count = length(schema.features)
    work = length(observations) * window.count * feature_count

    cond do
      not (is_integer(max_observations) and max_observations > 0 and
             is_integer(max_work) and max_work > 0) ->
        {:error, Error.new(:invalid_window_limit, :limit, "window limits must be positive")}

      length(observations) > max_observations ->
        {:error,
         Error.new(:observation_limit_exceeded, :limit, "observation limit exceeded", %{
           count: length(observations),
           max_observations: max_observations
         })}

      window.count > schema.max_rows ->
        {:error,
         Error.new(:row_limit_exceeded, :limit, "window exceeds schema max_rows", %{
           count: window.count,
           max_rows: schema.max_rows
         })}

      work > max_work ->
        {:error,
         Error.new(:window_work_limit_exceeded, :limit, "window selection work limit exceeded", %{
           work: work,
           max_work: max_work
         })}

      not Enum.all?(observations, &match?(%Observation{}, &1)) ->
        {:error,
         Error.new(:invalid_observations, :window, "window input must contain Observation values")}

      true ->
        index = index(observations)
        build_rows(index, schema.features, window)
    end
  end

  def resample(_observations, _schema, _window, _opts),
    do: {:error, Error.new(:invalid_window_input, :window, "window input is invalid")}

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

  defp enforce_age(nil, _timestamp, _max_age), do: nil
  defp enforce_age(observation, _timestamp, nil), do: observation

  defp enforce_age(observation, timestamp, max_age) do
    if abs(timestamp - observation.observed_at) <= max_age, do: observation, else: nil
  end
end
