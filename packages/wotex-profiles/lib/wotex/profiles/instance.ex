defmodule Wotex.Profiles.Instance do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Limits, Numeric, Schema}

  @type logical :: term()
  @numeric ~w(minimum maximum exclusiveMinimum exclusiveMaximum multipleOf)

  @doc false
  @spec json(term(), map(), Limits.t(), String.t()) :: :ok | {:error, Error.t()}
  def json(value, schema, limits, path) do
    with {:ok, _, limits} <- Grammar.admit(value, limits),
         :ok <- Schema.check(schema, limits, path),
         {:ok, value} <- native(value, limits, path) do
      visit(value, schema, limits, path)
    end
  end

  @doc false
  @spec c02(term(), map(), Limits.t(), String.t()) :: :ok | {:error, Error.t()}
  def c02(value, schema, limits, path) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, value} <- Wotex.Runtime.Codec.Value.validate(value),
         :ok <- Schema.check(schema, limits, path),
         {:ok, value} <- typed(value, path) do
      visit(value, schema, limits, path)
    else
      {:error, %Error{}} = error -> error
      _ -> Error.refusal(:invalid_input, path)
    end
  end

  defp native(value, limits, path) when is_number(value) do
    with {:ok, {coefficient, exponent}} <- Numeric.decimal(value, limits, path),
         do: {:ok, {:number, coefficient, exponent}}
  end

  defp native(value, limits, path) when is_list(value),
    do: collect(value, &native(&1, limits, path))

  defp native(value, limits, path) when is_map(value) do
    with {:ok, entries} <-
           collect(Map.to_list(value), fn {key, child} ->
             with {:ok, child} <- native(child, limits, path), do: {:ok, {key, child}}
           end),
         do: {:ok, Map.new(entries)}
  end

  defp native(value, _, _), do: {:ok, value}

  defp typed(%{"type" => "null"}, _), do: {:ok, nil}
  defp typed(%{"type" => type, "value" => value}, _) when type in ~w(boolean text), do: {:ok, value}

  defp typed(%{"type" => type, "value" => value}, _) when type in ~w(sint uint),
    do: {:ok, {:number, String.to_integer(value), 0}}

  defp typed(%{"type" => "decimal", "coefficient" => value, "exponent" => exponent}, _),
    do: {:ok, {:number, String.to_integer(value), exponent}}

  defp typed(%{"type" => "list", "items" => values}, path), do: collect(values, &typed(&1, path))

  defp typed(%{"type" => "object", "entries" => entries}, path) do
    with {:ok, entries} <-
           collect(entries, fn entry ->
             with {:ok, child} <- typed(entry["value"], path), do: {:ok, {entry["key"], child}}
           end),
         do: {:ok, Map.new(entries)}
  end

  defp typed(%{"type" => "bytes"}, path), do: Error.refusal(:codec_required, path)

  defp collect(values, function) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case function.(value) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp visit(value, schema, limits, path) do
    with true <- type?(value, schema["type"]),
         :ok <- constants(value, schema, limits, path) do
      constraints(value, schema, limits, path)
    else
      false -> domain(path)
      error -> error
    end
  end

  defp type?(nil, "null"), do: true
  defp type?(value, "boolean"), do: is_boolean(value)
  defp type?(value, "string"), do: is_binary(value)
  defp type?(value, "array"), do: is_list(value)
  defp type?(value, "object"), do: is_map(value)
  defp type?({:number, _, _}, "number"), do: true
  defp type?({:number, _, exponent}, "integer"), do: exponent >= 0
  defp type?(_, _), do: false

  defp constants(value, schema, limits, path) do
    with :ok <- constant(value, schema, limits, path),
         do: enumeration(value, schema, limits, path)
  end

  defp constant(value, %{"const" => expected}, limits, path) do
    with {:ok, expected} <- native(expected, limits, path),
         {:ok, equal} <- equal(value, expected, limits, path) do
      if equal, do: :ok, else: domain(path)
    end
  end

  defp constant(_, _, _, _), do: :ok

  defp enumeration(value, %{"enum" => values}, limits, path) do
    Enum.reduce_while(values, domain(path), fn expected, _ ->
      with {:ok, expected} <- native(expected, limits, path),
           {:ok, equal} <- equal(value, expected, limits, path) do
        if equal, do: {:halt, :ok}, else: {:cont, domain(path)}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp enumeration(_, _, _, _), do: :ok

  defp constraints({:number, _, _} = value, schema, limits, path) do
    Grammar.each(Map.to_list(Map.take(schema, @numeric)), fn {key, expected} ->
      with {:ok, expected} <- native(expected, limits, path),
           {:ok, left} <- fraction(value, limits, path),
           {:ok, right} <- fraction(expected, limits, path),
           {:ok, result} <- numeric(key, left, right, limits, path) do
        if result, do: :ok, else: domain(path)
      end
    end)
  end

  defp constraints(value, %{"type" => "string"} = schema, _, path),
    do: size(length(String.to_charlist(value)), schema, "minLength", "maxLength", path)

  defp constraints(values, %{"type" => "array"} = schema, limits, path) do
    with :ok <- size(length(values), schema, "minItems", "maxItems", path) do
      Grammar.each(Enum.with_index(values), fn {value, index} ->
        visit(value, schema["items"], limits, path <> "/" <> Integer.to_string(index))
      end)
    end
  end

  defp constraints(value, %{"type" => "object"} = schema, limits, path) do
    properties = schema["properties"]

    if Enum.all?(Map.keys(value), &Map.has_key?(properties, &1)) and
         Enum.all?(Map.get(schema, "required", []), &Map.has_key?(value, &1)) do
      Grammar.each(Map.to_list(value), fn {key, child} ->
        visit(child, properties[key], limits, path)
      end)
    else
      domain(path)
    end
  end

  defp constraints(_, _, _, _), do: :ok

  defp size(value, schema, minimum, maximum, path) do
    if value >= Map.get(schema, minimum, 0) and value <= Map.get(schema, maximum, 1_048_576),
      do: :ok,
      else: domain(path)
  end

  defp equal({:number, _, _} = a, {:number, _, _} = b, limits, path) do
    with {:ok, a} <- fraction(a, limits, path),
         {:ok, b} <- fraction(b, limits, path),
         {:ok, {left, right}} <- products(a, b, limits, path),
         do: {:ok, left == right}
  end

  defp equal(a, b, limits, path) when is_list(a) and is_list(b) and length(a) == length(b),
    do: equal_children(Enum.zip(a, b), limits, path)

  defp equal(a, b, limits, path) when is_map(a) and is_map(b) do
    if Enum.sort(Map.keys(a)) == Enum.sort(Map.keys(b)),
      do: equal_children(Enum.map(a, fn {key, value} -> {value, b[key]} end), limits, path),
      else: {:ok, false}
  end

  defp equal(a, b, _, _), do: {:ok, a === b}

  defp equal_children(values, limits, path) do
    Enum.reduce_while(values, {:ok, true}, fn {a, b}, _ ->
      case equal(a, b, limits, path) do
        {:ok, true} -> {:cont, {:ok, true}}
        result -> {:halt, result}
      end
    end)
  end

  defp fraction({:number, coefficient, exponent}, limits, path) when exponent in -18..18 do
    maximum = maximum(limits)

    if abs(exponent) >= limits.data["max_numeric_digits"] or abs(coefficient) > maximum do
      Error.refusal(:numeric_limit, path)
    else
      factor = Integer.pow(10, abs(exponent))

      if exponent < 0 do
        divisor = Integer.gcd(coefficient, factor)
        {:ok, {div(coefficient, divisor), div(factor, divisor)}}
      else
        with {:ok, number} <- product(coefficient, factor, maximum, path), do: {:ok, {number, 1}}
      end
    end
  end

  defp fraction(_, _, path), do: Error.refusal(:numeric_limit, path)

  defp products({a, b}, {c, d}, limits, path) do
    with {:ok, left} <- product(a, d, maximum(limits), path),
         {:ok, right} <- product(c, b, maximum(limits), path),
         do: {:ok, {left, right}}
  end

  defp product(a, b, maximum, path) do
    if a == 0 or abs(b) <= div(maximum, abs(a)),
      do: {:ok, a * b},
      else: Error.refusal(:numeric_limit, path)
  end

  defp maximum(limits), do: Integer.pow(10, limits.data["max_numeric_digits"]) - 1

  defp numeric(key, left, right, limits, path) do
    with {:ok, {a, b}} <- products(left, right, limits, path) do
      result =
        case key do
          "minimum" -> a >= b
          "maximum" -> a <= b
          "exclusiveMinimum" -> a > b
          "exclusiveMaximum" -> a < b
          "multipleOf" -> rem(a, b) == 0
        end

      {:ok, result}
    end
  end

  defp domain(path), do: Error.refusal(:out_of_domain, path)
end
