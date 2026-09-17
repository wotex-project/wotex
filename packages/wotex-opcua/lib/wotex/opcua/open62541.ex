defmodule Wotex.OPCUA.Open62541 do
  @moduledoc """
  Runs explicit OPC UA operations through the owned open62541 C executable.

  `connect/1` validates the WOP.13 native configuration. Persistent mode opens
  one secure Session and binds its temporary native host to the calling process.
  Any process may send Read, Write and Call through a persistent handle; the
  host admits at most 64 outstanding requests and monitors each caller. Browse
  and disconnect remain owner-only because they own continuation and Session
  cleanup.
  One-shot mode defers credential reads and process startup until `request/3`.
  This client projects Value Read, typed Write and Method Call results as
  validated native maps and complete, bounded child Browse pages as canonical
  NodeIds. One-shot Read, Write and Call preserve the existing adapter's result
  shapes. Persistent typed pagination and bounded child-list pagination use the
  same native Session; subscriptions and other compatibility cells remain
  separate work. No operation invokes Python or retries a
  transmitted mutation.
  """

  @behaviour Wotex.OPCUA.Client

  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Native.{Config, Host}

  @types ~w(Boolean SByte Byte Int16 UInt16 Int32 UInt32 Int64 UInt64 Float Double String DateTime Guid ByteString NodeId ExpandedNodeId StatusCode QualifiedName LocalizedText ExtensionObject)

  @impl Wotex.OPCUA.Client
  @doc "Validates native options and opens a caller-owned persistent Session when requested."
  def connect(options) do
    with {:ok, config} <- Config.new(options) do
      case config.lifecycle do
        :persistent -> persistent_connect(config)
        :oneshot -> {:ok, %{owner: self(), config: config, host: nil}}
      end
    end
  end

  @impl Wotex.OPCUA.Client
  @doc "Runs one validated native service request within the supplied timeout."
  def request(%{owner: owner, config: %Config{} = config, host: host} = handle, message, timeout)
      when is_pid(owner) and is_integer(timeout) and timeout in 1..60_000 do
    with {:ok, operation, parameters} <- service(message),
         :ok <- caller(owner, operation) do
      case config.lifecycle do
        :persistent when is_pid(host) ->
          persistent_request(host, operation, parameters, handle.namespace_array, timeout)

        :oneshot when is_nil(host) ->
          oneshot_request(config, operation, parameters, timeout)

        _ ->
          {:error, Error.new(:invalid_native_handle)}
      end
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_native_handle)}

  defp caller(owner, "browse") when owner != self(), do: {:error, Error.new(:invalid_native_handle)}
  defp caller(_, _), do: :ok

  defp persistent_request(host, "browse", parameters, namespaces, timeout),
    do:
      browse_children(
        host,
        parameters,
        namespaces,
        System.monotonic_time(:millisecond) + timeout
      )

  defp persistent_request(host, operation, parameters, namespaces, timeout) do
    with {:ok, result} <- Host.request(host, operation, parameters, timeout),
         do: project_result(operation, result, namespaces)
  end

  @impl Wotex.OPCUA.Client
  @doc "Closes an owned persistent Session; repeated cleanup is safe."
  def disconnect(%{owner: owner, config: %Config{lifecycle: :persistent} = config, host: host})
      when owner == self() and is_pid(host) do
    result =
      if Process.alive?(host),
        do: Host.request(host, "close", %{}, config.timeout),
        else: {:ok, nil}

    stop_host(host)

    case result do
      {:ok, nil} -> :ok
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:cleanup_failed)}
    end
  end

  def disconnect(%{owner: owner, config: %Config{lifecycle: :oneshot}, host: nil})
      when owner == self(), do: :ok

  def disconnect(_), do: {:error, Error.new(:invalid_native_handle)}

  defp persistent_connect(config) do
    deadline = System.monotonic_time(:millisecond) + config.timeout

    with {:ok, parameters} <- Config.open_parameters(config, deadline),
         {:ok, host, _} <- start_host(config, deadline) do
      case request_before(host, "open", parameters, deadline) do
        {:ok, %{"namespace_array" => namespaces}} ->
          {:ok, %{owner: self(), config: config, host: host, namespace_array: namespaces}}

        {:error, _} = error ->
          stop_host(host)
          error
      end
    end
  end

  defp oneshot_request(config, operation, parameters, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, open} <- Config.open_parameters(config, deadline),
         {:ok, host, _} <- start_host(config, deadline) do
      try do
        with {:ok, %{"namespace_array" => namespaces}} <-
               request_before(host, "open", open, deadline),
             {:ok, projected} <-
               request_project_before(host, operation, parameters, namespaces, deadline),
             {:ok, nil} <- Host.request(host, "close", %{}, min(config.timeout, 5000)),
             :ok <- ensure_deadline(deadline) do
          oneshot_result(operation, projected)
        end
      after
        stop_host(host)
      end
    end
  end

  defp start_host(config, deadline) do
    timeout = remaining(deadline)

    if timeout > 0 do
      Host.start_link(
        executable: config.executable,
        executable_digest: config.executable_digest,
        guardian: config.guardian,
        guardian_digest: config.guardian_digest,
        timeout: timeout
      )
    else
      {:error, Error.new(:deadline_exceeded, :deadline)}
    end
  end

  defp remaining(deadline),
    do: max(0, min(60_000, deadline - System.monotonic_time(:millisecond)))

  defp ensure_deadline(deadline) do
    if remaining(deadline) > 0,
      do: :ok,
      else: {:error, Error.new(:deadline_exceeded, :deadline)}
  end

  defp request_before(host, operation, parameters, deadline) do
    case remaining(deadline) do
      0 -> {:error, Error.new(:deadline_exceeded, :deadline)}
      timeout -> Host.request(host, operation, parameters, timeout)
    end
  end

  defp request_project_before(host, "browse", parameters, namespaces, deadline),
    do: browse_children(host, parameters, namespaces, deadline)

  defp request_project_before(host, operation, parameters, namespaces, deadline) do
    with {:ok, result} <- request_before(host, operation, parameters, deadline),
         do: project_result(operation, result, namespaces)
  end

  defp browse_children(host, parameters, namespaces, deadline) do
    case remaining(deadline) do
      0 ->
        {:error, Error.new(:deadline_exceeded, :deadline)}

      timeout ->
        with {:ok, page} <-
               Host.browse_page(host, parameters, %{max_pages: 64, max_references: 256}, timeout) do
          collect_children(host, page, namespaces, deadline, [])
        end
    end
  end

  defp collect_children(
         host,
         %{"status" => status, "continuation" => continuation} = page,
         namespaces,
         deadline,
         prior
       ) do
    result =
      if Bitwise.band(status, 0xC000_0000) == 0,
        do: project_result("browse", %{page | "continuation" => nil}, namespaces),
        else: {:error, Error.new(:incomplete_browse)}

    case result do
      {:ok, nodes} ->
        children = prior ++ nodes
        budget = remaining(deadline)

        cond do
          is_nil(continuation) ->
            {:ok, children}

          budget == 0 ->
            release_child_cursor(host, continuation)
            {:error, Error.new(:deadline_exceeded, :deadline)}

          true ->
            with {:ok, following} <- Host.browse_next(host, continuation, budget) do
              collect_children(host, following, namespaces, deadline, children)
            end
        end

      {:error, _} = error ->
        release_child_cursor(host, continuation)
        error
    end
  end

  defp release_child_cursor(_, nil), do: :ok
  defp release_child_cursor(host, continuation), do: Host.browse_release(host, continuation, 1000)

  defp stop_host(host) do
    if Process.alive?(host) do
      GenServer.stop(host, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end

  defp service(%{type: :read, node_id: node} = message) when map_size(message) in 2..3 do
    if Map.get(message, :index_range) == nil and
         Enum.all?(Map.keys(message), &(&1 in [:type, :node_id, :index_range])) do
      with {:ok, id} <- node_id(node) do
        {:ok, "read", %{"node_id" => id, "index_range" => nil}}
      end
    else
      invalid_request()
    end
  end

  defp service(%{type: :write, node_id: node, value: value} = message)
       when map_size(message) in 3..4 do
    if Map.get(message, :index_range) == nil and
         Enum.all?(Map.keys(message), &(&1 in [:type, :node_id, :index_range, :value])) do
      with {:ok, id} <- node_id(node), {:ok, variant} <- variant(value) do
        {:ok, "write", %{"node_id" => id, "index_range" => nil, "value" => variant}}
      end
    else
      invalid_request()
    end
  end

  defp service(
         %{type: :call, node_id: method, value: %{object_id: object, arguments: arguments}} =
           message
       )
       when map_size(message) == 3 and is_list(arguments) and length(arguments) <= 64 do
    with true <- map_size(message.value) == 2,
         {:ok, object_id} <- node_id(object),
         {:ok, method_id} <- node_id(method),
         {:ok, inputs} <- arguments(arguments, []) do
      {:ok, "call", %{"object_id" => object_id, "method_id" => method_id, "arguments" => inputs}}
    else
      _ -> invalid_request()
    end
  end

  defp service(%{type: :browse, node_id: node} = message) when map_size(message) == 2 do
    with {:ok, id} <- node_id(node) do
      {:ok, "browse",
       %{
         "node_id" => id,
         "reference_type_id" => "ns=0;i=33",
         "direction" => "forward",
         "include_subtypes" => true,
         "node_class_mask" => 0,
         "page_size" => 256
       }}
    end
  end

  defp service(%{type: type}) when type in [:browse_next, :browse_release],
    do: {:error, Error.new(:unsupported_protocol)}

  defp service(_), do: invalid_request()

  defp node_id(value) do
    with {:ok, node} <- Address.new(value) do
      {:ok, Address.to_string(node)}
    end
  end

  defp arguments([], values), do: {:ok, Enum.reverse(values)}

  defp arguments([value | rest], values) do
    with {:ok, encoded} <- variant(value) do
      arguments(rest, [encoded | values])
    end
  end

  defp variant(value) when is_map(value) do
    atom_keys =
      for {key, item} <- value, into: %{} do
        {case key do
           "type" -> :type
           "array" -> :array
           "value" -> :value
           "dimensions" -> :dimensions
           other -> other
         end, item}
      end

    typed = Map.put_new(atom_keys, :array, false)

    with true <- map_size(atom_keys) == map_size(value),
         true <- typed[:type] in @types,
         {:ok, _} <- Binary.encode_variant(typed) do
      {:ok,
       typed
       |> Map.new(fn {key, item} -> {Atom.to_string(key), item} end)
       |> native_bytes()}
    else
      _ -> invalid_request()
    end
  end

  defp variant(_), do: invalid_request()

  # Projects a Binary-validated Variant payload onto the closed native JSON shape.
  defp native_bytes(%{"array" => true, "value" => values, "type" => type} = value)
       when is_list(values),
       do: %{value | "value" => Enum.map(values, &native_element(type, &1))}

  defp native_bytes(%{"array" => false, "type" => type, "value" => element} = value),
    do: %{value | "value" => native_element(type, element)}

  defp native_bytes(value), do: value

  defp native_element(_, nil), do: nil

  defp native_element("ByteString", bytes),
    do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}

  defp native_element("NodeId", node), do: canonical_node(node)

  defp native_element("ExpandedNodeId", %{node_id: node} = value),
    do: %{
      "node_id" => canonical_node(node),
      "namespace_uri" => value.namespace_uri,
      "server_index" => value.server_index
    }

  defp native_element("QualifiedName", %{namespace: namespace, name: name}),
    do: %{"namespace" => namespace, "name" => name}

  defp native_element("ExtensionObject", %{encoding_id: id, encoding: encoding, body: body}),
    do: %{
      "encoding_id" => canonical_node(id),
      "encoding" => encoding,
      "body" => native_element("ByteString", body)
    }

  defp native_element(_, element), do: element

  defp canonical_node(node) do
    {:ok, address} = Address.new(node)
    Address.to_string(address)
  end

  defp project_result("browse", %{"references" => references, "continuation" => nil}, namespaces)
       when is_list(references) and is_list(namespaces) do
    projected =
      Enum.reduce_while(references, {:ok, []}, fn reference, {:ok, nodes} ->
        case reference do
          %{"node_id" => %{"node_id" => text, "namespace_uri" => nil, "server_index" => 0}} ->
            case Address.new(text) do
              {:ok, %Address{namespace: index} = node} when index < length(namespaces) ->
                {:cont, {:ok, [Address.to_string(node) | nodes]}}

              _ ->
                {:halt, {:error, Error.new(:unsupported_remote_reference)}}
            end

          _ ->
            {:halt, {:error, Error.new(:unsupported_remote_reference)}}
        end
      end)

    case projected do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp project_result("browse", _, _), do: {:error, Error.new(:invalid_native_frame)}
  defp project_result(_, result, _), do: {:ok, result}

  defp oneshot_result(
         "read",
         %{"has_value" => true, "status" => status, "value" => variant}
       )
       when is_map(variant) do
    with false <- Map.has_key?(variant, "dimensions"),
         {:ok, value} <- legacy_payload(variant["value"]) do
      {:ok, %{"type" => variant["type"], "value" => value, "status" => status}}
    else
      _ -> {:error, Error.new(:unsupported_type)}
    end
  end

  defp oneshot_result("read", _), do: {:error, Error.new(:unsupported_type)}
  defp oneshot_result("write", %{"status" => _}), do: {:ok, "written"}

  defp oneshot_result("call", %{"outputs" => outputs}) when is_list(outputs) do
    values =
      Enum.reduce_while(outputs, {:ok, []}, fn output, {:ok, values} ->
        if Map.has_key?(output, "dimensions") do
          {:halt, {:error, Error.new(:unsupported_type)}}
        else
          case legacy_payload(output["value"]) do
            {:ok, value} -> {:cont, {:ok, [value | values]}}
            error -> {:halt, error}
          end
        end
      end)

    case values do
      {:ok, []} -> {:ok, nil}
      {:ok, [value]} -> {:ok, value}
      {:ok, many} -> {:ok, Enum.reverse(many)}
      error -> error
    end
  end

  defp oneshot_result("browse", nodes) when is_list(nodes), do: {:ok, nodes}
  defp oneshot_result(_, _), do: {:error, Error.new(:invalid_native_frame)}

  defp legacy_payload(%{"type" => "bytes", "base64" => base64}) when is_binary(base64),
    do: {:ok, %{"type" => "ByteString", "base64" => base64}}

  defp legacy_payload(values) when is_list(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, converted} ->
        case legacy_payload(value) do
          {:ok, item} -> {:cont, {:ok, [item | converted]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, converted} -> {:ok, Enum.reverse(converted)}
      error -> error
    end
  end

  defp legacy_payload(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp legacy_payload(_), do: {:error, Error.new(:unsupported_type)}

  defp invalid_request, do: {:error, Error.new(:invalid_value)}
end
