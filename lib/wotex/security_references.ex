defmodule Wotex.SecurityReferences do
  @moduledoc false

  alias Wotex.{Error, JSON}

  @doc "Returns semantic errors for unresolved security-definition references."
  @spec errors(map()) :: [Error.t()]
  def errors(%{"securityDefinitions" => definitions} = document) when is_map(definitions) do
    document
    |> references(definitions)
    |> Enum.reduce([], fn
      {_path, reference}, errors when is_map_key(definitions, reference) ->
        errors

      {path, reference}, errors ->
        [
          Error.new(
            :undefined_security_reference,
            :semantic,
            "Security reference must name an entry in securityDefinitions",
            path,
            %{reference: reference}
          )
          | errors
        ]
    end)
    |> Enum.reverse()
  end

  def errors(_document), do: []

  defp references(document, definitions) do
    security_values(Map.get(document, "security"), "/security") ++
      form_references(Map.get(document, "forms"), "/forms") ++
      affordance_references(document) ++ combo_references(definitions)
  end

  defp affordance_references(document) do
    Enum.flat_map(~w(properties actions events), fn category ->
      document
      |> Map.get(category, %{})
      |> sorted_map_entries()
      |> Enum.flat_map(fn {name, affordance} ->
        path = "/#{category}/#{JSON.pointer_segment(name)}/forms"
        form_references(map_value(affordance, "forms", nil), path)
      end)
    end)
  end

  defp form_references(forms, path) when is_list(forms) do
    forms
    |> Enum.with_index()
    |> Enum.flat_map(fn {form, index} ->
      security_values(map_value(form, "security", nil), "#{path}/#{index}/security")
    end)
  end

  defp form_references(_forms, _path), do: []

  defp combo_references(definitions) do
    definitions
    |> sorted_map_entries()
    |> Enum.flat_map(fn
      {name, %{"scheme" => "combo"} = definition} ->
        Enum.flat_map(~w(oneOf allOf), fn member ->
          path = "/securityDefinitions/#{JSON.pointer_segment(name)}/#{member}"
          security_values(Map.get(definition, member), path)
        end)

      {_name, _definition} ->
        []
    end)
  end

  defp security_values(reference, path) when is_binary(reference), do: [{path, reference}]

  defp security_values(references, path) when is_list(references) do
    references
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {reference, index} when is_binary(reference) -> [{"#{path}/#{index}", reference}]
      {_reference, _index} -> []
    end)
  end

  defp security_values(_references, _path), do: []

  defp sorted_map_entries(value) when is_map(value), do: Enum.sort_by(value, &elem(&1, 0))
  defp sorted_map_entries(_value), do: []

  defp map_value(value, key, default) when is_map(value), do: Map.get(value, key, default)
  defp map_value(_value, _key, default), do: default
end
