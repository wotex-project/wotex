defmodule Wotex.Nx.DataSchemaValidator do
  @moduledoc false

  alias Wotex.Nx.Error

  @spec validate(term(), map(), boolean()) :: :ok | {:error, Error.t()}
  def validate(value, schema, allow_non_finite?) when is_map(schema) do
    with :ok <- type(value, schema, allow_non_finite?),
         :ok <- enum(value, schema),
         :ok <- bounds(value, schema) do
      :ok
    end
  end

  defp type(value, %{"type" => "number"}, allow?)
       when is_number(value) or value in [:nan, :infinity, :neg_infinity],
       do: finite(value, allow?)

  defp type(value, %{"type" => "integer"}, _allow?) when is_integer(value), do: :ok
  defp type(value, %{"type" => "boolean"}, _allow?) when is_boolean(value), do: :ok

  defp type(values, %{"type" => "array", "items" => items} = schema, allow?)
       when is_list(values) and is_map(items) do
    with :ok <- array_size(values, schema) do
      Enum.reduce_while(values, :ok, fn value, :ok ->
        case validate(value, items, allow?) do
          :ok -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp type(_value, _schema, _allow?) do
    {:error,
     Error.new(
       :data_schema_type_mismatch,
       :encoding,
       "value does not match the numerical DataSchema type"
     )}
  end

  defp array_size(values, schema) do
    minimum = Map.get(schema, "minItems")
    maximum = Map.get(schema, "maxItems")

    if (is_nil(minimum) or length(values) >= minimum) and
         (is_nil(maximum) or length(values) <= maximum) do
      :ok
    else
      {:error,
       Error.new(
         :data_schema_shape_mismatch,
         :encoding,
         "array length does not match DataSchema bounds"
       )}
    end
  end

  defp finite(value, true)
       when is_number(value) or value in [:nan, :infinity, :neg_infinity],
       do: :ok

  defp finite(value, false) when is_integer(value), do: :ok

  defp finite(value, false) when value in [:nan, :infinity, :neg_infinity],
    do: non_finite_error()

  defp finite(value, false) when is_float(value) do
    <<_sign::1, exponent::11, _fraction::52>> = <<value::float-64>>

    if exponent != 2_047 do
      :ok
    else
      non_finite_error()
    end
  end

  defp non_finite_error,
    do: {:error, Error.new(:non_finite_value, :encoding, "non-finite values are not allowed")}

  defp enum(value, %{"enum" => values}) when is_list(values) do
    if value in values,
      do: :ok,
      else:
        {:error,
         Error.new(:data_schema_enum_mismatch, :encoding, "value is outside DataSchema enum")}
  end

  defp enum(value, %{"const" => expected}) do
    if value === expected,
      do: :ok,
      else:
        {:error,
         Error.new(:data_schema_const_mismatch, :encoding, "value does not match DataSchema const")}
  end

  defp enum(_value, _schema), do: :ok

  defp bounds(value, schema) when is_number(value) do
    checks = [
      {:minimum, Map.get(schema, "minimum"), &>=/2},
      {:maximum, Map.get(schema, "maximum"), &<=/2},
      {:exclusive_minimum, Map.get(schema, "exclusiveMinimum"), &>/2},
      {:exclusive_maximum, Map.get(schema, "exclusiveMaximum"), &</2}
    ]

    case Enum.find(checks, fn {_name, bound, compare} ->
           is_number(bound) and not compare.(value, bound)
         end) do
      nil ->
        :ok

      {name, _bound, _compare} ->
        {:error,
         Error.new(:data_schema_bound_mismatch, :encoding, "value violates a DataSchema bound", %{
           bound: name
         })}
    end
  end

  defp bounds(_value, _schema), do: :ok
end
