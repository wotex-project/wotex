defmodule Wotex.Lab.Island.Patch do
  @moduledoc false

  @unsafe_segments ~w(__proto__ prototype constructor)
  @index ~r/\A(?:0|[1-9][0-9]*)\z/

  @doc false
  @spec apply(map(), [map()], [String.t()]) :: {:ok, map()} | {:error, term()}
  def apply(payload, operations, allowed) do
    Enum.reduce_while(operations, {:ok, payload}, fn operation, {:ok, current} ->
      with {:ok, op, segments} <- parse(operation, allowed),
           {:ok, next} <- change(current, segments, op, Map.get(operation, "value")) do
        {:cont, {:ok, next}}
      else
        _ -> {:halt, {:error, :invalid_island_patch_operation}}
      end
    end)
  end

  defp parse(%{"op" => op, "path" => "/" <> path} = operation, allowed)
       when op in ["add", "remove", "replace"] do
    keys = if op == "remove", do: ~w(op path), else: ~w(op path value)

    with true <- Enum.sort(Map.keys(operation)) == Enum.sort(keys),
         false <- Regex.match?(~r/~(?:[^01]|$)/, path),
         [field | _] = segments <- Enum.map(String.split(path, "/"), &unescape/1),
         true <- field in allowed,
         false <- Enum.any?(segments, &(&1 in @unsafe_segments)) do
      {:ok, op, segments}
    else
      _ -> :error
    end
  end

  defp parse(_, _), do: :error

  defp unescape(segment) do
    segment
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end

  defp change(parent, [key], op, value) when is_map(parent) do
    if op == "add" or Map.has_key?(parent, key) do
      {:ok, if(op == "remove", do: Map.delete(parent, key), else: Map.put(parent, key, value))}
    else
      :error
    end
  end

  defp change(parent, [key], op, value) when is_list(parent) do
    with {:ok, index} <- index(key, length(parent), op == "add") do
      next =
        case op do
          "add" -> List.insert_at(parent, index, value)
          "remove" -> List.delete_at(parent, index)
          "replace" -> List.replace_at(parent, index, value)
        end

      {:ok, next}
    end
  end

  defp change(parent, [key | rest], op, value) when is_map(parent) do
    with {:ok, child} <- Map.fetch(parent, key),
         {:ok, next} <- change(child, rest, op, value) do
      {:ok, Map.put(parent, key, next)}
    end
  end

  defp change(parent, [key | rest], op, value) when is_list(parent) do
    with {:ok, index} <- index(key, length(parent), false),
         {:ok, next} <- change(Enum.at(parent, index), rest, op, value) do
      {:ok, List.replace_at(parent, index, next)}
    end
  end

  defp change(_, _, _, _), do: :error

  defp index("-", length, true), do: {:ok, length}

  defp index(key, length, append?) do
    if Regex.match?(@index, key) do
      index = String.to_integer(key)
      if index < length or (append? and index == length), do: {:ok, index}, else: :error
    else
      :error
    end
  end
end
