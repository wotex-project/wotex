defmodule Wotex.Directory.Fixtures do
  @moduledoc false

  @spec thing_description(String.t() | nil, map()) :: Wotex.ThingDescription.t()
  def thing_description(identifier \\ "urn:example:thing:1", additions \\ %{}) do
    base = %{
      "@context" => Wotex.td_context_1_1(),
      "title" => "Example Thing",
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
      "security" => ["nosec_sc"],
      "properties" => %{
        "temperature" => %{
          "type" => "number",
          "readOnly" => true,
          "forms" => [
            %{
              "href" => "https://example.test/things/1/properties/temperature",
              "op" => "readproperty"
            }
          ]
        }
      }
    }

    document =
      base
      |> maybe_put_identifier(identifier)
      |> Map.merge(additions)

    {:ok, thing_description} = Wotex.ThingDescription.from_map(document)
    thing_description
  end

  defp maybe_put_identifier(document, nil), do: document
  defp maybe_put_identifier(document, identifier), do: Map.put(document, "id", identifier)
end
