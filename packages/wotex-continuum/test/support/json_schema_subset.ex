defmodule WotexContinuum.JSONSchemaSubset do
  @moduledoc false

  alias WotexContinuum.Error

  @supported ~w($ref oneOf allOf if type const enum required properties
                additionalProperties items minItems uniqueItems minLength
                maxLength pattern minimum)

  @unsupported ~w(format propertyNames)

  @spec supported_keywords() :: [String.t()]
  def supported_keywords, do: @supported

  @spec unsupported_keywords() :: [String.t()]
  def unsupported_keywords, do: @unsupported

  @spec validate(term(), String.t(), %{optional(String.t()) => map()}) ::
          :ok | {:error, [String.t()]}
  def validate(value, document, registry) do
    schema = Map.fetch!(registry, document)
    state = %{schema: schema, document: document, registry: registry, path: Error.root()}

    case check(value, schema, state) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check(_, true, _), do: []
  defp check(_, false, state), do: ["#{state.path}: no value is accepted"]

  defp check(value, schema, state) when is_map(schema) do
    state = %{state | schema: schema}

    Enum.flat_map(schema, fn {keyword, argument} ->
      check_keyword(keyword, argument, value, state)
    end)
  end

  defp check_keyword("$ref", reference, value, state) do
    {target, next_state} = resolve(reference, state)

    check(value, target, next_state)
  end

  defp check_keyword("oneOf", branches, value, state) do
    case Enum.count(branches, &(check(value, &1, state) == [])) do
      1 -> []
      matched -> ["#{state.path}: expected exactly one matching branch, matched #{matched}"]
    end
  end

  defp check_keyword("allOf", branches, value, state) do
    Enum.flat_map(branches, &check(value, &1, state))
  end

  defp check_keyword("if", condition, value, state) do
    with {:ok, consequence} <- Map.fetch(state.schema, "then"),
         [] <- check(value, condition, state) do
      check(value, consequence, state)
    else
      _ -> []
    end
  end

  defp check_keyword("type", type, value, state) do
    if type?(type, value), do: [], else: ["#{state.path}: expected type #{type}"]
  end

  defp check_keyword("const", expected, value, state) do
    if value == expected,
      do: [],
      else: ["#{state.path}: expected the constant #{inspect(expected)}"]
  end

  defp check_keyword("enum", allowed, value, state) do
    if value in allowed, do: [], else: ["#{state.path}: value is not in the allowed set"]
  end

  defp check_keyword("required", keys, value, state) when is_map(value) do
    for key <- keys,
        not Map.has_key?(value, key),
        do: "#{Error.child(state.path, key)}: is required"
  end

  defp check_keyword("properties", properties, value, state) when is_map(value) do
    Enum.flat_map(properties, fn {name, member_schema} ->
      case Map.fetch(value, name) do
        {:ok, member} -> check(member, member_schema, descend(state, name))
        :error -> []
      end
    end)
  end

  defp check_keyword("additionalProperties", false, value, state) when is_map(value) do
    known =
      state.schema
      |> Map.get("properties", %{})
      |> Map.keys()

    for key <- Map.keys(value),
        key not in known,
        do: "#{Error.child(state.path, key)}: member is not defined"
  end

  defp check_keyword("items", item_schema, value, state) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> check(item, item_schema, descend(state, index)) end)
  end

  defp check_keyword("minItems", minimum, value, state) when is_list(value) do
    if length(value) >= minimum, do: [], else: ["#{state.path}: fewer than #{minimum} items"]
  end

  defp check_keyword("uniqueItems", true, value, state) when is_list(value) do
    if Enum.uniq(value) == value, do: [], else: ["#{state.path}: items are not unique"]
  end

  defp check_keyword("minLength", minimum, value, state) when is_binary(value) do
    if String.length(value) >= minimum, do: [], else: ["#{state.path}: shorter than #{minimum}"]
  end

  defp check_keyword("maxLength", maximum, value, state) when is_binary(value) do
    if String.length(value) <= maximum, do: [], else: ["#{state.path}: longer than #{maximum}"]
  end

  defp check_keyword("pattern", pattern, value, state) when is_binary(value) do
    if Regex.match?(Regex.compile!(pattern), value),
      do: [],
      else: ["#{state.path}: does not match #{pattern}"]
  end

  defp check_keyword("minimum", minimum, value, state) when is_number(value) do
    if value >= minimum, do: [], else: ["#{state.path}: below #{minimum}"]
  end

  defp check_keyword(_, _, _, _), do: []

  defp descend(state, segment), do: %{state | path: Error.child(state.path, segment)}

  defp resolve(reference, state) do
    case String.split(reference, "#", parts: 2) do
      ["", "/$defs/" <> name] ->
        {definition(state.registry, state.document, name), state}

      [file, "/$defs/" <> name] ->
        {definition(state.registry, file, name), %{state | document: file}}
    end
  end

  defp definition(registry, document, name) do
    registry
    |> Map.fetch!(document)
    |> Map.fetch!("$defs")
    |> Map.fetch!(name)
  end

  defp type?("object", value), do: is_map(value)
  defp type?("array", value), do: is_list(value)
  defp type?("string", value), do: is_binary(value)
  defp type?("integer", value), do: is_integer(value)
  defp type?("number", value), do: is_number(value)
  defp type?("boolean", value), do: is_boolean(value)
  defp type?("null", value), do: is_nil(value)
end
