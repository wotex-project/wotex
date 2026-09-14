defmodule Wotex.Matter.Standalone do
  @moduledoc false

  alias Wotex.Matter
  alias Wotex.Matter.{Address, AttributeReport, Descriptor, EndpointCatalogue, Error, EventReport}
  alias Wotex.Matter.{PortCall, ReadPath, Session}

  @descriptor_cluster 0x001D
  @descriptor_members [0x0000, 0x0001, 0x0002, 0x0003]

  @doc false
  @spec read_attribute(Session.t(), term(), keyword()) ::
          {:ok, AttributeReport.t()} | {:error, Error.t()}
  def read_attribute(%Session{} = session, address, options) do
    with {:ok, address} <- Address.new(address),
         {:ok, _} <- Descriptor.lookup(:attribute, address, :read),
         {:ok, timeout} <- options(options, session.timeout, [:timeout]),
         {:ok, report} <- Matter.send(%{session | timeout: timeout}, message(:read, address)),
         {:ok, report} <- AttributeReport.new(report) do
      {:ok, report}
    else
      {:error, %Error{}} = error -> error
    end
  end

  def read_attribute(_, _, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec write_attribute(Session.t(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def write_attribute(%Session{} = session, address, value, options) do
    with {:ok, address} <- Address.new(address),
         {:ok, value} <- Descriptor.validate_element(:attribute, address, :write, value),
         {:ok, timeout, request_options} <-
           mutation_options(options, session.timeout, [:expected_data_version]),
         request =
           message(:write, address)
           |> Map.put(:value, value)
           |> Map.merge(request_options),
         {:ok, %{path: path, status: 0} = result} <-
           Matter.send(%{session | timeout: timeout}, request),
         {:ok, ^address} <- Address.new(path) do
      {:ok, result}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def write_attribute(_, _, _, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec invoke_command(Session.t(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def invoke_command(%Session{} = session, address, value, options) do
    with {:ok, address} <- Address.new(address),
         {:ok, value} <- Descriptor.validate_element(:command, address, :invoke, value),
         {:ok, timeout, request_options} <- mutation_options(options, session.timeout, []),
         request =
           message(:invoke, address)
           |> Map.put(:value, value)
           |> Map.merge(request_options),
         {:ok, %{path: path, value: result_value, status: 0} = result} <-
           Matter.send(%{session | timeout: timeout}, request),
         :ok <- invoke_result(path, result_value) do
      {:ok, result}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def invoke_command(_, _, _, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec read_events(Session.t(), list(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def read_events(%Session{} = session, paths, options) do
    with {:ok, paths} <- event_paths(paths),
         {:ok, timeout, minimum} <- event_options(options, session.timeout),
         message = event_message(paths, minimum),
         {:ok, results} <- request(session, message, timeout) do
      normalize_events(paths, results)
    end
  end

  def read_events(_, _, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec discover_endpoints(Session.t(), term(), keyword()) ::
          {:ok, EndpointCatalogue.t()} | {:error, Error.t()}
  def discover_endpoints(%Session{} = session, node, options) do
    with {:ok, fabric, node_id} <- node_identity(node),
         {:ok, timeout, max_endpoints} <- discovery_options(options, session.timeout),
         deadline = System.monotonic_time(:millisecond) + timeout,
         {:ok, root_results} <- read_descriptor(session, fabric, node_id, [0], deadline),
         {:ok, root} <- endpoint_entry(root_results, fabric, node_id, 0),
         {:ok, endpoints} <- discovered_endpoints(root.parts, max_endpoints),
         {:ok, child_results} <-
           read_descriptor(session, fabric, node_id, endpoints -- [0], deadline),
         {:ok, children} <- endpoint_entries(child_results, fabric, node_id, endpoints -- [0]) do
      EndpointCatalogue.new(%{
        fabric_id: fabric,
        node_id: node_id,
        endpoints: [root | children]
      })
    end
  end

  def discover_endpoints(_, _, _), do: {:error, Error.new(:invalid_message)}

  defp request(session, message, timeout) do
    result = PortCall.invoke(session.client, :request, [session.handle, message, timeout])

    case result do
      {:ok, _} = result -> result
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp message(type, address), do: Map.put(Map.from_struct(address), :type, type)

  defp invoke_result(nil, nil), do: :ok

  defp invoke_result(path, value) when path != nil and value != nil do
    with {:ok, address} <- Address.new(path),
         {:ok, _} <- Descriptor.validate_element(:command, address, :invoke, value),
         do: :ok
  end

  defp invoke_result(_, _), do: :error

  defp options(options, default, allowed) when is_list(options) do
    keys = if Keyword.keyword?(options), do: Keyword.keys(options), else: []
    timeout = Keyword.get(options, :timeout, default)

    if length(keys) == length(Enum.uniq(keys)) and keys -- allowed == [] and
         is_integer(timeout) and timeout in 1..60_000,
       do: {:ok, timeout},
       else: {:error, Error.new(:invalid_options)}
  end

  defp options(_, _, _), do: {:error, Error.new(:invalid_options)}

  defp mutation_options(options, default, extra) do
    allowed = [:timeout, :timed_request_timeout_ms | extra]

    with {:ok, timeout} <- options(options, default, allowed),
         :ok <- timed_option(options, timeout),
         :ok <- data_version_option(options, extra) do
      {:ok, timeout, Map.new(Keyword.drop(options, [:timeout]))}
    end
  end

  defp timed_option(options, timeout) do
    case Keyword.fetch(options, :timed_request_timeout_ms) do
      :error -> :ok
      {:ok, value} when is_integer(value) and value in 1..65_535 and value <= timeout -> :ok
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp data_version_option(options, [:expected_data_version]) do
    case Keyword.fetch(options, :expected_data_version) do
      :error -> :ok
      {:ok, value} when is_integer(value) and value in 0..0xFFFFFFFF -> :ok
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp data_version_option(_, []), do: :ok

  defp event_paths(paths) when is_list(paths) and length(paths) in 1..64 do
    traverse(paths, fn path ->
      with {:ok, address} <- Address.new(path),
           {:ok, _} <- Descriptor.lookup(:event, address, :read),
           do: {:ok, address}
    end)
  end

  defp event_paths(_), do: {:error, Error.new(:invalid_path_batch)}

  defp event_options(options, default) do
    with {:ok, timeout} <- options(options, default, [:timeout, :min_event_number]),
         minimum = Keyword.get(options, :min_event_number),
         true <- is_nil(minimum) or (is_integer(minimum) and minimum in 0..0xFFFFFFFFFFFFFFFF) do
      {:ok, timeout, minimum}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp event_message(paths, minimum) do
    message = %{type: :read_events, paths: Enum.map(paths, &Map.from_struct/1)}
    if is_nil(minimum), do: message, else: Map.put(message, :min_event_number, minimum)
  end

  defp normalize_events(paths, results)
       when is_list(results) and length(results) == length(paths) do
    by_path = Map.new(results, fn %{path: path} = result -> {path_key(path), result} end)

    if map_size(by_path) == length(paths) do
      traverse(paths, fn path ->
        case Map.fetch(by_path, path_key(path)) do
          {:ok, result} ->
            normalize_event_result(path, result)

          _ ->
            :error
        end
      end)
    else
      {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp normalize_events(_, _), do: {:error, Error.new(:invalid_transport_return)}

  defp normalize_event_result(path, %{path: raw_path, result: {:ok, report}}) do
    with {:ok, ^path} <- Address.new(raw_path),
         {:ok, report} <- EventReport.new(report),
         true <- report.path == path do
      {:ok, %{path: path, result: {:ok, report}}}
    else
      _ -> :error
    end
  end

  defp normalize_event_result(path, %{path: raw_path, result: {:error, %Error{} = error}}) do
    with {:ok, ^path} <- Address.new(raw_path),
         true <- error.effect == :none do
      {:ok, %{path: path, result: {:error, error}}}
    else
      _ -> :error
    end
  end

  defp normalize_event_result(_, _), do: :error

  defp node_identity(%{fabric_id: fabric, node_id: node} = value) when map_size(value) == 2 do
    case Address.new(%{fabric_id: fabric, node_id: node, endpoint: 0, cluster: 0, member: 0}) do
      {:ok, _} -> {:ok, fabric, node}
      _ -> {:error, Error.new(:invalid_path)}
    end
  end

  defp node_identity(_), do: {:error, Error.new(:invalid_path)}

  defp discovery_options(options, default) do
    with {:ok, timeout} <- options(options, default, [:timeout, :max_endpoints]),
         maximum = Keyword.get(options, :max_endpoints, 64),
         true <- is_integer(maximum) and maximum in 1..64 do
      {:ok, timeout, maximum}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  defp read_descriptor(_, _, _, [], _), do: {:ok, []}

  defp read_descriptor(session, fabric, node, endpoints, deadline) do
    endpoints
    |> Enum.chunk_every(16)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining < 1 do
        {:halt, {:error, Error.new(:timeout)}}
      else
        paths =
          for endpoint <- chunk, member <- @descriptor_members do
            %ReadPath{
              fabric_id: fabric,
              node_id: node,
              endpoint: endpoint,
              cluster: @descriptor_cluster,
              member: member
            }
          end

        case Matter.read_paths(session, paths, timeout: min(remaining, 60_000)) do
          {:ok, results} -> {:cont, {:ok, acc ++ results}}
          {:error, _} = error -> {:halt, error}
        end
      end
    end)
  end

  defp discovered_endpoints({:error, %Error{}}, _), do: {:ok, [0]}

  defp discovered_endpoints({:ok, %{value: parts}}, maximum) do
    cond do
      length(parts) != length(Enum.uniq(parts)) ->
        {:error, Error.new(:invalid_endpoint_catalogue)}

      length(parts) + 1 > maximum ->
        {:error, Error.new(:endpoint_limit)}

      true ->
        {:ok, [0 | parts]}
    end
  end

  defp endpoint_entries(results, fabric, node, endpoints),
    do: traverse(endpoints, &endpoint_entry(results, fabric, node, &1))

  defp endpoint_entry(results, fabric, node, endpoint) do
    with {:ok, device_types} <- descriptor_result(results, fabric, node, endpoint, 0x0000),
         {:ok, servers} <- descriptor_result(results, fabric, node, endpoint, 0x0001),
         {:ok, clients} <- descriptor_result(results, fabric, node, endpoint, 0x0002),
         {:ok, parts} <- descriptor_result(results, fabric, node, endpoint, 0x0003) do
      {:ok,
       %{
         endpoint: endpoint,
         device_types: device_types,
         server_clusters: servers,
         client_clusters: clients,
         parts: parts
       }}
    end
  end

  defp descriptor_result(results, fabric, node, endpoint, member) do
    path = %Address{
      fabric_id: fabric,
      node_id: node,
      endpoint: endpoint,
      cluster: @descriptor_cluster,
      member: member
    }

    case Enum.find(results, &(path_key(&1.path) == path_key(path))) do
      %{result: {:ok, %AttributeReport{} = report}} ->
        with {:ok, value} <- Descriptor.from_element(:attribute, path, :read, report.value) do
          {:ok, {:ok, %{value: value, data_version: report.data_version}}}
        end

      %{result: {:error, %Error{} = error}} ->
        {:ok, {:error, error}}

      _ ->
        {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp path_key(path),
    do: {path.fabric_id, path.node_id, path.endpoint, path.cluster, path.member}

  defp traverse(values, function), do: traverse(values, function, [])
  defp traverse([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | rest], function, acc) do
    case function.(value) do
      {:ok, result} -> traverse(rest, function, [result | acc])
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end
end
