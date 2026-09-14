defmodule Wotex.Matter.Standalone do
  @moduledoc false

  alias Wotex.Matter
  alias Wotex.Matter.{Address, AttributeReport, Descriptor, EndpointCatalogue, Error, EventReport}
  alias Wotex.Matter.OnboardingMaterial
  alias Wotex.Matter.{PortCall, ReadPath, Session, Subscription}

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
         {:ok, report} <- AttributeReport.new(report),
         :ok <- read_result(report, address) do
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
      normalize_events(paths, results, minimum)
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

  @doc false
  @spec subscribe(Session.t(), term()) :: {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(%Session{} = session, request) when is_map(request) do
    with {:ok, request, receiver, timeout} <- subscription_request(request, session.timeout),
         true <- function_exported?(session.client, :subscribe, 4),
         {:ok, %Subscription{} = subscription} <-
           PortCall.invoke(session.client, :subscribe, [session.handle, request, receiver, timeout]) do
      {:ok, subscription}
    else
      false -> {:error, Error.new(:not_supported)}
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def subscribe(_, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec unsubscribe(Session.t(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(%Session{} = session, %Subscription{} = subscription) do
    if function_exported?(session.client, :unsubscribe, 3) do
      PortCall.invoke(session.client, :unsubscribe, [session.handle, subscription, session.timeout])
    else
      {:error, Error.new(:not_supported)}
    end
  end

  def unsubscribe(_, _), do: {:error, Error.new(:invalid_handle)}

  @doc false
  @spec commission_on_network(Session.t(), term()) :: {:ok, map()} | {:error, Error.t()}
  def commission_on_network(%Session{} = session, request) when is_map(request) do
    with {:ok, message, timeout} <- commissioning_request(request),
         {:ok, result} <- request(session, message, timeout),
         {:ok, result} <- commission_result(result, message.node_id) do
      {:ok, result}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def commission_on_network(_, _), do: {:error, Error.new(:invalid_commissioning_request)}

  @doc false
  @spec open_commissioning_window(Session.t(), term()) ::
          {:ok, OnboardingMaterial.t()} | {:error, Error.t()}
  def open_commissioning_window(%Session{} = session, request) when is_map(request) do
    with {:ok, message} <- window_request(request),
         {:ok, result} <- request(session, message, session.timeout),
         {:ok, material} <- onboarding_material(result, message) do
      {:ok, material}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def open_commissioning_window(_, _),
    do: {:error, Error.new(:invalid_commissioning_window)}

  defp request(session, message, timeout) do
    result = PortCall.invoke(session.client, :request, [session.handle, message, timeout])

    case result do
      {:ok, _} = result -> result
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp commissioning_request(request) do
    with true <- exact_atom_keys?(request, [:node_id, :setup_pin, :discriminator, :timeout]),
         node when is_integer(node) and node in 1..0xFFFFFFEFFFFFFFFF <- request.node_id,
         pin when is_integer(pin) <- request.setup_pin,
         true <- valid_setup_pin?(pin),
         discriminator when is_integer(discriminator) and discriminator in 0..4095 <-
           request.discriminator,
         timeout when is_integer(timeout) and timeout in 1..60_000 <- request.timeout do
      {:ok,
       %{
         type: :commission_on_network,
         node_id: node,
         setup_pin: pin,
         discriminator: discriminator
       }, timeout}
    else
      _ -> {:error, Error.new(:invalid_commissioning_request)}
    end
  end

  defp window_request(request) do
    with true <-
           exact_atom_keys?(request, [:node_id, :timeout_s, :iteration_count, :discriminator]),
         node when is_integer(node) and node in 1..0xFFFFFFEFFFFFFFFF <- request.node_id,
         timeout when is_integer(timeout) and timeout in 180..900 <- request.timeout_s,
         iterations when is_integer(iterations) and iterations in 1_000..100_000 <-
           request.iteration_count,
         discriminator when is_integer(discriminator) and discriminator in 0..4095 <-
           request.discriminator do
      {:ok,
       %{
         type: :open_window,
         node_id: node,
         timeout_s: timeout,
         iteration_count: iterations,
         discriminator: discriminator
       }}
    else
      _ -> {:error, Error.new(:invalid_commissioning_window)}
    end
  end

  defp commission_result(
         %{node_id: node, fabric_id: fabric, case: :established} = result,
         node
       )
       when map_size(result) == 3 and is_integer(fabric) and fabric > 0,
       do: {:ok, result}

  defp commission_result(_, _), do: :error

  defp onboarding_material(
         %{
           node_id: node,
           setup_pin: pin,
           discriminator: discriminator,
           manual_code: manual,
           qr_code: qr,
           expires_in_s: expiry
         } = result,
         %{node_id: node, discriminator: discriminator, timeout_s: expiry}
       )
       when map_size(result) == 6 and is_binary(manual) and byte_size(manual) in 10..21 and
              is_binary(qr) and byte_size(qr) in 4..512 and is_integer(pin) do
    if valid_setup_pin?(pin) and String.starts_with?(qr, "MT:") do
      {:ok, struct!(OnboardingMaterial, result)}
    else
      :error
    end
  end

  defp onboarding_material(_, _), do: :error

  defp valid_setup_pin?(pin) do
    pin in 1..99_999_998 and pin not in [12_345_678, 87_654_321] and
      not repeated_digit?(pin)
  end

  defp repeated_digit?(pin) do
    pin
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
    |> String.codepoints()
    |> Enum.uniq()
    |> length() == 1
  end

  defp exact_atom_keys?(value, keys),
    do: Enum.all?(Map.keys(value), &is_atom/1) and Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp subscription_request(request, default_timeout) do
    allowed = [
      :kind,
      :paths,
      :receiver,
      :min_interval_s,
      :max_interval_s,
      :resubscribe,
      :max_queue_length,
      :timeout
    ]

    keys = Map.keys(request)
    receiver = Map.get(request, :receiver, self())
    minimum = Map.get(request, :min_interval_s, 1)
    maximum = Map.get(request, :max_interval_s, 60)
    resubscribe = Map.get(request, :resubscribe, false)
    queue_limit = Map.get(request, :max_queue_length, 1_000)
    timeout = Map.get(request, :timeout, default_timeout)

    with true <- Enum.all?(keys, &is_atom/1) and keys -- allowed == [],
         kind when kind in [:attribute, :event] <- Map.get(request, :kind),
         true <- is_pid(receiver) and Process.alive?(receiver),
         true <- is_integer(minimum) and minimum in 0..65_535,
         true <- is_integer(maximum) and maximum in 1..65_535 and minimum <= maximum,
         true <- is_boolean(resubscribe),
         true <- is_integer(queue_limit) and queue_limit in 1..10_000,
         true <- is_integer(timeout) and timeout in 1..60_000,
         {:ok, paths} <- subscription_paths(kind, Map.get(request, :paths)) do
      native = %{
        kind: kind,
        paths: Enum.map(paths, &Map.from_struct/1),
        min_interval_s: minimum,
        max_interval_s: maximum,
        resubscribe: resubscribe,
        queue_limit: queue_limit
      }

      {:ok, native, receiver, timeout}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

  defp subscription_paths(kind, paths) when is_list(paths) and length(paths) in 1..64 do
    with {:ok, addresses} <-
           traverse(paths, fn path ->
             with {:ok, address} <- Address.new(path),
                  {:ok, _} <- Descriptor.lookup(kind, address, :subscribe),
                  do: {:ok, address}
           end),
         true <- length(addresses) == length(Enum.uniq(addresses)) do
      {:ok, addresses}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_path_batch)}
    end
  end

  defp subscription_paths(_, _), do: {:error, Error.new(:invalid_path_batch)}

  defp message(type, address), do: Map.put(Map.from_struct(address), :type, type)

  defp read_result(%AttributeReport{path: path, value: value}, address) do
    with true <- path == address,
         {:ok, _} <- Descriptor.validate_element(:attribute, address, :read, value) do
      :ok
    else
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp invoke_result(nil, nil), do: :ok

  defp invoke_result(path, value) when path != nil and value != nil do
    with {:ok, address} <- Address.new(path),
         {:ok, _} <- Descriptor.validate_element(:command, address, :invoke, value),
         do: :ok
  end

  defp invoke_result(_, _), do: :error

  defp options(options, default, allowed) when is_list(options) do
    with true <- Keyword.keyword?(options),
         keys = Keyword.keys(options),
         true <- length(keys) == length(Enum.uniq(keys)) and keys -- allowed == [],
         timeout = Keyword.get(options, :timeout, default),
         true <- is_integer(timeout) and timeout in 1..60_000 do
      {:ok, timeout}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
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
    with {:ok, paths} <-
           traverse(paths, fn path ->
             with {:ok, address} <- Address.new(path),
                  {:ok, _} <- Descriptor.lookup(:event, address, :read),
                  do: {:ok, address}
           end),
         true <- length(Enum.uniq(paths)) == length(paths) do
      {:ok, paths}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_path_batch)}
    end
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

  defp normalize_events(paths, results, minimum)
       when is_list(results) and length(results) <= 1024 do
    allowed = MapSet.new(paths, &path_key/1)

    with {:ok, results} <- traverse(results, &event_entry(&1, allowed)),
         true <- unique_event_numbers?(results),
         groups = Enum.group_by(results, &path_key(&1.path)),
         {:ok, ordered} <-
           traverse(paths, fn path ->
             event_group(Map.get(groups, path_key(path), []), minimum)
           end) do
      {:ok, List.flatten(ordered)}
    else
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp normalize_events(_, _, _), do: {:error, Error.new(:invalid_transport_return)}

  defp event_entry(%{path: raw_path, result: _} = result, allowed) when map_size(result) == 2 do
    with {:ok, path} <- Address.new(raw_path),
         true <- MapSet.member?(allowed, path_key(path)),
         do: normalize_event_result(path, result)
  end

  defp event_entry(_, _), do: :error

  defp unique_event_numbers?(results) do
    identities =
      for %{result: {:ok, report}} <- results,
          do: {report.path.fabric_id, report.path.node_id, report.event_number}

    length(identities) == length(Enum.uniq(identities))
  end

  defp event_group([%{result: {:error, %Error{}}}] = results, _), do: {:ok, results}

  defp event_group(results, minimum) do
    if Enum.all?(results, fn
         %{result: {:ok, report}} -> is_nil(minimum) or report.event_number >= minimum
         _ -> false
       end) do
      {:ok, Enum.sort_by(results, fn %{result: {:ok, report}} -> report.event_number end)}
    else
      :error
    end
  end

  defp normalize_event_result(path, %{path: raw_path, result: {:ok, report}}) do
    with {:ok, ^path} <- Address.new(raw_path),
         {:ok, report} <- EventReport.new(report),
         {:ok, _} <- Descriptor.validate_element(:event, path, :read, report.value),
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
