defmodule Wotex.Matter.Bench.Topology do
  @moduledoc false

  # Descriptor-cluster data of a synthetic bridge: root endpoint 0, an
  # aggregator on endpoint 1 and bridged On/Off Lights on the remaining
  # endpoints. Batches follow `Wotex.Matter.discover_endpoints/3`: the root
  # endpoint first, then the parts in chunks of 16 endpoints.

  alias Wotex.Matter.{Descriptor, ReadPath}

  @fabric 1
  @node 0x1234
  @descriptor 0x001D
  @members [0x0000, 0x0001, 0x0002, 0x0003]

  @spec sizes() :: %{String.t() => pos_integer()}
  def sizes, do: %{"4 endpoints" => 4, "16 endpoints" => 16, "32 endpoints" => 32}

  @spec node_identity() :: %{fabric_id: pos_integer(), node_id: pos_integer()}
  def node_identity, do: %{fabric_id: @fabric, node_id: @node}

  @spec input(pos_integer()) :: map()
  def input(count) do
    endpoints = Map.new(0..(count - 1), &{&1, endpoint(&1, count)})
    descriptors = descriptors(endpoints)

    batches =
      [[0] | Enum.chunk_every(Enum.to_list(1..(count - 1)), 16)]
      |> Enum.with_index(1)
      |> Enum.map(fn {chunk, id} -> batch(chunk, id, descriptors) end)

    %{
      descriptors: descriptors,
      batches: batches,
      catalogue: %{
        fabric_id: @fabric,
        node_id: @node,
        endpoints: Enum.map(0..(count - 1), &catalogue_entry(Map.fetch!(endpoints, &1)))
      }
    }
  end

  defp endpoint(0, count) do
    %{
      endpoint: 0,
      device_types: [%{device_type: 0x0016, revision: 3}],
      server_clusters: [0x001D, 0x001F, 0x0028, 0x0030, 0x0031, 0x003C, 0x003E],
      client_clusters: [],
      parts: Enum.to_list(1..(count - 1))
    }
  end

  defp endpoint(1, count) do
    %{
      endpoint: 1,
      device_types: [%{device_type: 0x000E, revision: 2}],
      server_clusters: [0x0003, 0x001D],
      client_clusters: [],
      parts: Enum.to_list(2..(count - 1)//1)
    }
  end

  defp endpoint(endpoint, _) do
    %{
      endpoint: endpoint,
      device_types: [
        %{device_type: 0x0100, revision: 3},
        %{device_type: 0x0013, revision: 3}
      ],
      server_clusters: [0x0003, 0x0004, 0x0006, 0x001D, 0x0039],
      client_clusters: [],
      parts: []
    }
  end

  defp member_value(entry, 0x0000), do: entry.device_types
  defp member_value(entry, 0x0001), do: entry.server_clusters
  defp member_value(entry, 0x0002), do: entry.client_clusters
  defp member_value(entry, 0x0003), do: entry.parts

  defp descriptors(endpoints) do
    for {endpoint, entry} <- endpoints, member <- @members, into: %{} do
      path = path(endpoint, member)
      {:ok, element} = Descriptor.to_element(:attribute, path, :read, member_value(entry, member))

      {{endpoint, member},
       %{path: path, result: {:ok, %{path: path, value: element, data_version: 100 + endpoint}}}}
    end
  end

  defp batch(chunk, id, descriptors) do
    results = for endpoint <- chunk, member <- @members, do: descriptors[{endpoint, member}]

    requested =
      for endpoint <- chunk, member <- @members do
        {:ok, path} = ReadPath.new(path(endpoint, member))
        path
      end

    %{requested: requested, results: results, frame: frame(id, results)}
  end

  defp frame(id, results) do
    frame = %{
      "version" => 1,
      "id" => Integer.to_string(id),
      "ok" => true,
      "result" => Enum.map(results, &result_json/1)
    }

    {:ok, json} = Wotex.JSON.encode(frame)
    json
  end

  defp result_json(%{path: path, result: {:ok, report}}) do
    %{
      "path" => path_json(path),
      "result" => %{
        "ok" => %{
          "path" => path_json(report.path),
          "value" => element_json(report.value),
          "data_version" => report.data_version
        }
      }
    }
  end

  defp path_json(path), do: Map.new(path, fn {key, value} -> {Atom.to_string(key), value} end)

  defp element_json(%{tag: tag, type: type, value: value}) do
    %{
      "tag" => tag_json(tag),
      "type" => Atom.to_string(type),
      "value" => if(type in [:structure, :array], do: Enum.map(value, &element_json/1), else: value)
    }
  end

  defp tag_json(:anonymous), do: "anonymous"
  defp tag_json({:context, id}), do: ["context", id]

  defp catalogue_entry(entry) do
    version = 100 + entry.endpoint

    %{
      endpoint: entry.endpoint,
      device_types: {:ok, %{value: entry.device_types, data_version: version}},
      server_clusters: {:ok, %{value: entry.server_clusters, data_version: version}},
      client_clusters: {:ok, %{value: entry.client_clusters, data_version: version}},
      parts: {:ok, %{value: entry.parts, data_version: version}}
    }
  end

  defp path(endpoint, member) do
    %{fabric_id: @fabric, node_id: @node, endpoint: endpoint, cluster: @descriptor, member: member}
  end
end
