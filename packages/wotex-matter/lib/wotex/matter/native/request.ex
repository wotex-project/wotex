defmodule Wotex.Matter.Native.Request do
  @moduledoc """
  Bounds caller terms before native request copying and JSON serialization.

  The walk counts JSON collection depth, collection entries, aggregate nodes
  including keys, and escaped wire bytes. It stops at the IPC limits without
  materializing an encoded document. Integers retain the signed/unsigned 64-bit
  domain. Atom keys and values follow the native API's JSON representation, and
  context tags account for their two-element array representation. Structs,
  improper lists, invalid UTF-8 and colliding atom/string keys are rejected.

  API admission checks the caller's term before sending it to the connection.
  The connection checks its final envelope again, including correlation and
  timeout fields, before encoding. This module enforces representation bounds;
  operation-specific schema validation remains with the owning API and backend.
  """

  alias Wotex.Matter.Error

  @maximum_bytes 131_071
  @maximum_nodes 4096
  @maximum_depth 24
  @maximum_entries 1024

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(value) do
    case walk(value, 0, {@maximum_nodes, @maximum_bytes}) do
      {:ok, {nodes, bytes}} when nodes >= 0 and bytes >= 0 -> :ok
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  @doc false
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(frame) do
    with :ok <- validate(frame),
         {:ok, encoded} <- Jason.encode(frame),
         true <- byte_size(encoded) <= @maximum_bytes do
      {:ok, encoded}
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  defp walk(_, _, {nodes, bytes}) when nodes <= 0 or bytes < 0, do: :error

  defp walk(value, depth, {nodes, bytes}) when is_map(value) and not is_struct(value) do
    count = map_size(value)

    if count <= @maximum_entries and depth < @maximum_depth do
      Enum.reduce_while(value, {:ok, {nodes - 1, bytes - 2 - max(count - 1, 0)}}, fn
        {key, child}, {:ok, budget} ->
          with {:ok, budget} <- key(key, value, budget),
               {:ok, budget} <- walk(child, depth + 1, budget) do
            {:cont, {:ok, budget}}
          else
            _ -> {:halt, :error}
          end
      end)
    else
      :error
    end
  end

  defp walk(value, depth, {nodes, bytes}) when is_list(value) do
    if depth < @maximum_depth,
      do: walk_list(value, depth + 1, {nodes - 1, bytes - 2}, 0),
      else: :error
  end

  defp walk({:context, id}, depth, budget) when is_integer(id) and id in 0..255,
    do: walk(["context", id], depth, budget)

  defp walk(value, _, budget) when is_binary(value), do: string(value, budget)
  defp walk(nil, _, {nodes, bytes}), do: {:ok, {nodes - 1, bytes - 4}}
  defp walk(true, _, {nodes, bytes}), do: {:ok, {nodes - 1, bytes - 4}}
  defp walk(false, _, {nodes, bytes}), do: {:ok, {nodes - 1, bytes - 5}}
  defp walk(value, _, budget) when is_atom(value), do: string(Atom.to_string(value), budget)

  defp walk(value, _, {nodes, bytes})
       when is_integer(value) and value >= -0x8000000000000000 and
              value <= 0xFFFFFFFFFFFFFFFF,
       do: {:ok, {nodes - 1, bytes - byte_size(Integer.to_string(value))}}

  defp walk(value, _, {nodes, bytes}) when is_float(value),
    do: {:ok, {nodes - 1, bytes - byte_size(Float.to_string(value))}}

  defp walk(_, _, _), do: :error

  defp walk_list([], _, budget, _), do: {:ok, budget}

  defp walk_list([child | rest], depth, {nodes, bytes}, count) when count < @maximum_entries do
    separator = if count == 0, do: 0, else: 1

    case walk(child, depth, {nodes, bytes - separator}) do
      {:ok, budget} -> walk_list(rest, depth, budget, count + 1)
      _ -> :error
    end
  end

  defp walk_list(_, _, _, _), do: :error

  defp key(key, map, {nodes, bytes}) when is_atom(key) do
    text = Atom.to_string(key)
    if Map.has_key?(map, text), do: :error, else: string(text, {nodes, bytes - 1})
  end

  defp key(key, _, {nodes, bytes}) when is_binary(key), do: string(key, {nodes, bytes - 1})
  defp key(_, _, _), do: :error

  defp string(value, {nodes, bytes}) do
    if nodes > 0 and byte_size(value) + 2 <= bytes and String.valid?(value) do
      case string_bytes(value, bytes - 2) do
        remaining when remaining >= 0 -> {:ok, {nodes - 1, remaining}}
        _ -> :error
      end
    else
      :error
    end
  end

  defp string_bytes(_, budget) when budget < 0, do: -1
  defp string_bytes(<<>>, budget), do: budget

  defp string_bytes(<<byte, rest::binary>>, budget) do
    size =
      cond do
        byte in [8, 9, 10, 12, 13, 34, 92] -> 2
        byte < 32 -> 6
        true -> 1
      end

    string_bytes(rest, budget - size)
  end
end
