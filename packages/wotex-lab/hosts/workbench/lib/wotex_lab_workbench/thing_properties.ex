defmodule WotexLabWorkbench.ThingProperties do
  @moduledoc "Admitted Property controls for the room's reference Things."

  alias Wotex.Form

  @primary %{"thermostat" => "temperature", "meter" => "power", "actuator" => "target"}

  @doc "Returns the Property represented on a reference Thing's canvas node."
  @spec primary(map()) :: String.t() | nil
  def primary(thing), do: @primary[thing.key]

  @doc "Returns bounded Property rows; inert entries never receive operation controls."
  @spec rows(map()) :: [map()]
  def rows(thing) do
    (get_in(thing, [:document, "properties"]) || %{})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(32)
    |> Enum.map(fn {name, property} ->
      operations = operations(property)

      %{
        name: name,
        unit: unit(property["unit"]),
        readable: thing.consumable and "readproperty" in operations,
        observable:
          thing.consumable and property["observable"] == true and
            "observeproperty" in operations and "unobserveproperty" in operations
      }
    end)
  end

  @doc "Returns only operations available for the node's represented Property."
  @spec operations_for_node(map()) :: [String.t()]
  def operations_for_node(thing) do
    case Enum.find(rows(thing), &(&1.name == primary(thing))) do
      nil ->
        []

      row ->
        Enum.flat_map([{"read", row.readable}, {"observe", row.observable}], fn
          {operation, true} -> [operation]
          _ -> []
        end)
    end
  end

  defp operations(property) do
    property
    |> Map.get("forms", [])
    |> Enum.flat_map(fn form ->
      case Form.new(form, for: :property) do
        {:ok, form} ->
          Form.operations(form,
            for: :property,
            read_only: property["readOnly"] == true,
            write_only: property["writeOnly"] == true
          )

        _ ->
          []
      end
    end)
  end

  defp unit("Cel"), do: "°C"
  defp unit(value) when is_binary(value), do: value
  defp unit(_), do: ""
end
