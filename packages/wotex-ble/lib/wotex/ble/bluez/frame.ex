defmodule Wotex.BLE.BlueZ.Frame do
  @moduledoc false

  @doc false
  @spec decode(term()) :: {:ok, map()} | :error
  def decode(line) when is_binary(line) and byte_size(line) < 131_072 do
    with {:ok, value} <- Jason.decode(line, objects: :ordered_objects),
         {result, _remaining} when is_map(result) <- normalize(value, 1, 4096) do
      {:ok, result}
    else
      _ -> :error
    end
  catch
    :throw, :invalid_frame -> :error
  end

  def decode(_), do: :error

  defp normalize(_, depth, budget) when depth > 8 or budget < 1, do: throw(:invalid_frame)

  defp normalize(%Jason.OrderedObject{values: pairs}, depth, budget) do
    if length(pairs) > 1024, do: throw(:invalid_frame)

    Enum.reduce(pairs, {%{}, budget - 1}, fn {key, value}, {map, remaining} ->
      if Map.has_key?(map, key), do: throw(:invalid_frame)
      {value, remaining} = normalize(value, depth + 1, remaining)
      {Map.put(map, key, value), remaining}
    end)
  end

  defp normalize(values, depth, budget) when is_list(values) do
    if length(values) > 1024, do: throw(:invalid_frame)
    Enum.map_reduce(values, budget - 1, &normalize(&1, depth + 1, &2))
  end

  defp normalize(value, _depth, budget), do: {value, budget - 1}
end
