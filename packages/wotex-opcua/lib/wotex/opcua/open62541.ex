defmodule Wotex.OPCUA.Open62541 do
  @moduledoc """
  Runs explicit OPC UA operations through the owned open62541 C executable.

  `connect/1` validates the WOP.13 native configuration. Persistent mode opens
  one secure Session and binds its temporary native host to the calling process.
  One-shot mode defers credential reads and process startup until `request/3`.
  This client currently projects Value Read, typed Write and Method Call results
  as validated native maps. Browse, subscriptions and the complete compatibility
  projection remain separate work. No operation invokes Python or retries a
  transmitted mutation.
  """

  @behaviour Wotex.OPCUA.Client

  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Native.{Config, Host}

  @types ~w(Boolean SByte Byte Int16 UInt16 Int32 UInt32 Int64 UInt64 Float Double String DateTime Guid ByteString StatusCode LocalizedText)

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
  def request(%{owner: owner, config: %Config{} = config, host: host}, message, timeout)
      when owner == self() and is_integer(timeout) and timeout in 1..60_000 do
    with {:ok, operation, parameters} <- service(message) do
      case config.lifecycle do
        :persistent when is_pid(host) -> Host.request(host, operation, parameters, timeout)
        :oneshot when is_nil(host) -> oneshot_request(config, operation, parameters, timeout)
        _ -> {:error, Error.new(:invalid_native_handle)}
      end
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_native_handle)}

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
        {:ok, _} ->
          {:ok, %{owner: self(), config: config, host: host}}

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
        with {:ok, _} <- request_before(host, "open", open, deadline),
             {:ok, result} <- request_before(host, operation, parameters, deadline),
             {:ok, nil} <- Host.request(host, "close", %{}, min(config.timeout, 5000)) do
          {:ok, result}
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

  defp request_before(host, operation, parameters, deadline) do
    case remaining(deadline) do
      0 -> {:error, Error.new(:deadline_exceeded, :deadline)}
      timeout -> Host.request(host, operation, parameters, timeout)
    end
  end

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

  defp service(%{type: type}) when type in [:browse, :browse_next, :browse_release],
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

  defp native_bytes(%{"type" => "ByteString", "value" => bytes} = value) when is_binary(bytes),
    do: %{value | "value" => %{"type" => "bytes", "base64" => Base.encode64(bytes)}}

  defp native_bytes(%{"type" => "ByteString", "array" => true, "value" => values} = value)
       when is_list(values),
       do: %{value | "value" => Enum.map(values, &byte_element/1)}

  defp native_bytes(value), do: value

  defp byte_element(bytes) when is_binary(bytes),
    do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}

  defp byte_element(nil), do: nil

  defp invalid_request, do: {:error, Error.new(:invalid_value)}
end
