defmodule Wotex.Lab.Island.CanonicalJSON do
  @moduledoc "Canonical compact I-JSON bytes used by the Lab island protocol."

  @max_depth 16
  @max_string_bytes 8 * 1_024
  @max_safe_integer 9_007_199_254_740_991
  @secret ~r/(?:^|_)(?:authorization|cookie|credential|password|secret|socket|token)(?:_|$)/i

  @doc "Validates an I-JSON value and returns canonical UTF-8 bytes."
  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value) do
    with :ok <- validate(value, 0), do: {:ok, IO.iodata_to_binary(canonical(value))}
  end

  @doc "Returns the lowercase hexadecimal SHA-256 digest of canonical bytes."
  @spec digest(term()) :: {:ok, String.t()} | {:error, term()}
  def digest(value) do
    with {:ok, bytes} <- encode(value),
         do: {:ok, :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)}
  end

  defp validate(_, depth) when depth > @max_depth,
    do: {:error, {:island_limit, :depth, depth, @max_depth}}

  defp validate(nil, _), do: :ok
  defp validate(value, _) when is_boolean(value), do: :ok
  defp validate(value, _) when is_integer(value) and abs(value) <= @max_safe_integer, do: :ok

  defp validate(value, _) when is_float(value) do
    with encoded when is_binary(encoded) <- JSON.encode!(value),
         true <- value != trunc(value) or abs(value) <= @max_safe_integer do
      :ok
    else
      false -> {:error, :invalid_island_number}
    end
  rescue
    _ -> {:error, :invalid_island_number}
  end

  defp validate(value, _) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= @max_string_bytes,
      do: :ok,
      else: {:error, {:island_limit, :string_bytes, byte_size(value), @max_string_bytes}}
  end

  defp validate(value, depth) when is_list(value), do: validate_many(value, depth + 1)

  defp validate(value, depth) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <- string_pairs(value),
         :ok <- validate_keys(pairs) do
      validate_many(Enum.map(pairs, &elem(&1, 1)), depth + 1)
    end
  end

  defp validate(_, _), do: {:error, :invalid_island_json}

  defp validate_many(values, depth) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validate(value, depth) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp string_pairs(map) do
    pairs = Enum.map(map, fn {key, value} -> {to_string(key), value} end)
    keys = Enum.map(pairs, &elem(&1, 0))

    if length(keys) == MapSet.size(MapSet.new(keys)),
      do: {:ok, pairs},
      else: {:error, :duplicate_island_json_key}
  end

  defp validate_keys(pairs) do
    if Enum.all?(pairs, fn {key, _} ->
         String.valid?(key) and byte_size(key) <= @max_string_bytes and
           not Regex.match?(@secret, key)
       end),
       do: :ok,
       else: {:error, :secret_or_invalid_island_field}
  end

  defp canonical(nil), do: "null"
  defp canonical(true), do: "true"
  defp canonical(false), do: "false"
  defp canonical(value) when is_binary(value), do: JSON.encode!(value)
  defp canonical(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical(value) when is_float(value), do: canonical_float(value)

  defp canonical(value) when is_list(value),
    do: ["[", Enum.intersperse(Enum.map(value, &canonical/1), ","), "]"]

  defp canonical(value) when is_map(value) do
    pairs =
      value
      |> string_pairs()
      |> elem(1)
      |> Enum.sort_by(&elem(&1, 0))

    encoded = Enum.map(pairs, fn {key, item} -> [JSON.encode!(key), ":", canonical(item)] end)
    ["{", Enum.intersperse(encoded, ","), "}"]
  end

  defp canonical_float(value) when value == 0.0, do: "0"

  defp canonical_float(value) do
    {sign, unsigned} = split_sign(:erlang.float_to_binary(value, [:short]))
    {mantissa, exponent} = split_exponent(unsigned)
    {digits, decimal_position} = mantissa_digits(mantissa)
    digits = String.trim_trailing(digits, "0")
    decimal_position = decimal_position + exponent
    sign <> format_float_digits(digits, decimal_position)
  end

  defp split_sign("-" <> unsigned), do: {"-", unsigned}
  defp split_sign(unsigned), do: {"", unsigned}

  defp split_exponent(value) do
    case String.split(value, "e", parts: 2) do
      [mantissa] -> {mantissa, 0}
      [mantissa, exponent] -> {mantissa, String.to_integer(exponent)}
    end
  end

  defp mantissa_digits(mantissa) do
    case String.split(mantissa, ".", parts: 2) do
      [integer] -> {integer, byte_size(integer)}
      [integer, fraction] -> {integer <> fraction, byte_size(integer)}
    end
  end

  defp format_float_digits(digits, decimal_position)
       when decimal_position <= 0 and decimal_position > -6 do
    "0." <> String.duplicate("0", -decimal_position) <> digits
  end

  defp format_float_digits(digits, decimal_position)
       when decimal_position > 0 and decimal_position <= byte_size(digits) do
    case String.split_at(digits, decimal_position) do
      {integer, ""} -> integer
      {integer, fraction} -> integer <> "." <> fraction
    end
  end

  defp format_float_digits(digits, decimal_position)
       when decimal_position > byte_size(digits) and decimal_position <= 21 do
    digits <> String.duplicate("0", decimal_position - byte_size(digits))
  end

  defp format_float_digits(digits, decimal_position) do
    {head, tail} = String.split_at(digits, 1)
    coefficient = if tail == "", do: head, else: head <> "." <> tail
    exponent = decimal_position - 1
    exponent_sign = if exponent >= 0, do: "+", else: ""
    coefficient <> "e" <> exponent_sign <> Integer.to_string(exponent)
  end
end
