defmodule Wotex.BLE.BlueZ.Frame do
  @moduledoc """
  Parses bounded JSON objects received from the persistent BlueZ bridge.

  This implementation helper decodes ordered object members before building
  maps so duplicate JSON keys cannot disappear during parsing. Input must be
  smaller than 128 KiB, the root must be an object, nesting is limited to eight
  levels, collections to 1024 members and traversal to 4096 nodes. Malformed
  JSON or exceeded bounds return `:error` without partial output.

  Parsing preserves string keys and creates no atoms from peer input. It does
  not validate a protocol envelope, operation or request ID. Those checks
  belong to `Wotex.BLE.BlueZ.Response` and the owning connection.

  ## Examples

      iex> Wotex.BLE.BlueZ.Frame.decode(~s({"version":1,"ok":true}))
      {:ok, %{"version" => 1, "ok" => true}}
      iex> Wotex.BLE.BlueZ.Frame.decode(~s({"id":"1","id":"2"}))
      :error
  """

  @doc false
  @spec decode(term()) :: {:ok, map()} | :error
  def decode(line) when is_binary(line) and byte_size(line) < 131_072 do
    with {:ok, value} <- Jason.decode(line, objects: :ordered_objects),
         {result, _} when is_map(result) <- normalize(value, 1, 4096) do
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

  defp normalize(value, _, budget), do: {value, budget - 1}
end
