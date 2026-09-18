defmodule Wotex.Nx.Bench.Series do
  @moduledoc false

  # Synthetic Property observation series for the Wotex Nx benchmarks. Every
  # feature reads one Property of one Thing identified by a reserved example
  # URN. Observations arrive once per 1,000 ms step with a deterministic jitter
  # below half a step, and carry temperatures in degrees Celsius.

  alias Wotex.DataSchema
  alias Wotex.Nx.{Feature, Observation, Row, Schema}

  @thing_id "urn:example:thing:bench"
  @step 1_000

  @spec sizes() :: %{String.t() => {pos_integer(), pos_integer()}}
  def sizes do
    %{
      "4 features x 32 rows" => {4, 32},
      "16 features x 128 rows" => {16, 128},
      "64 features x 512 rows" => {64, 512}
    }
  end

  @spec step() :: pos_integer()
  def step, do: @step

  @spec schema(pos_integer(), pos_integer()) :: Schema.t()
  def schema(feature_count, row_count) do
    {:ok, data_schema} = DataSchema.new(%{"type" => "number", "unit" => "Cel"})

    features =
      Enum.map(1..feature_count, fn index ->
        {:ok, feature} =
          Feature.new(
            name: "f#{index}",
            thing_id: @thing_id,
            affordance_type: :property,
            affordance_name: "p#{index}",
            data_schema: data_schema,
            accepted_quality: [:good],
            missing: {:fill, 0.0}
          )

        feature
      end)

    {:ok, schema} = Schema.new(features: features, max_rows: max(row_count, 1_024))
    schema
  end

  # Raw readings as a consumer receives them: identity, time and value.
  @spec readings(pos_integer(), pos_integer()) :: [keyword()]
  def readings(feature_count, row_count) do
    for step <- 0..(row_count - 1), index <- 1..feature_count do
      [
        id: "urn:example:observation:#{index}:#{step}",
        thing_id: @thing_id,
        affordance_type: :property,
        affordance_name: "p#{index}",
        observed_at: step * @step - rem(index * 37 + step * 11, div(@step, 2)),
        value: 20.0 + rem(index * 7 + step, 50) / 10,
        unit: "Cel"
      ]
    end
  end

  @spec observations([keyword()]) :: [Observation.t()]
  def observations(readings) do
    Enum.map(readings, fn reading ->
      {:ok, observation} = Observation.new(reading)
      observation
    end)
  end

  # Schema-ordered rows on the step grid. With `missing_every: n`, every n-th
  # cell is absent and the encoder applies the feature's fill policy.
  @spec rows([Observation.t()], pos_integer(), keyword()) :: [Row.t()]
  def rows(observations, feature_count, opts \\ []) do
    missing_every = Keyword.get(opts, :missing_every)

    observations
    |> Enum.chunk_every(feature_count)
    |> Enum.with_index()
    |> Enum.map(fn {cells, step} ->
      entries =
        cells
        |> Enum.with_index(1)
        |> Map.new(fn {observation, index} ->
          {"f#{index}", missing(observation, step * feature_count + index, missing_every)}
        end)

      {:ok, row} = Row.new(step * @step, entries)
      row
    end)
  end

  defp missing(_, cell, every) when is_integer(every) and rem(cell, every) == 0, do: nil
  defp missing(observation, _, _), do: observation
end
