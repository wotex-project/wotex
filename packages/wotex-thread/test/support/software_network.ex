defmodule Wotex.Thread.SoftwareNetwork do
  @moduledoc false

  alias Wotex.Thread.OpenThread

  @interfaces %{
    leader: "wthleader",
    joiner: "wthjoiner",
    daemon: "wthdaemon",
    sensor: "wthsensor",
    light: "wthlight"
  }
  @node_variables %{
    leader: "WOTEX_THREAD_NODE_LEADER",
    joiner: "WOTEX_THREAD_NODE_JOINER",
    daemon: "WOTEX_THREAD_NODE_DAEMON",
    sensor: "WOTEX_THREAD_NODE_SENSOR",
    light: "WOTEX_THREAD_NODE_LIGHT"
  }

  @type owned_process :: %{
          required(:port) => port(),
          required(:os_pid) => pos_integer(),
          required(:executable) => Path.t(),
          required(:pids) => [pos_integer()],
          optional(atom()) => term()
        }

  @doc "Returns an isolated native-host configuration for one fixed simulation node."
  @spec host_options(atom(), Path.t(), keyword()) :: keyword()
  def host_options(role, root, options \\ []) when is_atom(role) and is_binary(root) do
    storage_mode = Keyword.get(options, :storage_mode, :create_new)
    allow_network_creation = Keyword.get(options, :allow_network_creation, false)
    executable = System.fetch_env!("WOTEX_THREAD_HOST")

    [
      client: OpenThread,
      executable: executable,
      executable_sha256: digest(executable),
      radio_url: radio_url(role),
      interface: Map.fetch!(@interfaces, role),
      storage_path: Path.join([root, "stores", Atom.to_string(role)]),
      storage_mode: storage_mode,
      allow_network_creation: allow_network_creation,
      owner: self(),
      timeout: Keyword.get(options, :timeout, 10_000)
    ]
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  @doc "Starts the pinned borrowed daemon on its own simulation RCP."
  @spec start_daemon(Path.t()) :: {:ok, owned_process()} | {:error, term()}
  def start_daemon(root) do
    executable = System.fetch_env!("WOTEX_THREAD_DAEMON")
    socket = System.fetch_env!("WOTEX_THREAD_DAEMON_SOCKET")
    data = Path.join(root, "daemon-data")
    :ok = private_directory(data)

    args = [
      "--data-path",
      data,
      "--settings-file",
      "settings",
      "-I",
      @interfaces.daemon,
      radio_url(:daemon)
    ]

    with {:ok, process} <- start_process(executable, args) do
      process = Map.put(process, :pids, [process.os_pid | descendants(process.os_pid)])

      case await_path(socket, process.port, 10_000) do
        :ok ->
          {:ok,
           Map.merge(process, %{
             socket: socket,
             interface: @interfaces.daemon,
             pids: [process.os_pid | descendants(process.os_pid)]
           })}

        {:error, _} = error ->
          stop_process(process)
          error
      end
    end
  end

  @doc "Starts one pinned OpenThread CoAP application peer and returns its mesh-local address."
  @spec start_application(Path.t(), :sensor | :light, :sensor | :light, Path.t()) ::
          {:ok, owned_process()} | {:error, term()}
  def start_application(root, role, mode, dataset_path)
      when role in [:sensor, :light] and mode in [:sensor, :light] do
    executable = System.fetch_env!("WOTEX_THREAD_COAP_PEER")
    storage = Path.join([root, "application", Atom.to_string(role), "store"])
    report = Path.join([root, "application", Atom.to_string(role), "report.json"])
    :ok = private_directory(storage)

    args = [
      "--radio",
      radio_url(role),
      "--interface",
      Map.fetch!(@interfaces, role),
      "--storage",
      storage,
      "--dataset",
      dataset_path,
      "--mode",
      Atom.to_string(mode),
      "--report",
      report
    ]

    with {:ok, process} <- start_process(executable, args) do
      process = Map.put(process, :pids, [process.os_pid | descendants(process.os_pid)])

      result =
        with {:ok, ready} <- await_ready(process.port, <<>>, 30_000),
             true <- ready["mode"] == Atom.to_string(mode),
             true <- ready["role"] in ["child", "router"],
             true <- is_binary(ready["address"]) and byte_size(ready["address"]) in 2..64 do
          {:ok,
           Map.merge(process, %{
             address: ready["address"],
             interface: Map.fetch!(@interfaces, role),
             mode: mode,
             report: report,
             sleepy: ready["sleepy"],
             pids: [process.os_pid | descendants(process.os_pid)]
           })}
        else
          false -> {:error, :invalid_application_ready}
          {:error, _} = error -> error
        end

      if match?({:error, _}, result), do: stop_process(process)
      result
    end
  end

  @doc "Stops one owned daemon or application process and waits for all recorded descendants."
  @spec stop_process(owned_process()) :: :ok | {:error, :timeout}
  def stop_process(%{port: port, os_pid: pid, executable: executable, pids: pids}) do
    if owned_process?(pid, executable), do: signal(pid, "-TERM")

    case eventually(fn -> Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) end, 5_000) do
      :ok ->
        :ok

      {:error, :timeout} ->
        if owned_process?(pid, executable), do: signal(pid, "-KILL")
    end

    result = eventually(fn -> Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) end, 5_000)
    close_port(port)
    result
  end

  @doc "Reads the finite application report written during graceful shutdown."
  @spec application_report(map()) :: {:ok, map()} | {:error, :invalid_application_report}
  def application_report(%{report: path}) do
    with {:ok, bytes} <- File.read(path),
         {:ok, report} when is_map(report) <- Jason.decode(bytes) do
      {:ok, report}
    else
      _ -> {:error, :invalid_application_report}
    end
  end

  @doc "Returns the native host and forkpty descendant PIDs for cleanup assertions."
  @spec native_pids(Wotex.Thread.Session.t()) :: [pos_integer()]
  def native_pids(session) do
    state = :sys.get_state(session.handle.pid)
    port = Map.fetch!(state, :port)
    {:os_pid, pid} = Port.info(port, :os_pid)

    [pid | descendants(pid)]
  end

  @doc "Waits for a condition without extending the supplied finite timeout."
  @spec eventually((-> term()), non_neg_integer()) :: :ok | {:error, :timeout}
  def eventually(condition, timeout \\ 5_000) when is_function(condition, 0) do
    eventually_until(condition, System.monotonic_time(:millisecond) + timeout)
  end

  @doc "Returns whether a recorded Linux process still executes the expected fixture binary."
  @spec owned_process?(pos_integer(), Path.t()) :: boolean()
  def owned_process?(pid, executable) when is_integer(pid) and is_binary(executable) do
    case File.read_link("/proc/#{pid}/exe") do
      {:ok, target} -> target == executable
      _ -> false
    end
  end

  defp eventually_until(condition, deadline) do
    if condition.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        receive do
        after
          10 -> eventually_until(condition, deadline)
        end
      else
        {:error, :timeout}
      end
    end
  end

  defp start_process(executable, args) do
    if Path.type(executable) == :absolute and File.regular?(executable) do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: Enum.map(args, &String.to_charlist/1),
          env: cleared_environment()
        ])

      case Port.info(port, :os_pid) do
        {:os_pid, pid} ->
          {:ok, %{port: port, os_pid: pid, executable: executable}}

        _ ->
          close_port(port)
          {:error, :application_start_failed}
      end
    else
      {:error, :fixture_executable_unavailable}
    end
  end

  defp await_path(path, port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_path(path, port, deadline, 0)
  end

  defp await_path(path, port, deadline, output_bytes) do
    cond do
      File.exists?(path) and Port.info(port) != nil ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :daemon_start_timeout}

      true ->
        receive do
          {^port, {:data, bytes}} when output_bytes + byte_size(bytes) <= 4_096 ->
            await_path(path, port, deadline, output_bytes + byte_size(bytes))

          {^port, {:data, _}} ->
            {:error, :daemon_output_limit}

          {^port, {:exit_status, status}} ->
            {:error, {:daemon_exit, status}}
        after
          10 -> await_path(path, port, deadline, output_bytes)
        end
    end
  end

  defp await_ready(port, bytes, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_ready_until(port, bytes, deadline)
  end

  defp await_ready_until(port, bytes, deadline) do
    case :binary.match(bytes, "\n") do
      {position, 1} ->
        line = binary_part(bytes, 0, position)

        case Jason.decode(line) do
          {:ok,
           %{
             "ready" => true,
             "mode" => mode,
             "role" => role,
             "address" => address,
             "sleepy" => sleepy
           } = ready}
          when map_size(ready) == 5 and is_binary(mode) and is_binary(role) and
                 is_binary(address) and is_boolean(sleepy) ->
            {:ok, ready}

          _ ->
            {:error, :invalid_application_ready}
        end

      :nomatch when byte_size(bytes) > 4_096 ->
        {:error, :application_output_limit}

      :nomatch ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :application_start_timeout}
        else
          receive do
            {^port, {:data, more}} -> await_ready_until(port, bytes <> more, deadline)
            {^port, {:exit_status, status}} -> {:error, {:application_exit, status}}
          after
            10 -> await_ready_until(port, bytes, deadline)
          end
        end
    end
  end

  defp radio_url(role) do
    rcp = System.fetch_env!("WOTEX_THREAD_RCP")
    node = System.fetch_env!(Map.fetch!(@node_variables, role))

    with {number, ""} <- Integer.parse(node), true <- number in 1..65_535 do
      "spinel+hdlc+forkpty://#{rcp}?forkpty-arg=#{number}"
    else
      _ -> raise "invalid simulation node assignment for #{role}"
    end
  end

  defp private_directory(path) do
    case File.mkdir_p(path) do
      :ok -> File.chmod(path, 0o700)
      {:error, _} = error -> error
    end
  end

  defp descendants(pid) do
    case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, bytes} ->
        children =
          bytes
          |> String.split()
          |> Enum.map(&String.to_integer/1)

        children ++ Enum.flat_map(children, &descendants/1)

      {:error, :enoent} ->
        []
    end
  end

  defp signal(pid, signal) do
    System.cmd("/bin/kill", [signal, Integer.to_string(pid)],
      stderr_to_stdout: true,
      env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
    )

    :ok
  end

  defp close_port(port) do
    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end
  end

  defp cleared_environment do
    Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
  end
end
