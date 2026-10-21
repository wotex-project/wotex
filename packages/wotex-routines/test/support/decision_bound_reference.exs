defmodule Wotex.Routines.Test.DecisionBoundReference do
  @moduledoc false

  # A generic native-JSON measurement and canonical writer. No Wotex JSON,
  # Validation, compiler, execution or decision helper participates in it.
  @spec measure(term()) :: map()
  def measure(data) do
    data
    |> tree(0)
    |> Map.put("max_bytes", IO.iodata_length(canonical(data)))
  end

  @spec digest(map(), String.t()) :: map()
  def digest(data, key) do
    bytes =
      data
      |> Map.delete(key)
      |> canonical()
      |> IO.iodata_to_binary()

    hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    Map.put(data, key, "sha256:" <> hash)
  end

  @spec canonical(term()) :: iodata()
  def canonical(data) when is_map(data) do
    entries =
      data
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, value} -> [JSON.encode!(key), ":", canonical(value)] end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  def canonical(data) when is_list(data),
    do: ["[", Enum.intersperse(Enum.map(data, &canonical/1), ","), "]"]

  def canonical(data), do: JSON.encode!(data)

  defp tree(data, depth) do
    {values, keys, size} =
      cond do
        is_map(data) -> {Map.values(data), Map.keys(data), map_size(data)}
        is_list(data) -> {data, [], length(data)}
        true -> {[], [], 0}
      end

    nested = Enum.map(values, &tree(&1, depth + 1))
    strings = if is_binary(data), do: [data | keys], else: keys
    string_size = Enum.max([0 | Enum.map(strings, &byte_size/1)])
    container_depth = if is_map(data) or is_list(data), do: depth + 1, else: depth

    %{
      "max_nodes" => 1 + Enum.sum(Enum.map(nested, & &1["max_nodes"])),
      "max_depth" => Enum.max([container_depth | Enum.map(nested, & &1["max_depth"])]),
      "max_string_bytes" => Enum.max([string_size | Enum.map(nested, & &1["max_string_bytes"])]),
      "max_collection_size" => Enum.max([size | Enum.map(nested, & &1["max_collection_size"])])
    }
  end
end
