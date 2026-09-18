defmodule Wotex.Directory.Bench.Things do
  @moduledoc false

  # Synthetic Thing Descriptions for the Directory benchmarks. Identifiers use
  # reserved example URNs and every Form a reserved example domain.

  alias Wotex.ThingDescription

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"1 Property" => 1, "24 Properties" => 24, "240 Properties" => 240}

  @spec identifier(pos_integer()) :: String.t()
  def identifier(index), do: "urn:example:thing:" <> String.pad_leading("#{index}", 4, "0")

  @spec thing_description(String.t(), pos_integer()) :: ThingDescription.t()
  def thing_description(identifier, property_count) do
    {:ok, td} = ThingDescription.from_map(document(identifier, property_count))
    td
  end

  @spec document(String.t(), pos_integer()) :: map()
  def document(identifier, property_count) do
    %{
      "@context" => Wotex.td_context_1_1(),
      "id" => identifier,
      "title" => "Directory benchmark Thing",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "properties" => Map.new(1..property_count, &property/1)
    }
  end

  @spec introduction() :: ThingDescription.t()
  def introduction do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "@type" => "ThingDirectory",
        "id" => "urn:example:directory",
        "title" => "Benchmark Thing Description Directory",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "things" => %{
            "type" => "array",
            "readOnly" => true,
            "forms" => [%{"href" => "https://directory.example/things"}]
          }
        }
      })

    td
  end

  # A patch that renames the Thing and describes every Property.
  @spec merge_patch(pos_integer()) :: map()
  def merge_patch(property_count) do
    %{
      "title" => "Renamed benchmark Thing",
      "properties" =>
        Map.new(1..property_count, fn index ->
          {"p#{index}", %{"description" => "Calibrated sensor #{index}", "minimum" => -40}}
        end)
    }
  end

  defp property(index) do
    {"p#{index}",
     %{
       "type" => "number",
       "unit" => "Cel",
       "readOnly" => true,
       "forms" => [
         %{"href" => "https://thing.example/properties/p#{index}", "op" => "readproperty"}
       ]
     }}
  end
end
