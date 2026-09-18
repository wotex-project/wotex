defmodule Wotex.Bench.Documents do
  @moduledoc false

  # Synthetic Thing Descriptions and Thing Models with a growing number of
  # Interaction Affordances. Identifiers use reserved example domains.

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"1 affordance" => 1, "24 affordances" => 24, "240 affordances" => 240}

  @spec thing_description(pos_integer()) :: map()
  def thing_description(count) do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:example:thing:bench",
      "title" => "Benchmark Thing",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => "nosec_sc",
      "properties" => affordances(count, "properties", &property/1),
      "actions" => affordances(div(count, 3), "actions", &action/1),
      "events" => affordances(div(count, 3), "events", &event/1)
    }
  end

  @spec thing_model(pos_integer()) :: map()
  def thing_model(count) do
    properties =
      Map.new(1..count, fn index ->
        {"p#{index}", %{"type" => "number", "unit" => "Cel", "readOnly" => true}}
      end)

    %{
      "@context" => Wotex.td_context_1_1(),
      "@type" => "tm:ThingModel",
      "id" => "urn:example:model:bench",
      "title" => "Benchmark model",
      "properties" => properties,
      "tm:optional" => Enum.map(1..count, &"/properties/p#{&1}")
    }
  end

  @spec json(map()) :: binary()
  def json(document) do
    {:ok, json} = Wotex.JSON.encode(document)
    json
  end

  defp affordances(0, _, _), do: %{}
  defp affordances(count, kind, build), do: Map.new(1..count, &{"#{kind}#{&1}", build.(&1)})

  defp property(index) do
    %{
      "type" => "number",
      "minimum" => 0,
      "maximum" => 100,
      "readOnly" => true,
      "forms" => [%{"href" => "https://thing.example/properties/p#{index}", "op" => "readproperty"}]
    }
  end

  defp action(index) do
    %{
      "input" => %{"type" => "object", "properties" => %{"level" => %{"type" => "integer"}}},
      "forms" => [%{"href" => "https://thing.example/actions/a#{index}"}]
    }
  end

  defp event(index) do
    %{
      "data" => %{"type" => "string"},
      "forms" => [%{"href" => "https://thing.example/events/e#{index}", "subprotocol" => "sse"}]
    }
  end
end
