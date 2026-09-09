defmodule Wotex.Conformance.JSONSchema do
  @moduledoc false

  # A small JSON Schema 2020-12 subset, sufficient for the portable schema
  # mirrors in `priv/schemas`. It supports the keywords those schemas use and
  # rejects any other keyword, so a mirror cannot silently grow a constraint
  # this checker ignores. It is test tooling, not a general validator, and adds
  # no production dependency.

  @annotations ~w($schema $id title description format)
  @supported ~w(
    $ref type const enum pattern minLength maxLength minimum maximum
    minItems maxItems uniqueItems required properties additionalProperties
    items oneOf anyOf allOf if then else
  )

  @type schema :: map() | boolean()

  @doc "Validates a decoded JSON value against a schema and a registry of `$id` schemas."
  @spec validate(schema(), term(), %{optional(String.t()) => schema()}) ::
          :ok | {:error, [String.t()]}
  def validate(schema, value, registry \\ %{}) do
    case errors(schema, value, "", registry) do
      [] -> :ok
      messages -> {:error, messages}
    end
  end

  @doc "Builds a registry of schemas keyed by their `$id`."
  @spec registry([map()]) :: %{optional(String.t()) => schema()}
  def registry(schemas), do: Map.new(schemas, &{&1["$id"], &1})

  defp errors(true, _, _, _), do: []
  defp errors(false, _, path, _), do: ["#{at(path)}: no value is valid"]

  defp errors(schema, value, path, registry) when is_map(schema) do
    conditional(schema, value, path, registry) ++
      additional(schema, value, path, registry) ++
      Enum.flat_map(schema, fn {keyword, constraint} ->
        keyword(keyword, constraint, value, path, registry)
      end)
  end

  defp conditional(%{"if" => condition, "then" => then_schema} = schema, value, path, registry) do
    if errors(condition, value, path, registry) == [] do
      errors(then_schema, value, path, registry)
    else
      errors(Map.get(schema, "else", true), value, path, registry)
    end
  end

  defp conditional(_, _, _, _), do: []

  # `additionalProperties` is evaluated with the sibling `properties` of the
  # same schema object, so it is applied here rather than keyword by keyword.
  defp additional(%{"additionalProperties" => schema} = parent, value, path, registry)
       when is_map(value) do
    declared = parent |> Map.get("properties", %{}) |> Map.keys()

    value
    |> Map.drop(declared)
    |> Enum.flat_map(fn {name, member} -> errors(schema, member, "#{path}/#{name}", registry) end)
  end

  defp additional(_, _, _, _), do: []

  defp keyword(annotation, _, _, _, _)
       when annotation in @annotations,
       do: []

  defp keyword(conditional, _, _, _, _)
       when conditional in ~w(if then else),
       do: []

  defp keyword(unsupported, _, _, path, _)
       when unsupported not in @supported do
    ["#{at(path)}: unsupported schema keyword #{unsupported}"]
  end

  defp keyword("$ref", reference, value, path, registry) do
    case Map.fetch(registry, reference) do
      {:ok, schema} -> errors(schema, value, path, registry)
      :error -> ["#{at(path)}: unresolved reference #{reference}"]
    end
  end

  defp keyword("type", types, value, path, _) do
    if Enum.any?(List.wrap(types), &type?(&1, value)) do
      []
    else
      ["#{at(path)}: expected type #{Enum.join(List.wrap(types), " or ")}"]
    end
  end

  defp keyword("const", expected, value, path, _) do
    if value === expected, do: [], else: ["#{at(path)}: expected constant value"]
  end

  defp keyword("enum", allowed, value, path, _) do
    if value in allowed, do: [], else: ["#{at(path)}: value is not an allowed member"]
  end

  defp keyword("pattern", pattern, value, path, _) when is_binary(value) do
    if Regex.match?(Regex.compile!(pattern), value) do
      []
    else
      ["#{at(path)}: value does not match #{pattern}"]
    end
  end

  defp keyword("minLength", min, value, path, _) when is_binary(value) do
    if String.length(value) >= min, do: [], else: ["#{at(path)}: value is shorter than #{min}"]
  end

  defp keyword("maxLength", max, value, path, _) when is_binary(value) do
    if String.length(value) <= max, do: [], else: ["#{at(path)}: value is longer than #{max}"]
  end

  defp keyword("minimum", min, value, path, _) when is_number(value) do
    if value >= min, do: [], else: ["#{at(path)}: value is below #{min}"]
  end

  defp keyword("maximum", max, value, path, _) when is_number(value) do
    if value <= max, do: [], else: ["#{at(path)}: value is above #{max}"]
  end

  defp keyword("minItems", min, value, path, _) when is_list(value) do
    if length(value) >= min, do: [], else: ["#{at(path)}: fewer than #{min} members"]
  end

  defp keyword("maxItems", max, value, path, _) when is_list(value) do
    if length(value) <= max, do: [], else: ["#{at(path)}: more than #{max} members"]
  end

  defp keyword("uniqueItems", true, value, path, _) when is_list(value) do
    if length(Enum.uniq(value)) == length(value), do: [], else: ["#{at(path)}: members repeat"]
  end

  defp keyword("required", names, value, path, _) when is_map(value) do
    names
    |> Enum.reject(&Map.has_key?(value, &1))
    |> Enum.map(&"#{at(path)}: required member #{&1} is missing")
  end

  defp keyword("properties", properties, value, path, registry) when is_map(value) do
    Enum.flat_map(properties, fn {name, schema} ->
      case Map.fetch(value, name) do
        {:ok, member} -> errors(schema, member, "#{path}/#{name}", registry)
        :error -> []
      end
    end)
  end

  defp keyword("additionalProperties", _, _, _, _), do: []

  defp keyword("items", schema, value, path, registry) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {member, index} ->
      errors(schema, member, "#{path}/#{index}", registry)
    end)
  end

  defp keyword("oneOf", schemas, value, path, registry) do
    matched = Enum.count(schemas, &(errors(&1, value, path, registry) == []))
    if matched == 1, do: [], else: ["#{at(path)}: #{matched} of #{length(schemas)} branches match"]
  end

  defp keyword("anyOf", schemas, value, path, registry) do
    if Enum.any?(schemas, &(errors(&1, value, path, registry) == [])) do
      []
    else
      ["#{at(path)}: no branch matches"]
    end
  end

  defp keyword("allOf", schemas, value, path, registry) do
    Enum.flat_map(schemas, &errors(&1, value, path, registry))
  end

  defp keyword(_, _, _, _, _), do: []

  defp type?("object", value), do: is_map(value)
  defp type?("array", value), do: is_list(value)
  defp type?("string", value), do: is_binary(value)
  defp type?("integer", value), do: is_integer(value)
  defp type?("number", value), do: is_number(value)
  defp type?("boolean", value), do: is_boolean(value)
  defp type?("null", value), do: is_nil(value)
  defp type?(_, _), do: false

  defp at(""), do: "(root)"
  defp at(path), do: path
end
