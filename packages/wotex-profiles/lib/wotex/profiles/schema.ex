defmodule Wotex.Profiles.Schema do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Limits, Numeric}

  @common ~w(type enum const title description readOnly writeOnly observable)
  @numeric ~w(minimum maximum exclusiveMinimum exclusiveMaximum multipleOf)

  @doc false
  @spec check(term(), Limits.t(), String.t()) :: :ok | {:error, Error.t()}
  def check(data, limits, path) do
    case Wotex.DataSchema.new(data, Grammar.options(limits)) do
      {:ok, schema} -> visit(Wotex.DataSchema.to_map(schema), limits, path)
      _ -> Error.refusal(:unsupported_schema, path)
    end
  end

  defp visit(data, limits, path) when is_map(data) do
    with {:ok, operators} <- operators(data["type"], path),
         :ok <- schema_fields(data, operators, path),
         :ok <- metadata(data, path),
         :ok <- literals(data, limits, path) do
      specific(data, limits, path)
    end
  end

  defp visit(_, _, path), do: Error.refusal(:unsupported_schema, path)

  defp operators(type, _) when type in ~w(null boolean), do: {:ok, []}
  defp operators(type, _) when type in ~w(number integer), do: {:ok, @numeric}
  defp operators("string", _), do: {:ok, ~w(minLength maxLength)}
  defp operators("array", _), do: {:ok, ~w(items minItems maxItems)}
  defp operators("object", _), do: {:ok, ~w(properties required additionalProperties)}
  defp operators(_, path), do: Error.refusal(:unsupported_schema, path)

  defp schema_fields(data, operators, path) do
    case Grammar.fields(data, ["type"], path, @common ++ operators) do
      :ok -> :ok
      _ -> Error.refusal(:unsupported_schema, path)
    end
  end

  defp metadata(data, path) do
    Grammar.each(
      Map.to_list(Map.take(data, ~w(title description readOnly writeOnly observable))),
      fn
        {key, value} when key in ~w(title description) and is_binary(value) -> :ok
        {key, value} when key in ~w(readOnly writeOnly observable) and is_boolean(value) -> :ok
        _ -> Error.refusal(:unsupported_schema, path)
      end
    )
  end

  defp literals(data, limits, path) do
    with :ok <- enum(data, path) do
      literal_numbers(Map.take(data, ~w(enum const)), limits, path)
    end
  end

  defp enum(%{"enum" => values}, path) when is_list(values) and length(values) in 1..256 do
    encoded =
      Enum.map(values, fn value ->
        {:ok, bytes} = Wotex.JSON.encode(value)
        bytes
      end)

    if length(Enum.uniq(encoded)) == length(encoded),
      do: :ok,
      else: Error.refusal(:unsupported_schema, path <> "/enum")
  end

  defp enum(%{"enum" => _}, path), do: Error.refusal(:unsupported_schema, path <> "/enum")
  defp enum(_, _), do: :ok

  defp literal_numbers(value, limits, path) when is_number(value) do
    case Numeric.decimal(value, limits, path) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp literal_numbers(value, limits, path) when is_list(value),
    do: Grammar.each(value, &literal_numbers(&1, limits, path))

  defp literal_numbers(value, limits, path) when is_map(value),
    do: Grammar.each(Map.values(value), &literal_numbers(&1, limits, path))

  defp literal_numbers(_, _, _), do: :ok

  defp specific(%{"type" => type} = data, limits, path) when type in ~w(number integer) do
    Grammar.each(Map.to_list(Map.take(data, @numeric)), fn {key, value} ->
      with {:ok, {coefficient, _}} <- Numeric.decimal(value, limits, path <> "/" <> key),
           true <- key != "multipleOf" or coefficient > 0 do
        :ok
      else
        false -> Error.refusal(:unsupported_schema, path <> "/multipleOf")
        error -> error
      end
    end)
  end

  defp specific(%{"type" => "string"} = data, _, path),
    do: sizes(data, "minLength", "maxLength", path)

  defp specific(%{"type" => "array"} = data, limits, path) do
    with true <- Map.has_key?(data, "items"),
         :ok <- sizes(data, "minItems", "maxItems", path) do
      visit(data["items"], limits, path <> "/items")
    else
      false -> Error.refusal(:unsupported_schema, path)
      error -> error
    end
  end

  defp specific(%{"type" => "object"} = data, limits, path) do
    with %{} = properties when not is_struct(properties) <- data["properties"],
         false <- data["additionalProperties"],
         :ok <- required(Map.get(data, "required", []), properties, path),
         :ok <-
           Grammar.each(Map.to_list(properties), fn {key, child} ->
             with :ok <- Grammar.text(key, 128, path <> "/properties"),
                  do: visit(child, limits, path <> "/properties")
           end) do
      :ok
    else
      {:error, _} = error -> error
      _ -> Error.refusal(:unsupported_schema, path)
    end
  end

  defp specific(_, _, _), do: :ok

  defp required(values, properties, path) when is_list(values) do
    if values == Enum.sort(Enum.uniq(values)) and
         Enum.all?(values, &(is_binary(&1) and Map.has_key?(properties, &1))),
       do: :ok,
       else: Error.refusal(:unsupported_schema, path <> "/required")
  end

  defp required(_, _, path), do: Error.refusal(:unsupported_schema, path <> "/required")

  defp sizes(data, minimum, maximum, path) do
    lower = Map.get(data, minimum, 0)
    upper = Map.get(data, maximum, 1_048_576)

    if is_integer(lower) and is_integer(upper) and lower >= 0 and upper >= lower and
         upper <= 1_048_576, do: :ok, else: Error.refusal(:unsupported_schema, path)
  end
end
