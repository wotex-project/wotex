defmodule Wotex.Conformance.Bench.Observations do
  @moduledoc false

  # Normalized document observations over a synthetic Thing Description with
  # 64 Properties, the projection limit. Every eighth Property name contains a
  # `/`, so pointer encoding exercises the RFC 6901 escape.

  @properties 64

  @spec sizes() :: [{String.t(), pos_integer()}]
  def sizes, do: [{"1 pointer", 1}, {"8 pointers", 8}, {"64 pointers", @properties}]

  @spec sample(pos_integer()) :: %{
          input: map(),
          accepted: map(),
          rejected: map(),
          segments: [[String.t()]],
          pointers: [String.t()]
        }
  def sample(count) when count <= @properties do
    document = document()
    names = Enum.take(names(), count)
    segments = Enum.map(names, &["properties", &1])
    pointers = Enum.map(names, &("/properties/" <> String.replace(&1, "/", "~1")))

    projected =
      names
      |> Enum.zip(pointers)
      |> Map.new(fn {name, pointer} -> {pointer, document["properties"][name]} end)

    errors =
      pointers
      |> Enum.map(&%{"code" => "schema_violation", "phase" => "schema", "path" => &1})
      |> Enum.sort_by(&{&1["path"], &1["code"]})

    %{
      input: %{"document" => document, "projection" => pointers},
      accepted: %{"accepted" => true, "document" => projected},
      rejected: %{"accepted" => false, "errors" => errors},
      segments: segments,
      pointers: pointers
    }
  end

  defp document do
    %{
      "@context" => "https://www.w3.org/2022/wot/td/v1.1",
      "id" => "urn:example:thing:observation-bench",
      "title" => "Observation benchmark Thing",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "properties" => Map.new(names(), &{&1, property(&1)})
    }
  end

  defp names do
    Enum.map(1..@properties, fn
      index when rem(index, 8) == 0 -> "zone/#{index}"
      index -> "temperature-#{index}"
    end)
  end

  defp property(name) do
    %{
      "type" => "number",
      "unit" => "Cel",
      "readOnly" => true,
      "forms" => [
        %{
          "href" => "https://thing.example/properties/#{URI.encode_www_form(name)}",
          "contentType" => "application/json",
          "op" => ["readproperty"]
        }
      ]
    }
  end
end
