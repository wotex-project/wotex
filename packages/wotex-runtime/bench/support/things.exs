defmodule Wotex.Runtime.Bench.Things do
  @moduledoc false

  # Synthetic Thing Descriptions and binding profiles for the Runtime
  # benchmarks. Identifiers use reserved example domains and URNs.

  alias Wotex.Runtime.BindingProfile
  alias Wotex.ThingDescription

  @spec property_sizes() :: %{String.t() => pos_integer()}
  def property_sizes,
    do: %{"1 Property" => 1, "24 Properties" => 24, "240 Properties" => 240}

  @spec form_sizes() :: %{String.t() => pos_integer()}
  def form_sizes, do: %{"1 Form" => 1, "16 Forms" => 16, "128 Forms" => 128}

  @spec thing_description(pos_integer(), keyword()) :: ThingDescription.t()
  def thing_description(property_count, opts \\ []) do
    form_count = Keyword.get(opts, :forms, 1)

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:runtime-bench",
        "title" => "Runtime benchmark Thing",
        "base" => "https://thing.example/things/1/",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "forms" => forms(form_count, "interactions", thing_operations()),
        "properties" => properties(property_count, form_count),
        "actions" => %{
          "calibrate" => %{
            "input" => %{"type" => "number"},
            "forms" => forms(form_count, "actions/calibrate", ["invokeaction", "queryaction"])
          }
        },
        "events" => %{
          "overheated" => %{
            "data" => %{"type" => "string"},
            "forms" => forms(form_count, "events/overheated", ["subscribeevent"])
          }
        }
      })

    td
  end

  @spec property_names(pos_integer()) :: [String.t()]
  def property_names(count), do: Enum.map(1..count, &"p#{&1}")

  @spec profiles() :: [BindingProfile.t()]
  def profiles do
    [
      profile(:mqtt, ["mqtt", "mqtts"]),
      profile(:https, ["http", "https"])
    ]
  end

  defp profile(id, schemes) do
    {:ok, profile} =
      BindingProfile.new(
        id: id,
        schemes: schemes,
        operations: Wotex.Runtime.operations(),
        media_types: ["application/json"]
      )

    profile
  end

  defp thing_operations, do: Enum.map(Wotex.Runtime.thing_operations(), &Atom.to_string/1)

  defp properties(count, form_count) do
    Map.new(property_names(count), fn name ->
      {name,
       %{
         "type" => "number",
         "unit" => "Cel",
         "observable" => true,
         "forms" =>
           forms(form_count, "properties/#{name}", [
             "readproperty",
             "writeproperty",
             "observeproperty"
           ])
       }}
    end)
  end

  # Every Form but the last uses a URI scheme no benchmark profile declares, so
  # selection scans all of them before it reaches the compatible relative Form.
  defp forms(count, href, operations) do
    Enum.map(1..count, fn
      ^count ->
        %{"href" => href, "contentType" => "application/json; charset=utf-8", "op" => operations}

      index ->
        %{
          "href" => "coap://thing.example/#{href}/#{index}",
          "contentType" => "application/json",
          "op" => operations
        }
    end)
  end
end
