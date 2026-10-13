defmodule Wotex.Profiles.Shape do
  @moduledoc false

  alias Wotex.Profiles.{Error, Instance, Limits}

  @inert ~w($schema $id definitions title description examples)
  @numeric ~w(minimum maximum exclusiveMinimum exclusiveMaximum multipleOf)
  @engineering %{
    "max_bytes" => 1_048_576,
    "max_depth" => 16,
    "max_nodes" => 100_000,
    "max_channels" => 1024,
    "max_definitions" => 1024,
    "max_bindings" => 64,
    "max_dependencies" => 1024,
    "max_numeric_digits" => 128
  }

  @doc false
  @spec check(term(), term(), pos_integer(), pos_integer()) ::
          {:ok, [map()], non_neg_integer(), boolean()} | {:error, Error.t()}
  def check(value, schema, steps, maximum) do
    state = %{remaining: steps, used: 0, errors: [], maximum: maximum, truncated: false}

    with {:ok, state} <- visit(value, schema, schema, "", state) do
      {:ok, Enum.reverse(state.errors), state.used, state.truncated}
    end
  end

  defp tick(%{remaining: 0}), do: Error.refusal(:input_limit)
  defp tick(state), do: {:ok, %{state | remaining: state.remaining - 1, used: state.used + 1}}

  defp visit(value, schema, root, path, state) do
    with {:ok, state} <- tick(state), do: node(value, schema, root, path, state)
  end

  defp node(_, true, _, _, state), do: {:ok, state}
  defp node(_, false, _, path, state), do: {:ok, error(state, path)}

  defp node(value, %{"$ref" => reference}, root, path, state) do
    with {:ok, state} <- tick(state),
         {:ok, state} <- tick(state),
         {:ok, schema} <- local(reference, root),
         do: visit(value, schema, root, path, state)
  end

  defp node(value, schema, root, path, state) do
    schema
    |> Map.keys()
    |> Enum.reject(&(&1 in @inert))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, state}, fn key, {:ok, state} ->
      with {:ok, state} <- tick(state),
           {:ok, state} <- assertion(key, schema[key], value, schema, root, path, state) do
        {:cont, {:ok, state}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp local("#", root), do: {:ok, root}

  defp local("#/" <> pointer, root) do
    value =
      pointer
      |> String.split("/")
      |> Enum.reduce(root, fn segment, acc ->
        key =
          segment
          |> String.replace("~1", "/")
          |> String.replace("~0", "~")

        if is_map(acc), do: Map.get(acc, key), else: nil
      end)

    if is_map(value) or is_boolean(value), do: {:ok, value}, else: Error.refusal(:invalid_contract)
  end

  defp local(_, _), do: Error.refusal(:invalid_contract)

  defp assertion("type", types, value, _, _, path, state) do
    types = if is_list(types), do: types, else: [types]
    checked(state, Enum.any?(types, &type?(value, &1)), path)
  end

  defp assertion("const", expected, value, _, _, path, state),
    do: checked(state, equal?(expected, value), path)

  defp assertion("enum", expected, value, _, _, path, state),
    do: checked(state, Enum.any?(expected, &equal?(&1, value)), path)

  defp assertion("required", names, value, _, _, path, state) when is_map(value) do
    {:ok,
     Enum.reduce(names, state, fn name, state ->
       if Map.has_key?(value, name), do: state, else: error(state, join(path, name))
     end)}
  end

  defp assertion("properties", properties, value, _, root, path, state) when is_map(value) do
    properties
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, state}, fn {name, schema}, {:ok, state} ->
      if Map.has_key?(value, name),
        do: continue(visit(value[name], schema, root, join(path, name), state)),
        else: {:cont, {:ok, state}}
    end)
  end

  defp assertion("additionalProperties", additional, value, schema, root, path, state)
       when is_map(value) do
    known = Map.keys(Map.get(schema, "properties", %{}))

    value
    |> Enum.reject(fn {key, _} -> key in known end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, state}, fn {_, child}, {:ok, state} ->
      continue(visit(child, additional, root, path, state))
    end)
  end

  defp assertion("propertyNames", schema, value, _, root, path, state) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, state}, fn key, {:ok, state} ->
      continue(visit(key, schema, root, path, state))
    end)
  end

  defp assertion("items", schema, values, _, root, path, state) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state}, fn {value, index}, {:ok, state} ->
      continue(visit(value, schema, root, join(path, Integer.to_string(index)), state))
    end)
  end

  defp assertion(key, bound, value, _, _, path, state)
       when key in ~w(minItems maxItems) and is_list(value),
       do: checked(state, bound?(key, length(value), bound), path)

  defp assertion(key, bound, value, _, _, path, state)
       when key in ~w(minProperties maxProperties) and is_map(value),
       do: checked(state, bound?(key, map_size(value), bound), path)

  defp assertion(key, bound, value, _, _, path, state)
       when key in ~w(minLength maxLength) and is_binary(value),
       do: checked(state, bound?(key, length(String.to_charlist(value)), bound), path)

  defp assertion("uniqueItems", true, values, _, _, path, state) when is_list(values),
    do: checked(state, unique?(values), path)

  defp assertion("pattern", pattern, value, _, _, path, state) when is_binary(value),
    do: checked(state, Regex.match?(Regex.compile!(pattern), value), path)

  defp assertion(key, bound, value, _, _, path, state) when key in @numeric and is_number(value) do
    {:ok, limits} = Limits.new(@engineering)

    case Instance.json(value, %{"type" => "number", key => bound}, limits, path) do
      :ok -> {:ok, state}
      {:error, %Error{code: :out_of_domain}} -> {:ok, error(state, path)}
      error -> error
    end
  end

  defp assertion(key, schemas, value, _, root, path, state) when key in ~w(anyOf oneOf allOf) do
    with {:ok, count, state} <- alternatives(schemas, value, root, path, state) do
      valid =
        case key do
          "anyOf" -> count >= 1
          "oneOf" -> count == 1
          "allOf" -> count == length(schemas)
        end

      checked(state, valid, path)
    end
  end

  defp assertion("not", schema, value, _, root, path, state) do
    with {:ok, count, state} <- alternatives([schema], value, root, path, state),
         do: checked(state, count == 0, path)
  end

  defp assertion(_, _, _, _, _, _, state), do: {:ok, state}

  defp alternatives(schemas, value, root, path, state) do
    Enum.reduce_while(schemas, {:ok, 0, state}, fn schema, {:ok, count, state} ->
      branch = %{state | errors: [], truncated: false}

      case visit(value, schema, root, path, branch) do
        {:ok, result} ->
          count = if result.errors == [] and not result.truncated, do: count + 1, else: count
          {:cont, {:ok, count, %{state | used: result.used, remaining: result.remaining}}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp checked(state, true, _), do: {:ok, state}
  defp checked(state, false, path), do: {:ok, error(state, path)}

  defp error(state, path) do
    if length(state.errors) < state.maximum do
      %{state | errors: [%{"code" => "invalid_input", "path" => path} | state.errors]}
    else
      %{state | truncated: true}
    end
  end

  defp continue({:ok, _} = result), do: {:cont, result}
  defp continue(error), do: {:halt, error}
  defp join(path, name), do: path <> "/" <> Wotex.JSON.pointer_segment(name)
  defp bound?("min" <> _, value, bound), do: value >= bound
  defp bound?(_, value, bound), do: value <= bound
  defp type?(nil, "null"), do: true
  defp type?(value, "boolean"), do: is_boolean(value)
  defp type?(value, "object"), do: is_map(value)
  defp type?(value, "array"), do: is_list(value)
  defp type?(value, "string"), do: is_binary(value)
  defp type?(value, "number"), do: is_number(value)
  defp type?(value, "integer") when is_integer(value), do: true
  defp type?(value, "integer") when is_float(value), do: value == trunc(value)
  defp type?(_, _), do: false
  defp equal?(a, b) when is_number(a) and is_number(b), do: a == b

  defp equal?(a, b) when is_list(a) and is_list(b) and length(a) == length(b),
    do: Enum.all?(Enum.zip(a, b), fn {a, b} -> equal?(a, b) end)

  defp equal?(a, b) when is_map(a) and is_map(b),
    do:
      Enum.sort(Map.keys(a)) == Enum.sort(Map.keys(b)) and
        Enum.all?(a, fn {key, value} -> equal?(value, b[key]) end)

  defp equal?(a, b), do: a === b
  defp unique?([]), do: true
  defp unique?([value | rest]), do: not Enum.any?(rest, &equal?(value, &1)) and unique?(rest)
end
