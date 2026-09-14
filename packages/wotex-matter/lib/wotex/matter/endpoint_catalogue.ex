defmodule Wotex.Matter.EndpointCatalogue do
  @moduledoc """
  Represents a bounded, non-atomic projection of Descriptor-cluster reads.

  A catalogue retains the controller fabric and node identity, root endpoint
  zero, and one entry for every endpoint read during discovery. Each Descriptor
  member keeps either its value and DataVersion or its structured per-path
  error. Entries are sorted by endpoint identifier. Construction rejects
  duplicate endpoints, duplicate children, self-reference, cycles, references
  to absent endpoints, and aggregate endpoint or cluster counts outside the
  WMA.11 profile.

  `Wotex.Matter.discover_endpoints/2` performs the P04 native discovery. This
  value itself performs no network I/O and explicitly records that the separate
  Descriptor reads do not form an atomic snapshot.
  """

  alias Wotex.Matter.{Address, Error}

  @enforce_keys [:fabric_id, :node_id, :endpoints]
  defstruct [:fabric_id, :node_id, root_endpoint: 0, endpoints: [], consistency: :not_atomic]

  @type data_version :: non_neg_integer() | nil
  @type device_type :: %{device_type: non_neg_integer(), revision: non_neg_integer()}

  @type descriptor_result(value) ::
          {:ok, %{value: value, data_version: data_version()}} | {:error, Error.t()}

  @type endpoint_entry :: %{
          endpoint: non_neg_integer(),
          device_types: descriptor_result([device_type()]),
          server_clusters: descriptor_result([non_neg_integer()]),
          client_clusters: descriptor_result([non_neg_integer()]),
          parts: descriptor_result([non_neg_integer()])
        }

  @type t :: %__MODULE__{
          fabric_id: pos_integer(),
          node_id: pos_integer(),
          root_endpoint: 0,
          endpoints: [endpoint_entry()],
          consistency: :not_atomic
        }

  @doc "Validates and sorts one finite Descriptor-cluster catalogue."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = catalogue), do: new(Map.from_struct(catalogue))

  def new(%{fabric_id: fabric, node_id: node, endpoints: endpoints} = catalogue)
      when map_size(catalogue) == 3,
      do: build(fabric, node, endpoints)

  def new(
        %{
          fabric_id: fabric,
          node_id: node,
          root_endpoint: 0,
          endpoints: endpoints,
          consistency: :not_atomic
        } = catalogue
      )
      when map_size(catalogue) == 5,
      do: build(fabric, node, endpoints)

  def new(_), do: {:error, Error.new(:invalid_endpoint_catalogue)}

  defp build(fabric, node, endpoints) do
    with {:ok, _} <-
           Address.new(%{fabric_id: fabric, node_id: node, endpoint: 0, cluster: 0, member: 0}),
         {:ok, endpoints} <- normalize_endpoints(endpoints),
         :ok <- validate_graph(endpoints),
         true <- cluster_count(endpoints) <= 1024 do
      {:ok,
       %__MODULE__{
         fabric_id: fabric,
         node_id: node,
         endpoints: Enum.sort_by(endpoints, & &1.endpoint)
       }}
    else
      _ -> {:error, Error.new(:invalid_endpoint_catalogue)}
    end
  end

  defp normalize_endpoints(endpoints) when is_list(endpoints) do
    if length(endpoints) in 1..64 do
      traverse(endpoints, &normalize_endpoint/1, [])
    else
      :error
    end
  end

  defp normalize_endpoints(_), do: :error

  defp normalize_endpoint(
         %{
           endpoint: endpoint,
           device_types: device_types,
           server_clusters: server_clusters,
           client_clusters: client_clusters,
           parts: parts
         } = entry
       )
       when map_size(entry) == 5 do
    with true <- valid_endpoint?(endpoint),
         {:ok, device_types} <- descriptor_result(device_types, :device_types),
         {:ok, server_clusters} <- descriptor_result(server_clusters, :clusters),
         {:ok, client_clusters} <- descriptor_result(client_clusters, :clusters),
         {:ok, parts} <- descriptor_result(parts, :parts) do
      {:ok,
       %{
         endpoint: endpoint,
         device_types: device_types,
         server_clusters: server_clusters,
         client_clusters: client_clusters,
         parts: parts
       }}
    else
      _ -> :error
    end
  end

  defp normalize_endpoint(_), do: :error

  defp descriptor_result({:ok, %{value: values, data_version: version} = result}, kind)
       when map_size(result) == 2 and
              (is_nil(version) or (is_integer(version) and version in 0..0xFFFFFFFF)) do
    with {:ok, values} <- descriptor_values(values, kind) do
      {:ok, {:ok, %{value: values, data_version: version}}}
    end
  end

  defp descriptor_result({:error, %Error{} = error}, _) do
    if valid_error?(error), do: {:ok, {:error, error}}, else: :error
  end

  defp descriptor_result(_, _), do: :error

  defp descriptor_values(values, :device_types) when is_list(values) do
    if length(values) <= 1024, do: traverse(values, &device_type/1, []), else: :error
  end

  defp descriptor_values(values, :clusters) when is_list(values) do
    if length(values) <= 1024, do: traverse(values, &cluster/1, []), else: :error
  end

  defp descriptor_values(values, :parts) when is_list(values) do
    if length(values) <= 64 do
      with {:ok, values} <- traverse(values, &endpoint/1, []),
           true <- length(values) == length(Enum.uniq(values)) do
        {:ok, values}
      else
        _ -> :error
      end
    else
      :error
    end
  end

  defp descriptor_values(_, _), do: :error

  defp device_type(%{device_type: device_type, revision: revision} = value)
       when map_size(value) == 2 and is_integer(device_type) and
              device_type in 0..0xFFFFFFFF and is_integer(revision) and revision in 0..0xFFFF,
       do: {:ok, value}

  defp device_type(_), do: :error

  defp cluster(value) when is_integer(value) do
    if valid_cluster?(value), do: {:ok, value}, else: :error
  end

  defp cluster(_), do: :error

  defp endpoint(value) when is_integer(value) do
    if valid_endpoint?(value), do: {:ok, value}, else: :error
  end

  defp endpoint(_), do: :error

  defp traverse([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | rest], function, acc) do
    case function.(value) do
      {:ok, value} -> traverse(rest, function, [value | acc])
      _ -> :error
    end
  end

  defp validate_graph(endpoints) do
    ids = Enum.map(endpoints, & &1.endpoint)
    graph = Map.new(endpoints, &{&1.endpoint, parts(&1.parts)})

    cond do
      0 not in ids ->
        :error

      length(ids) != length(Enum.uniq(ids)) ->
        :error

      Enum.any?(Map.values(graph), fn children -> Enum.any?(children, &(&1 not in ids)) end) ->
        :error

      Enum.any?(ids, &cycle?(&1, graph, %{})) ->
        :error

      true ->
        :ok
    end
  end

  @spec cycle?(non_neg_integer(), %{non_neg_integer() => [non_neg_integer()]}, map()) ::
          boolean()
  defp cycle?(endpoint, graph, path) do
    if Map.has_key?(path, endpoint) do
      true
    else
      path = Map.put(path, endpoint, true)
      Enum.any?(Map.fetch!(graph, endpoint), &cycle?(&1, graph, path))
    end
  end

  defp parts({:ok, %{value: parts}}), do: parts
  defp parts({:error, %Error{}}), do: []

  defp cluster_count(endpoints) do
    Enum.reduce(endpoints, 0, fn endpoint, count ->
      count + result_length(endpoint.server_clusters) + result_length(endpoint.client_clusters)
    end)
  end

  defp result_length({:ok, %{value: values}}), do: length(values)
  defp result_length({:error, %Error{}}), do: 0

  defp valid_error?(%Error{
         code: code,
         field: field,
         class: class,
         details: details,
         retryable: retryable,
         effect: :none
       }) do
    is_atom(code) and not is_nil(code) and valid_field?(field) and is_map(details) and
      valid_class?(class) and map_size(details) <= 16 and is_boolean(retryable) and
      bounded_details?(details)
  end

  defp valid_error?(_), do: false
  defp valid_field?(nil), do: true
  defp valid_field?(field), do: is_atom(field)

  defp valid_class?(class),
    do: class in [:timeout, :unavailable, :rate_limited, :protocol, :permanent, nil]

  defp bounded_details?(details) do
    if :erlang.external_size(details) <= 4096 do
      case Jason.encode_to_iodata(details) do
        {:ok, encoded} -> IO.iodata_length(encoded) <= 4096
        {:error, _} -> false
      end
    else
      false
    end
  end

  defp valid_endpoint?(endpoint) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: 1, node_id: 1, endpoint: endpoint, cluster: 0, member: 0})
    )
  end

  defp valid_cluster?(cluster) do
    match?(
      {:ok, _},
      Address.new(%{fabric_id: 1, node_id: 1, endpoint: 0, cluster: cluster, member: 0})
    )
  end
end
