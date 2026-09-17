defmodule Wotex.BLE.BlueZ do
  @moduledoc """
  Performs Linux BlueZ GATT access through two explicit client lifecycles.

  The default one-shot mode uses an absolute `busctl` executable and an exact
  characteristic object path for an already connected device. It validates
  the service and characteristic UUIDs, invokes ReadValue or acknowledged
  WriteValue without a shell, and limits command output to 4096 bytes.
  Attribute values are limited to 512 bytes in both modes.

  With `lifecycle: :persistent`, `Wotex.BLE.BlueZ.Connection` owns the selected
  peer and one unique D-Bus sender. Persistent mode requires the complete native
  SDK path/digest and guardian path/digest cohort; both executables are verified
  under the original startup deadline before the guardian starts the
  first-party native host. Persistent mode implements GATT discovery,
  consumer-directed pairing, health probes, reads, acknowledged writes and
  value-change streams. The consumer supplies the local bus address and chooses
  borrowed or owned connection behavior.

  Neither mode starts the BlueZ service, powers an adapter or installs native
  dependencies. Ordinary borrowed-session cleanup leaves the existing device
  connection intact. An outstanding Pair call is a separate BlueZ lifecycle:
  losing its sender may make BlueZ disconnect that peer. The adapter does not
  call CancelPairing or remove a bond to manufacture cancellation.
  """
  @behaviour Wotex.BLE.Client
  alias Wotex.BLE.{Address, Error, ObjectPath, UUID}
  alias Wotex.BLE.BlueZ.Connection

  @impl Wotex.BLE.Client
  def connect(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.get_values(opts, :lifecycle) == [:persistent] do
      Connection.connect(Keyword.delete(opts, :lifecycle))
    else
      if admitted_options?(opts),
        do: connect_options(opts),
        else: {:error, Error.new(:invalid_options)}
    end
  end

  def connect(_), do: {:error, Error.new(:invalid_options)}

  defp connect_options(opts) do
    executable = Keyword.get(opts, :executable)
    path = Keyword.get(opts, :object_path)
    timeout = Keyword.get(opts, :timeout, 5000)

    with true <-
           is_binary(executable) and byte_size(executable) <= 4096 and
             Path.type(executable) == :absolute,
         true <-
           ObjectPath.valid?(path) and
             Regex.match?(
               ~r{^/org/bluez/hci[0-9]+/dev_[A-Fa-f0-9_]+/service[0-9a-fA-F]+/char[0-9a-fA-F]+$},
               path
             ),
         {:ok, service} <- UUID.normalize(Keyword.get(opts, :service)),
         {:ok, characteristic} <- UUID.normalize(Keyword.get(opts, :characteristic)),
         true <- is_integer(timeout) and timeout in 1..60_000 do
      {:ok, %{executable: executable, path: path, service: service, characteristic: characteristic}}
    else
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @impl Wotex.BLE.Client
  def request(%Connection{} = handle, message, timeout),
    do: Connection.request(handle, message, timeout)

  def request(
        %{executable: executable, path: path, service: service, characteristic: characteristic},
        message,
        timeout
      ) do
    with :ok <- Address.validate_message(message),
         {:ok, handle} <-
           connect_options(
             executable: executable,
             object_path: path,
             service: service,
             characteristic: characteristic,
             timeout: timeout
           ),
         :ok <- selection_supported(message, handle),
         {:ok, service} <- UUID.normalize(message.service),
         {:ok, characteristic} <- UUID.normalize(message.characteristic),
         true <- service == handle.service and characteristic == handle.characteristic,
         {:ok, method, signature, args} <- operation(message),
         {:ok, output} <-
           run(
             handle.executable,
             [
               "--system",
               "--timeout=#{timeout}ms",
               "call",
               "org.bluez",
               handle.path,
               "org.bluez.GattCharacteristic1",
               method,
               signature
             ] ++ args,
             timeout
           ) do
      if message.type == :read, do: decode(output), else: {:ok, :written}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:address_mismatch)}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @impl Wotex.BLE.Client
  def disconnect(%Connection{} = handle), do: Connection.disconnect(handle)
  def disconnect(_), do: :ok

  @doc "Discovers typed GATT identities through the explicitly persistent backend."
  @spec discover(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def discover(%Connection{} = handle, options, timeout),
    do: Connection.discover(handle, options, timeout)

  def discover(_, _, _), do: {:error, Error.new(:not_supported)}

  @doc "Pairs through the persistent sender and an explicit consumer Agent callback."
  @spec pair(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def pair(%Connection{} = handle, request, timeout), do: Connection.pair(handle, request, timeout)
  def pair(_, _, _), do: {:error, Error.new(:not_supported)}

  @doc "Queries actual peer state through the persistent sender."
  @spec health_check(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def health_check(%Connection{} = handle, timeout), do: Connection.health_check(handle, timeout)
  def health_check(_, _), do: {:error, Error.new(:probe_required)}

  @doc "Starts a typed stream through the persistent sender."
  @spec subscribe(term(), term(), term()) :: {:ok, Wotex.BLE.Subscription.t()} | {:error, Error.t()}
  def subscribe(%Connection{} = handle, request, timeout),
    do: Connection.subscribe(handle, request, timeout)

  def subscribe(_, _, _), do: {:error, Error.new(:not_supported)}

  @doc "Releases a subscription belonging to this persistent session."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(%Connection{} = handle, subscription),
    do: Connection.unsubscribe(handle, subscription)

  def unsubscribe(_, _), do: {:error, Error.new(:not_supported)}

  @doc "Parses busctl's exact byte-array response; bounds count and every byte."
  @spec decode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def decode(text) when is_binary(text) and byte_size(text) <= 4096 do
    case String.split(text) do
      ["ay", count | values] ->
        with {count, ""} when count in 0..512 <- Integer.parse(count),
             true <- length(values) == count,
             numbers = Enum.map(values, &Integer.parse/1),
             true <-
               Enum.all?(numbers, fn
                 {n, rest} -> rest == "" and n in 0..255
                 _ -> false
               end) do
          {:ok, :binary.list_to_bin(Enum.map(numbers, &elem(&1, 0)))}
        else
          _ -> {:error, Error.new(:invalid_response)}
        end

      _ ->
        {:error, Error.new(:invalid_response)}
    end
  end

  def decode(_), do: {:error, Error.new(:response_limit)}

  defp operation(%{type: :read}), do: {:ok, "ReadValue", "a{sv}", ["0"]}

  defp operation(%{type: :write, value: value}) when is_binary(value) and byte_size(value) <= 512 do
    values = for <<byte <- value>>, do: Integer.to_string(byte)

    {:ok, "WriteValue", "aya{sv}",
     [Integer.to_string(byte_size(value)) | values] ++ ["1", "type", "s", "request"]}
  end

  defp operation(_), do: {:error, Error.new(:invalid_request)}

  defp selection_supported(message, handle) do
    cond do
      not is_nil(Map.get(message, :handle)) or not is_nil(Map.get(message, :generation)) ->
        {:error, Error.new(:not_supported)}

      Map.get(message, :object_path) not in [nil, handle.path] ->
        {:error, Error.new(:address_mismatch)}

      true ->
        :ok
    end
  end

  defp run(executable, args, timeout) do
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status, args: args])

    try do
      collect(port, <<>>, System.monotonic_time(:millisecond) + timeout)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> {:error, Error.new(:transport_unavailable)}
  end

  defp collect(port, output, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0,
      do: {:error, Error.new(:timeout)},
      else: receive_output(port, output, deadline, remaining)
  end

  defp receive_output(port, output, deadline, remaining) do
    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 4096 ->
        collect(port, output <> data, deadline)

      {^port, {:data, _}} ->
        {:error, Error.new(:response_limit)}

      {^port, {:exit_status, 0}} ->
        {:ok, output}

      {^port, {:exit_status, _}} ->
        {:error, Error.new(:remote_error)}
    after
      remaining -> {:error, Error.new(:timeout)}
    end
  end

  defp admitted_options?(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      keys -- [:executable, :object_path, :service, :characteristic, :timeout] == [] and
        length(keys) == MapSet.size(MapSet.new(keys))
    else
      false
    end
  end
end
