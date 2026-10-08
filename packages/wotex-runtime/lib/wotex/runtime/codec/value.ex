defmodule Wotex.Runtime.Codec.Value do
  @moduledoc """
  Bounded inert codec trees with exact integers and normalized decimals.

  Object entries use UTF-8 byte order. JSON object properties use RFC 8785
  UTF-16 order during encoding. Values carry no transport or Action authority.
  """
  alias Wotex.Runtime.Implementation.{Error, Grammar, JSON}

  @type t :: map()
  @wire %{bytes: 65_536, depth: 24, nodes: 4096, entries: 256, string: 5464}

  @doc "Revalidates the closed algebra, depth, node count and encoded output size."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(value) do
    with {:ok, _} <- visit(value, 1, 0),
         {:ok, _} <- canonical(value) do
      {:ok, value}
    else
      {:error, %Error{}} = error -> error
      {:error, code} when code in [:output_limit, :unsupported_value] -> failure(code)
      _ -> failure(:unsupported_value)
    end
  end

  @doc "Returns bounded RFC 8785 canonical bytes after validating the typed tree."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, value} <- validate(value) do
      canonical(value)
    end
  end

  defp visit(_, depth, count) when depth > 8 or count >= 1024, do: {:error, :output_limit}

  defp visit(value, depth, count) when is_map(value) and not is_struct(value) do
    case value do
      %{"type" => "null"} ->
        scalar(value, ["type"], true, count)

      %{"type" => "boolean", "value" => v} ->
        scalar(value, ~w(type value), is_boolean(v), count)

      %{"type" => "text", "value" => v} ->
        text(value, v, count)

      %{"type" => "bytes", "base64" => v} ->
        bytes(value, v, count)

      %{"type" => "sint", "value" => v} ->
        scalar(
          value,
          ~w(type value),
          integer?(v, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807),
          count
        )

      %{"type" => "uint", "value" => v} ->
        scalar(value, ~w(type value), integer?(v, 0, 18_446_744_073_709_551_615), count)

      %{"type" => "decimal", "coefficient" => c, "exponent" => e} ->
        scalar(value, ~w(type coefficient exponent), decimal?(c, e), count)

      %{"type" => "list", "items" => items} ->
        collection(value, ~w(type items), items, depth, count, :list)

      %{"type" => "object", "entries" => entries} ->
        collection(value, ~w(type entries), entries, depth, count, :object)

      _ ->
        {:error, :unsupported_value}
    end
  end

  defp visit(_, _, _), do: {:error, :unsupported_value}

  defp scalar(value, keys, valid, count) do
    if valid and Grammar.closed?(value, keys),
      do: {:ok, count + 1},
      else: {:error, :unsupported_value}
  end

  defp text(_, v, _) when is_binary(v) and byte_size(v) > 4096, do: {:error, :output_limit}

  defp text(value, v, count),
    do: scalar(value, ~w(type value), is_binary(v) and String.valid?(v), count)

  defp bytes(_, v, _) when is_binary(v) and byte_size(v) > 5464, do: {:error, :output_limit}

  defp bytes(value, v, count) when is_binary(v) do
    with true <- Grammar.closed?(value, ~w(type base64)),
         {:ok, decoded} <- Base.decode64(v),
         true <- Base.encode64(decoded) == v do
      if byte_size(decoded) <= 4096, do: {:ok, count + 1}, else: {:error, :output_limit}
    else
      _ -> {:error, :unsupported_value}
    end
  end

  defp bytes(_, _, _), do: {:error, :unsupported_value}

  defp integer?(v, minimum, maximum) when is_binary(v) and byte_size(v) in 1..20 do
    case Integer.parse(v) do
      {number, ""} -> number >= minimum and number <= maximum and Integer.to_string(number) == v
      _ -> false
    end
  end

  defp integer?(_, _, _), do: false

  defp decimal?(c, e) do
    integer?(c, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807) and
      is_integer(e) and e >= -32_768 and e <= 32_767 and
      if(c == "0", do: e == 0, else: not String.ends_with?(c, "0"))
  end

  defp collection(value, keys, items, depth, count, kind) do
    if Grammar.closed?(value, keys) do
      members(items, depth + 1, count + 1, 0, kind, nil)
    else
      {:error, :unsupported_value}
    end
  end

  defp members([], _, count, _, _, _), do: {:ok, count}
  defp members([_ | _], _, _, size, _, _) when size >= 256, do: {:error, :output_limit}

  defp members([item | rest], depth, count, size, kind, previous) do
    with {:ok, child, key} <- member(item, kind, previous),
         {:ok, count} <- visit(child, depth, count) do
      members(rest, depth, count, size + 1, kind, key)
    end
  end

  defp members(_, _, _, _, _, _), do: {:error, :unsupported_value}
  defp member(item, :list, _), do: {:ok, item, nil}

  defp member(%{"key" => key, "value" => value} = entry, :object, previous) do
    if Grammar.closed?(entry, ~w(key value)) and is_binary(key) and
         byte_size(key) in 1..128 and String.valid?(key) and (is_nil(previous) or key > previous),
       do: {:ok, value, key},
       else: {:error, :unsupported_value}
  end

  defp member(_, _, _), do: {:error, :unsupported_value}
  defp failure(code), do: {:error, Error.new(code, :output, %{field: :value})}

  defp canonical(value) do
    case JSON.encode(value, @wire) do
      {:ok, _} = success -> success
      {:error, :limit_exceeded} -> failure(:output_limit)
      _ -> failure(:unsupported_value)
    end
  end
end
