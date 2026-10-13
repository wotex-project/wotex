defmodule Wotex.Profiles.Arithmetic do
  @moduledoc false

  alias Wotex.Profiles.{Error, Limits}

  @type fraction :: {integer(), pos_integer()}
  @type result :: {:ok, fraction()} | {:error, Error.t()}

  @doc false
  @spec coordinates(map(), map(), map(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def coordinates(value, source, target, limits) do
    maximum = Integer.pow(10, limits.data["max_numeric_digits"]) - 1

    with {:ok, x} <- number(value, maximum),
         {:ok, source_scale} <- coordinate(source, "scale", maximum),
         {:ok, source_offset} <- coordinate(source, "offset", maximum),
         {:ok, target_scale} <- coordinate(target, "scale", maximum),
         {:ok, target_offset} <- coordinate(target, "offset", maximum),
         {:ok, scaled} <- multiply(x, source_scale, maximum),
         {:ok, canonical} <- add(scaled, source_offset, maximum),
         {:ok, shifted} <- add(canonical, negate(target_offset), maximum),
         {:ok, result} <- multiply(shifted, reciprocal(target_scale), maximum) do
      output(result, maximum)
    end
  end

  defp coordinate(data, kind, maximum) do
    bounded({String.to_integer(data[kind <> "_n"]), String.to_integer(data[kind <> "_d"])}, maximum)
  end

  defp number(%{"type" => kind, "value" => value}, maximum) when kind in ~w(sint uint),
    do: bounded({String.to_integer(value), 1}, maximum)

  defp number(%{"type" => "decimal", "coefficient" => value, "exponent" => exponent}, maximum)
       when exponent in -18..18 do
    coefficient = String.to_integer(value)

    with {:ok, factor} <- power(10, abs(exponent), maximum) do
      if exponent < 0 do
        bounded(reduce({coefficient, factor}), maximum)
      else
        with {:ok, number} <- product(coefficient, factor, maximum),
             do: bounded({number, 1}, maximum)
      end
    end
  end

  defp number(%{"type" => "decimal"}, _), do: failure(:numeric_limit)
  defp number(_, _), do: Error.refusal(:unsupported_semantics, "/value")

  defp bounded({numerator, denominator} = fraction, maximum) do
    if abs(numerator) <= maximum and denominator <= maximum,
      do: {:ok, fraction},
      else: failure(:numeric_limit)
  end

  defp reduce({numerator, denominator}) do
    divisor = Integer.gcd(numerator, denominator)
    {div(numerator, divisor), div(denominator, divisor)}
  end

  defp negate({numerator, denominator}), do: {-numerator, denominator}
  defp reciprocal({numerator, denominator}), do: {denominator, numerator}

  defp multiply({a, b}, {c, d}, maximum) do
    left = Integer.gcd(a, d)
    right = Integer.gcd(c, b)

    with {:ok, numerator} <- product(div(a, left), div(c, right), maximum),
         {:ok, denominator} <- product(div(b, right), div(d, left), maximum) do
      {:ok, {numerator, denominator}}
    end
  end

  defp add({a, b}, {c, d}, maximum) do
    divisor = Integer.gcd(b, d)

    with {:ok, left} <- product(a, div(d, divisor), maximum),
         {:ok, right} <- product(c, div(b, divisor), maximum),
         {:ok, denominator} <- product(div(b, divisor), d, maximum),
         {:ok, numerator} <- sum(left, right, maximum) do
      {:ok, reduce({numerator, denominator})}
    end
  end

  # Division compares the prospective product before allocating it.
  defp product(a, b, maximum) do
    if a == 0 or abs(b) <= div(maximum, abs(a)),
      do: {:ok, a * b},
      else: failure(:numeric_limit)
  end

  defp sum(a, b, maximum) do
    if (b >= 0 and a <= maximum - b) or (b < 0 and a >= -maximum - b),
      do: {:ok, a + b},
      else: failure(:numeric_limit)
  end

  defp power(base, exponent, maximum), do: power(base, exponent, maximum, 1)
  defp power(_, 0, _, accumulator), do: {:ok, accumulator}

  defp power(base, exponent, maximum, accumulator) do
    with {:ok, next} <- product(accumulator, base, maximum),
         do: power(base, exponent - 1, maximum, next)
  end

  defp output({numerator, 1}, _)
       when numerator >= -9_223_372_036_854_775_808 and numerator <= 9_223_372_036_854_775_807,
       do: checked(%{"type" => "sint", "value" => Integer.to_string(numerator)})

  defp output({numerator, 1}, _) when numerator > 0 and numerator <= 18_446_744_073_709_551_615,
    do: checked(%{"type" => "uint", "value" => Integer.to_string(numerator)})

  defp output({numerator, denominator}, maximum) do
    {after_two, twos} = factors(denominator, 2, 0)
    {rest, fives} = factors(after_two, 5, 0)

    if rest == 1 do
      exponent = max(twos, fives)

      with {:ok, two} <- power(2, exponent - twos, maximum),
           {:ok, five} <- power(5, exponent - fives, maximum),
           {:ok, coefficient} <- product(numerator, two, maximum),
           {:ok, coefficient} <- product(coefficient, five, maximum) do
        {coefficient, exponent} = normalize(coefficient, -exponent)

        checked(%{
          "type" => "decimal",
          "coefficient" => Integer.to_string(coefficient),
          "exponent" => exponent
        })
      end
    else
      failure(:inexact_conversion)
    end
  end

  defp factors(value, factor, count) when rem(value, factor) == 0,
    do: factors(div(value, factor), factor, count + 1)

  defp factors(value, _, count), do: {value, count}
  defp normalize(0, _), do: {0, 0}

  defp normalize(coefficient, exponent) when rem(coefficient, 10) == 0,
    do: normalize(div(coefficient, 10), exponent + 1)

  defp normalize(coefficient, exponent), do: {coefficient, exponent}

  defp checked(value) do
    case Wotex.Runtime.Codec.Value.validate(value) do
      {:ok, value} -> {:ok, value}
      _ -> failure(:numeric_limit)
    end
  end

  defp failure(code), do: Error.refusal(code, "/value")
end
