defmodule Wotex.Nx.TestFactory do
  @moduledoc false

  alias Wotex.DataSchema
  alias Wotex.Nx.{Feature, Observation, Row, Schema}

  def data_schema(map \\ %{"type" => "number", "unit" => "Cel"}) do
    {:ok, schema} = DataSchema.new(map)
    schema
  end

  def feature(overrides \\ []) do
    defaults = [
      name: "temperature",
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: data_schema()
    ]

    {:ok, feature} = Feature.new(Keyword.merge(defaults, overrides))
    feature
  end

  def observation(overrides \\ []) do
    defaults = [
      id: "observation-1",
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      observed_at: 100,
      value: 21.5,
      unit: "Cel"
    ]

    {:ok, observation} = Observation.new(Keyword.merge(defaults, overrides))
    observation
  end

  def schema(features \\ [feature()], overrides \\ []) do
    {:ok, schema} = Schema.new(Keyword.merge([features: features], overrides))
    schema
  end

  def row(timestamp, observations) do
    {:ok, row} = Row.new(timestamp, observations)
    row
  end
end
