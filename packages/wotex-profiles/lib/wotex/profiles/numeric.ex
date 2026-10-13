defmodule Wotex.Profiles.Numeric do
  @moduledoc false

  alias Wotex.Profiles.{Error, Limits}

  @doc false
  @spec decimal(term(), Limits.t(), String.t()) ::
          {:ok, {integer(), integer()}} | {:error, Error.t()}
  def decimal(value, limits, path) when is_integer(value) or is_float(value) do
    {:ok, bytes} = Wotex.JSON.encode(value)
    decimal(Decimal.new(bytes), limits, path)
  end

  def decimal(%Decimal{sign: sign, coef: coefficient, exp: exponent}, limits, path)
      when is_integer(coefficient) do
    {coefficient, exponent} = normalize(sign * coefficient, exponent)

    if exponent in -18..18 and
         abs(coefficient) < Integer.pow(10, limits.data["max_numeric_digits"]) do
      {:ok, {coefficient, exponent}}
    else
      Error.refusal(:numeric_limit, path)
    end
  end

  def decimal(_, _, path), do: Error.refusal(:invalid_input, path)

  defp normalize(0, _), do: {0, 0}

  defp normalize(coefficient, exponent) when rem(coefficient, 10) == 0,
    do: normalize(div(coefficient, 10), exponent + 1)

  defp normalize(coefficient, exponent), do: {coefficient, exponent}

  @doc false
  @spec integer(term(), integer(), integer(), String.t()) ::
          {:ok, integer()} | {:error, Error.t()}
  def integer(value, minimum, maximum, path) when is_binary(value) and byte_size(value) <= 20 do
    case Integer.parse(value) do
      {number, ""} when number >= minimum and number <= maximum ->
        if Integer.to_string(number) == value,
          do: {:ok, number},
          else: Error.refusal(:invalid_input, path)

      _ ->
        Error.refusal(:invalid_input, path)
    end
  end

  def integer(_, _, _, path), do: Error.refusal(:invalid_input, path)

  @doc false
  @spec rational(map(), String.t(), String.t(), boolean(), String.t()) ::
          :ok | {:error, Error.t()}
  def rational(data, numerator, denominator, positive, path) do
    minimum = if positive, do: 1, else: -9_223_372_036_854_775_808

    with {:ok, n} <- integer(data[numerator], minimum, 9_223_372_036_854_775_807, path),
         {:ok, d} <- integer(data[denominator], 1, 9_223_372_036_854_775_807, path),
         true <- Integer.gcd(n, d) == 1 do
      :ok
    else
      false -> Error.refusal(:invalid_input, path)
      error -> error
    end
  end
end
