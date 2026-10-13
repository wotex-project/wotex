defmodule Wotex.Profiles.Parser do
  @moduledoc false

  alias Wotex.Profiles.{Error, Grammar, Limits, Numeric}

  @doc false
  @spec decode(term(), term()) :: {:ok, term(), Limits.t()} | {:error, Error.t()}
  def decode(bytes, limits) when is_binary(bytes) do
    with {:ok, limits} <- Limits.new(limits),
         true <- byte_size(bytes) <= limits.data["max_bytes"],
         :ok <- scan(bytes, false, limits),
         {:ok, data} <- Wotex.JSON.decode(bytes, Grammar.options(limits)),
         {:ok, exact} <- Jason.decode(bytes, floats: :decimals),
         :ok <- unchanged(exact, data, limits) do
      {:ok, data, limits}
    else
      {:error, %Error{}} = error -> error
      false -> Error.refusal(:input_limit)
      {:error, %Wotex.Error{code: code}} -> Grammar.core_refusal(code)
      _ -> Error.refusal(:invalid_input)
    end
  end

  def decode(_, _), do: Error.refusal(:invalid_input)

  @doc false
  @spec guard_numbers(binary(), pos_integer()) :: :ok | {:error, Error.t()}
  def guard_numbers(bytes, maximum),
    do: scan(bytes, false, %Limits{data: %{"max_numeric_digits" => maximum}})

  @doc false
  @spec decode_envelope(binary(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def decode_envelope(bytes, options) do
    limits = %Limits{data: %{"max_numeric_digits" => 128}}

    with :ok <- guard_numbers(bytes, 128),
         {:ok, data} <- Wotex.JSON.decode(bytes, options),
         {:ok, exact} <- Jason.decode(bytes, floats: :decimals),
         :ok <- unchanged(exact, data, limits),
         do: {:ok, data},
         else: (
           {:error, %Wotex.Error{code: code}} -> Grammar.core_refusal(code)
           error -> error
         )
  end

  @doc false
  @spec native_numbers(term()) :: :ok | {:error, Error.t()}
  def native_numbers(value) when is_integer(value) do
    if abs(value) < Integer.pow(10, 128), do: :ok, else: Error.refusal(:numeric_limit)
  end

  def native_numbers(value) when is_float(value) do
    case Numeric.decimal(value, %Limits{data: %{"max_numeric_digits" => 128}}, "") do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def native_numbers(values) when is_list(values), do: Grammar.each(values, &native_numbers/1)

  def native_numbers(value) when is_map(value),
    do: Grammar.each(Map.values(value), &native_numbers/1)

  def native_numbers(_), do: :ok

  defp scan(<<>>, _, _), do: :ok
  defp scan(<<?\\, _, rest::binary>>, true, limits), do: scan(rest, true, limits)
  defp scan(<<?", rest::binary>>, inside, limits), do: scan(rest, not inside, limits)

  defp scan(<<c, rest::binary>>, false, limits) when c in ?0..?9 or c == ?- do
    number(rest, limits, if(c == ?-, do: 0, else: 1), 0, false, <<c>>)
  end

  defp scan(<<_, rest::binary>>, inside, limits), do: scan(rest, inside, limits)

  defp number(rest, limits, coefficient, exponent, in_exponent, token) do
    cond do
      coefficient > limits.data["max_numeric_digits"] or exponent > 6 ->
        Error.refusal(:numeric_limit)

      byte_size(token) > limits.data["max_numeric_digits"] + 14 ->
        Error.refusal(:invalid_input)

      true ->
        number_next(rest, limits, coefficient, exponent, in_exponent, token)
    end
  end

  defp number_next(<<c, rest::binary>>, limits, coefficient, exponent, in_exponent, token)
       when c in ?0..?9 do
    if in_exponent,
      do: number(rest, limits, coefficient, exponent + 1, true, token <> <<c>>),
      else: number(rest, limits, coefficient + 1, exponent, false, token <> <<c>>)
  end

  defp number_next(<<c, rest::binary>>, limits, coefficient, exponent, _, token)
       when c in [?e, ?E],
       do: number(rest, limits, coefficient, exponent, true, token <> <<c>>)

  defp number_next(<<c, rest::binary>>, limits, coefficient, exponent, in_exponent, token)
       when c in [?., ?+, ?-],
       do: number(rest, limits, coefficient, exponent, in_exponent, token <> <<c>>)

  defp number_next(rest, limits, _, _, _, token) do
    with :ok <- token(token, limits), do: scan(rest, false, limits)
  end

  defp token(token, limits) do
    case Regex.named_captures(
           ~r/\A(?<sign>-?)(?<integer>0|[1-9][0-9]*)(?:\.(?<fraction>[0-9]+))?(?:[eE](?<exponent>[+-]?[0-9]+))?\z/,
           token
         ) do
      %{} = parts ->
        exponent = if parts["exponent"] == "", do: 0, else: String.to_integer(parts["exponent"])

        number = %Decimal{
          sign: if(parts["sign"] == "-", do: -1, else: 1),
          coef: String.to_integer(parts["integer"] <> parts["fraction"]),
          exp: exponent - byte_size(parts["fraction"])
        }

        if parts["fraction"] == "" and parts["exponent"] == "" do
          :ok
        else
          case Numeric.decimal(number, limits, "") do
            {:ok, _} -> :ok
            error -> error
          end
        end

      _ ->
        Error.refusal(:invalid_input)
    end
  end

  defp unchanged(%Decimal{} = exact, value, limits) do
    with {:ok, original} <- Numeric.decimal(exact, limits, ""),
         {:ok, normalized} <- Numeric.decimal(value, limits, ""),
         true <- original == normalized do
      :ok
    else
      false -> Error.refusal(:numeric_limit)
      error -> error
    end
  end

  defp unchanged(exact, value, limits) when is_list(exact) do
    Grammar.each(Enum.zip(exact, value), fn {a, b} -> unchanged(a, b, limits) end)
  end

  defp unchanged(exact, value, limits) when is_map(exact) do
    Grammar.each(Map.to_list(exact), fn {key, child} -> unchanged(child, value[key], limits) end)
  end

  defp unchanged(_, _, _), do: :ok
end
