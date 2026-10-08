defmodule Wotex.Runtime.Implementation.JSON do
  @moduledoc false

  # This integer-only JCS subset is independent of root provisioning tooling.
  # Parsing counts nodes and collection members before allocating the next one.
  @defaults %{bytes: 65_536, depth: 12, nodes: 4096, entries: 1024, string: 4096}
  @safe 9_007_199_254_740_991

  @doc false
  @spec decode(term(), map()) :: {:ok, term()} | {:error, :invalid_descriptor | :limit_exceeded}
  def decode(input, limits \\ %{})

  def decode(input, limits) when is_binary(input) do
    limits = Map.merge(@defaults, limits)

    if byte_size(input) <= limits.bytes and String.valid?(input) do
      with {:ok, value, rest, _} <- parse(skip(input), 0, 0, limits),
           true <- skip(rest) == "" do
        {:ok, value}
      else
        {:error, code} -> {:error, code}
        _ -> {:error, :invalid_descriptor}
      end
    else
      {:error, if(byte_size(input) > limits.bytes, do: :limit_exceeded, else: :invalid_descriptor)}
    end
  end

  def decode(_, _), do: {:error, :invalid_descriptor}

  @doc false
  @spec encode(term(), map()) :: {:ok, binary()} | {:error, :invalid_descriptor | :limit_exceeded}
  def encode(value, limits \\ %{}) do
    limits = Map.merge(@defaults, limits)

    with {:ok, encoded, _, _} <- emit(value, 0, 0, 0, limits) do
      {:ok, IO.iodata_to_binary(encoded)}
    end
  end

  @doc false
  @spec digest(term()) :: {:ok, String.t()} | {:error, :invalid_descriptor | :limit_exceeded}
  def digest(value) do
    with {:ok, encoded} <- encode(value) do
      {:ok, :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)}
    end
  end

  defp parse(_, _, nodes, limits) when nodes >= limits.nodes, do: {:error, :limit_exceeded}

  defp parse(<<?{, rest::binary>>, depth, nodes, limits),
    do: object(skip(rest), %{}, depth + 1, nodes + 1, limits, false)

  defp parse(<<?[, rest::binary>>, depth, nodes, limits),
    do: array(skip(rest), [], 0, depth + 1, nodes + 1, limits, false)

  defp parse(<<?", rest::binary>>, _, nodes, limits) do
    with {:ok, value, rest} <- string(rest, [], 0, limits.string) do
      {:ok, value, rest, nodes + 1}
    end
  end

  defp parse("null" <> rest, _, nodes, _), do: {:ok, nil, rest, nodes + 1}
  defp parse("true" <> rest, _, nodes, _), do: {:ok, true, rest, nodes + 1}
  defp parse("false" <> rest, _, nodes, _), do: {:ok, false, rest, nodes + 1}

  defp parse(input, _, nodes, _) do
    {token, rest} = number(input, <<>>)

    if byte_size(token) <= 17 and Regex.match?(~r/\A-?(0|[1-9][0-9]*)\z/, token) do
      value = String.to_integer(token)
      if abs(value) <= @safe, do: {:ok, value, rest, nodes + 1}, else: {:error, :invalid_descriptor}
    else
      {:error, :invalid_descriptor}
    end
  end

  defp object(_, _, depth, _, limits, _) when depth > limits.depth, do: {:error, :limit_exceeded}
  defp object(<<?}, rest::binary>>, acc, _, nodes, _, false), do: {:ok, acc, rest, nodes}

  defp object(_, acc, _, _, limits, _) when map_size(acc) >= limits.entries,
    do: {:error, :limit_exceeded}

  defp object(<<?", rest::binary>>, acc, depth, nodes, limits, _) do
    with {:ok, key, rest} <- string(rest, [], 0, limits.string),
         false <- Map.has_key?(acc, key),
         <<?:, rest::binary>> <- skip(rest),
         {:ok, value, rest, nodes} <- parse(skip(rest), depth, nodes, limits) do
      acc = Map.put(acc, key, value)

      case skip(rest) do
        <<?,, next::binary>> -> object(skip(next), acc, depth, nodes, limits, true)
        <<?}, next::binary>> -> {:ok, acc, next, nodes}
        _ -> {:error, :invalid_descriptor}
      end
    else
      {:error, code} -> {:error, code}
      _ -> {:error, :invalid_descriptor}
    end
  end

  defp object(_, _, _, _, _, _), do: {:error, :invalid_descriptor}

  defp array(_, _, _, depth, _, limits, _) when depth > limits.depth, do: {:error, :limit_exceeded}

  defp array(<<?], rest::binary>>, acc, _, _, nodes, _, false),
    do: {:ok, Enum.reverse(acc), rest, nodes}

  defp array(_, _, count, _, _, limits, _) when count >= limits.entries,
    do: {:error, :limit_exceeded}

  defp array(input, acc, count, depth, nodes, limits, _) do
    with {:ok, value, rest, nodes} <- parse(input, depth, nodes, limits) do
      case skip(rest) do
        <<?,, next::binary>> ->
          array(skip(next), [value | acc], count + 1, depth, nodes, limits, true)

        <<?], next::binary>> ->
          {:ok, Enum.reverse([value | acc]), next, nodes}

        _ ->
          {:error, :invalid_descriptor}
      end
    end
  end

  defp string(<<?", rest::binary>>, acc, _, _),
    do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp string(<<?\\, ?u, a, b, c, d, rest::binary>>, acc, size, limit) do
    with {:ok, point} <- hex(<<a, b, c, d>>),
         {:ok, point, rest} <- surrogate(point, rest) do
      append_string(<<point::utf8>>, rest, acc, size, limit)
    end
  end

  defp string(<<?\\, escaped, rest::binary>>, acc, size, limit) do
    case escaped do
      ?" -> append_string("\"", rest, acc, size, limit)
      ?\\ -> append_string("\\", rest, acc, size, limit)
      ?/ -> append_string("/", rest, acc, size, limit)
      ?b -> append_string(<<8>>, rest, acc, size, limit)
      ?f -> append_string(<<12>>, rest, acc, size, limit)
      ?n -> append_string("\n", rest, acc, size, limit)
      ?r -> append_string("\r", rest, acc, size, limit)
      ?t -> append_string("\t", rest, acc, size, limit)
      _ -> {:error, :invalid_descriptor}
    end
  end

  defp string(<<point::utf8, rest::binary>>, acc, size, limit) when point >= 0x20 and point != ?\\,
    do: append_string(<<point::utf8>>, rest, acc, size, limit)

  defp string(_, _, _, _), do: {:error, :invalid_descriptor}

  defp append_string(part, rest, acc, size, limit) do
    if size + byte_size(part) <= limit,
      do: string(rest, [part | acc], size + byte_size(part), limit),
      else: {:error, :limit_exceeded}
  end

  defp hex(bytes) do
    if Regex.match?(~r/\A[0-9a-fA-F]{4}\z/, bytes),
      do: {:ok, String.to_integer(bytes, 16)},
      else: {:error, :invalid_descriptor}
  end

  defp surrogate(high, <<?\\, ?u, a, b, c, d, rest::binary>>) when high in 0xD800..0xDBFF do
    case hex(<<a, b, c, d>>) do
      {:ok, low} when low in 0xDC00..0xDFFF ->
        {:ok, 0x10000 + (high - 0xD800) * 1024 + low - 0xDC00, rest}

      _ ->
        {:error, :invalid_descriptor}
    end
  end

  defp surrogate(point, _) when point in 0xD800..0xDFFF, do: {:error, :invalid_descriptor}
  defp surrogate(point, rest), do: {:ok, point, rest}

  defp number(<<byte, rest::binary>>, token) when byte in [?-, ?+, ?., ?e, ?E] or byte in ?0..?9 do
    if byte_size(token) < 18, do: number(rest, <<token::binary, byte>>), else: {token <> "!", rest}
  end

  defp number(rest, token), do: {token, rest}
  defp skip(<<byte, rest::binary>>) when byte in [32, 9, 10, 13], do: skip(rest)
  defp skip(rest), do: rest

  defp emit(_, _, nodes, _, limits) when nodes >= limits.nodes, do: {:error, :limit_exceeded}

  defp emit(value, depth, nodes, bytes, limits) when is_map(value) and not is_struct(value) do
    with :ok <- container(depth, map_size(value), limits),
         true <- Enum.all?(Map.keys(value), &(is_binary(&1) and String.valid?(&1))) do
      pairs =
        Enum.sort_by(value, fn {key, _} ->
          :unicode.characters_to_binary(key, :utf8, {:utf16, :big})
        end)

      emit_object(pairs, [], depth + 1, nodes + 1, bytes + 2, limits)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_descriptor}
    end
  end

  defp emit(value, depth, nodes, bytes, limits) when is_list(value) do
    with :ok <- container(depth, 0, limits) do
      emit_array(value, [], 0, depth + 1, nodes + 1, bytes + 2, limits)
    end
  end

  defp emit(value, _, nodes, bytes, limits) do
    with {:ok, part} <- scalar(value, limits),
         :ok <- size(bytes + IO.iodata_length(part), limits.bytes) do
      {:ok, part, nodes + 1, bytes + IO.iodata_length(part)}
    end
  end

  defp emit_object([], acc, _, nodes, bytes, limits), do: finish(?{, ?}, acc, nodes, bytes, limits)

  defp emit_object([{key, value} | rest], acc, depth, nodes, bytes, limits) do
    with {:ok, key} <- scalar(key, limits),
         bytes = bytes + IO.iodata_length(key) + 1 + if(acc == [], do: 0, else: 1),
         :ok <- size(bytes, limits.bytes),
         {:ok, value, nodes, bytes} <- emit(value, depth, nodes, bytes, limits) do
      emit_object(rest, [[key, ?:, value] | acc], depth, nodes, bytes, limits)
    end
  end

  defp emit_array([], acc, _, _, nodes, bytes, limits),
    do: finish(?[, ?], acc, nodes, bytes, limits)

  defp emit_array([value | rest], acc, count, depth, nodes, bytes, limits)
       when count < limits.entries do
    with {:ok, part, nodes, bytes} <-
           emit(value, depth, nodes, bytes + if(count == 0, do: 0, else: 1), limits) do
      emit_array(rest, [part | acc], count + 1, depth, nodes, bytes, limits)
    end
  end

  defp emit_array(_, _, count, _, _, _, limits) when count >= limits.entries,
    do: {:error, :limit_exceeded}

  defp emit_array(_, _, _, _, _, _, _), do: {:error, :invalid_descriptor}

  defp finish(open, close, acc, nodes, bytes, limits) do
    with :ok <- size(bytes, limits.bytes) do
      {:ok, [open, Enum.intersperse(Enum.reverse(acc), ?,), close], nodes, bytes}
    end
  end

  defp container(depth, entries, limits) do
    if depth + 1 <= limits.depth and entries <= limits.entries,
      do: :ok,
      else: {:error, :limit_exceeded}
  end

  defp size(bytes, max) when bytes <= max, do: :ok
  defp size(_, _), do: {:error, :limit_exceeded}
  defp scalar(nil, _), do: {:ok, "null"}
  defp scalar(true, _), do: {:ok, "true"}
  defp scalar(false, _), do: {:ok, "false"}

  defp scalar(value, _) when is_integer(value) and value >= -@safe and value <= @safe,
    do: {:ok, Integer.to_string(value)}

  defp scalar(value, limits) when is_binary(value) do
    cond do
      byte_size(value) > limits.string -> {:error, :limit_exceeded}
      not String.valid?(value) -> {:error, :invalid_descriptor}
      true -> {:ok, [?", escape(value), ?"]}
    end
  end

  defp scalar(_, _), do: {:error, :invalid_descriptor}

  defp escape(value) do
    for <<point::utf8 <- value>> do
      case point do
        ?" ->
          "\\\""

        ?\\ ->
          "\\\\"

        8 ->
          "\\b"

        9 ->
          "\\t"

        10 ->
          "\\n"

        12 ->
          "\\f"

        13 ->
          "\\r"

        point when point < 32 ->
          ["\\u", String.pad_leading(String.downcase(Integer.to_string(point, 16)), 4, "0")]

        point ->
          <<point::utf8>>
      end
    end
  end
end
