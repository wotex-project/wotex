defmodule Wotex.CoAP.Bench.LibcoapPeer do
  @moduledoc false

  # The same-stack OSCORE peer of the native benchmarks: libcoap 4.3.5's
  # coap-server, built as the software lane builds its peer (the verified
  # archive of the native workspace, unpatched, with the lane's CMake options)
  # and configured as the lane's OSCORE peer, with warnings-only logging so
  # that peer logging does not load the measured exchanges.

  use GenServer

  alias Wotex.CoAP
  alias Wotex.CoAP.{Message, Security}
  alias Wotex.CoAP.Native.Archive

  # Wotex.CoAP.Software.Build's peer options.
  @cmake_options ~w(ENABLE_OSCORE=ON ENABLE_DTLS=ON DTLS_BACKEND=openssl BUILD_SHARED_LIBS=OFF
    ENABLE_DOCS=OFF ENABLE_TESTS=OFF ENABLE_EXAMPLES=ON CMAKE_BUILD_TYPE=Release)
  @ready_timeout 15_000

  defstruct [:pid, :port, :secret, :root, :backend]

  @type t :: %__MODULE__{
          pid: pid(),
          port: :inet.port_number(),
          secret: binary(),
          root: Path.t(),
          backend: %{executable: Path.t(), manifest: Path.t()}
        }

  @doc """
  Builds coap-server in `scratch` from the native workspace's verified libcoap
  archive and starts it with an OSCORE context whose recipients are `senders`.
  """
  @spec start!(Path.t(), Path.t(), [binary()]) :: t()
  def start!(workspace, scratch, senders) do
    root = private_directory(Path.join(scratch, "oscore"))
    executable = build!(workspace, root)
    secret = :crypto.strong_rand_bytes(16)
    port = available_pair()
    config = Path.join(root, "oscore.conf")
    File.write!(config, config(secret, senders))
    {:ok, pid} = GenServer.start_link(__MODULE__, {executable, arguments(port, config)})
    await_ready!(port, System.monotonic_time(:millisecond) + @ready_timeout)

    %__MODULE__{
      pid: pid,
      port: port,
      secret: secret,
      root: root,
      backend: %{
        executable: Path.join(workspace, "bin/wotex-coap-oscore"),
        manifest: Path.join(workspace, "native-manifest.json")
      }
    }
  end

  @doc "Stops the peer process."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid}), do: GenServer.call(pid, :stop, 5_000)

  @doc "Options of a native OSCORE session to the peer as `sender`, with a new context store."
  @spec session_options(t(), binary()) :: keyword()
  def session_options(%__MODULE__{} = peer, sender) do
    store = private_directory(Path.join(peer.root, "store-" <> Base.encode16(sender)))

    {:ok, security} =
      Security.new(
        mode: :oscore,
        master_secret: peer.secret,
        master_salt: <<>>,
        sender_id: sender,
        recipient_id: <<>>,
        context_store: store
      )

    [
      host: "127.0.0.1",
      port: peer.port,
      timeout: 5_000,
      security: security,
      native_backend: peer.backend
    ]
  end

  @doc "Options of an unprotected UDP session to the peer."
  @spec plain_options(t()) :: keyword()
  def plain_options(%__MODULE__{port: port}), do: [host: "127.0.0.1", port: port, timeout: 5_000]

  @impl GenServer
  def init({executable, arguments}) do
    Process.flag(:trap_exit, true)

    native =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: arguments,
        env: Enum.map(System.get_env(), fn {name, _} -> {String.to_charlist(name), false} end)
      ])

    {:os_pid, os_pid} = Port.info(native, :os_pid)
    {:ok, %{native: native, os_pid: os_pid, output: ""}}
  end

  @impl GenServer
  def handle_call(:stop, _, state) do
    terminate(:normal, state)
    {:stop, :normal, :ok, %{state | native: nil}}
  end

  @impl GenServer
  def handle_info({native, {:data, bytes}}, %{native: native} = state) do
    output = state.output <> bytes
    kept = min(byte_size(output), 4_096)
    {:noreply, %{state | output: binary_part(output, byte_size(output) - kept, kept)}}
  end

  def handle_info({native, {:exit_status, status}}, %{native: native} = state),
    do: {:stop, {:peer_exit, status, state.output}, %{state | native: nil}}

  def handle_info({:EXIT, _, reason}, state), do: {:stop, reason, state}

  @impl GenServer
  def terminate(_, %{native: nil}), do: :ok

  def terminate(_, %{native: native, os_pid: os_pid}) do
    signal(os_pid, "-TERM")

    receive do
      {^native, {:exit_status, _}} -> :ok
    after
      1_000 ->
        signal(os_pid, "-KILL")

        receive do
          {^native, {:exit_status, _}} -> :ok
        after
          1_000 -> :ok
        end
    end
  end

  defp signal(os_pid, name) do
    System.cmd("/bin/kill", [name, Integer.to_string(os_pid)],
      stderr_to_stdout: true,
      env: cleared_environment()
    )
  end

  defp build!(workspace, root) do
    manifest =
      workspace
      |> Path.join("native-manifest.json")
      |> File.read!()
      |> Jason.decode!()

    source = manifest["build"]["source"]
    identity = manifest["workspace"]["identity"]
    tools = identity["tool_paths"]
    archive_root = "libcoap-" <> source["commit"]
    sources = Path.join(root, "sources")
    build = Path.join(root, "build")

    :ok =
      Archive.extract(Path.join(workspace, "downloads/libcoap.tar.gz"), sources, %{
        root: archive_root,
        sha256: source["sha256"]
      })

    environment = build_environment(tools, identity["openssl_root"])

    run!(tools["cmake"], environment, [
      "-S",
      Path.join(sources, archive_root),
      "-B",
      build,
      "-DCMAKE_C_COMPILER=#{tools["cc"]}",
      "-DOPENSSL_ROOT_DIR=#{identity["openssl_root"]}",
      "-DPKG_CONFIG_EXECUTABLE=#{tools["pkg_config"]}"
      | Enum.map(@cmake_options, &("-D" <> &1))
    ])

    parallel = Integer.to_string(System.schedulers_online())

    run!(tools["cmake"], environment, [
      "--build",
      build,
      "--target",
      "coap-server",
      "--parallel",
      parallel
    ])

    Path.join(build, "coap-server")
  end

  defp run!(executable, environment, arguments) do
    case System.cmd(executable, arguments, stderr_to_stdout: true, env: environment) do
      {_, 0} -> :ok
      {output, status} -> raise "#{Path.basename(executable)} failed (#{status}):\n#{output}"
    end
  end

  # The software lane's build environment: the resolved tools, OpenSSL and C
  # messages, nothing else inherited.
  defp build_environment(tools, openssl_root) do
    path =
      tools
      |> Map.values()
      |> Enum.map(&Path.dirname/1)
      |> Kernel.++(["/usr/bin", "/bin"])
      |> Enum.uniq()
      |> Enum.join(":")

    cleared_environment() ++
      [
        {"CC", tools["cc"]},
        {"LC_ALL", "C"},
        {"OPENSSL_ROOT_DIR", openssl_root},
        {"PATH", path},
        {"PKG_CONFIG", tools["pkg_config"]}
      ]
  end

  defp cleared_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  # The software lane's peer arguments with warnings-only logging.
  defp arguments(port, config) do
    ["-A", "127.0.0.1", "-p", Integer.to_string(port)] ++
      ~w(-v 4 -V 0 -d 256 -e -L 1) ++ ["-E", config]
  end

  defp config(secret, senders) do
    recipients =
      Enum.map_join(senders, fn id ->
        ~s(recipient_id,hex,"#{Base.encode16(id, case: :lower)}"\n)
      end)

    [
      ~s(master_secret,hex,"#{Base.encode16(secret, case: :lower)}"\n),
      ~s(master_salt,hex,""\n),
      ~s(sender_id,hex,""\n),
      recipients,
      "replay_window,integer,32\naead_alg,integer,10\nhkdf_alg,integer,-10\n",
      "rfc8613_b_1_2,bool,false\nrfc8613_b_2,bool,false\nssn_freq,integer,32\n"
    ]
  end

  # The context store requires an owned 0700 directory reached without symlinks.
  defp private_directory(path) do
    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
    File.cd!(path, &File.cwd!/0)
  end

  defp await_ready!(port, deadline) do
    cond do
      ready?(port) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "coap-server did not answer on port #{port}"

      true ->
        Process.sleep(50)
        await_ready!(port, deadline)
    end
  end

  defp ready?(port) do
    case CoAP.connect(host: "127.0.0.1", port: port, timeout: 500) do
      {:ok, session} ->
        result = CoAP.get(session, "/")
        CoAP.disconnect(session)
        match?({:ok, %Message{code: 69}}, result)

      _ ->
        false
    end
  end

  # coap-server also binds TCP on its port and a secure endpoint on the next one.
  defp available_pair(attempts \\ 128)
  defp available_pair(0), do: raise("no adjacent free UDP and TCP ports")

  defp available_pair(attempts) do
    {:ok, socket} = :gen_udp.open(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_udp.close(socket)

    if port < 65_535 and Enum.all?([port, port + 1], &free?/1),
      do: port,
      else: available_pair(attempts - 1)
  end

  defp free?(port) do
    with {:ok, udp} <- :gen_udp.open(port, [:binary, ip: {127, 0, 0, 1}]),
         :ok <- :gen_udp.close(udp),
         {:ok, tcp} <- :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, reuseaddr: true]) do
      :gen_tcp.close(tcp)
      true
    else
      _ -> false
    end
  end
end
