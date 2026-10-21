defmodule Wotex.Lab.Island.Canvas do
  @moduledoc false

  @node_fields ~w(id kind title identity value unit status detail x y)
  @edge_fields ~w(id source target label kind target_handle)
  @limits %{
    "id" => 128,
    "title" => 128,
    "identity" => 256,
    "value" => 128,
    "unit" => 32,
    "status" => 32,
    "detail" => 128
  }

  @doc false
  @spec validate(map()) :: :ok | {:error, :invalid_island_prop}
  def validate(%{"nodes" => nodes, "edges" => edges}) do
    ids = Enum.map(nodes, &field(&1, "id"))
    edge_ids = Enum.map(edges, &field(&1, "id"))

    if unique?(ids) and unique?(edge_ids) and Enum.all?(nodes, &node?/1) and
         Enum.all?(edges, &edge?(&1, ids)),
       do: :ok,
       else: {:error, :invalid_island_prop}
  end

  defp field(value, key) when is_map(value), do: Map.get(value, key)
  defp field(_, _), do: nil
  defp unique?(ids), do: length(ids) == MapSet.size(MapSet.new(ids))

  defp node?(node) when is_map(node) do
    exact?(node, @node_fields) and
      Enum.all?(@limits, fn {key, limit} -> text?(node[key], limit) end) and
      identifier?(node["id"]) and node["kind"] in ~w(thing process entry) and
      coordinate?(node["x"]) and coordinate?(node["y"])
  end

  defp node?(_), do: false

  defp edge?(edge, ids) when is_map(edge) do
    exact?(edge, @edge_fields) and identifier?(edge["id"]) and
      edge["source"] in ids and edge["target"] in ids and
      text?(edge["label"], 128) and edge["kind"] in ~w(input proposal) and
      edge["target_handle"] in ~w(temperature power input)
  end

  defp edge?(_, _), do: false
  defp exact?(value, keys), do: Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp text?(value, max), do: is_binary(value) and String.valid?(value) and byte_size(value) <= max
  defp coordinate?(value), do: is_number(value) and value >= -20_000 and value <= 20_000

  defp identifier?(value),
    do: text?(value, 128) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/, value)
end
