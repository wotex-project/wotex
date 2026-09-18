Code.require_file("peer_process.ex", __DIR__)

defmodule Wotex.CoAP.Test.CaliforniumPeer do
  @moduledoc false

  # An independent upstream-stack OSCORE peer. The pinned Eclipse Californium
  # plugtest server owns its own CoAP engine, OSCORE implementation and
  # observation model, so its cases are cross-stack evidence rather than the
  # same-stack libcoap evidence. Each instance owns one workspace, one loopback
  # UDP port pair and one JVM process, and its server context admits exactly one
  # client sender identity, so every instance serves one fresh client context.

  use GenServer
  import ExUnit.Assertions
  alias Wotex.CoAP.Security
  alias Wotex.CoAP.Test.PeerProcess

  @master_secret Base.decode16!("0102030405060708090A0B0C0D0E0F10")
  @master_salt Base.decode16!("9E7CA92223786340")
  @id_context Base.decode16!("37CBF3210017A2D3")
  @sender_id <<0x01>>
  @recipient_id <<0x02>>
  @ready_timeout 30_000

  @spec verify!() :: {Path.t(), Path.t()}
  def verify! do
    java = System.fetch_env!("WOTEX_COAP_JAVA")
    archive = System.fetch_env!("WOTEX_COAP_INDEPENDENT_PEER")
    assert Path.type(java) == :absolute and File.regular?(java)
    assert Path.type(archive) == :absolute and File.regular?(archive)

    {version, 0} =
      System.cmd(java, ["-version"], stderr_to_stdout: true, env: clean_environment())

    digest = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)
    Mix.shell().info("independent Californium 3.14.0 plugtest server sha256: #{digest}")
    Mix.shell().info("independent peer runtime: #{String.trim(version)}")
    {java, archive}
  end

  @spec start_link({Path.t(), Path.t()}) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @doc "Returns the peer's loopback plaintext CoAP port once it listens."
  @spec endpoint(pid()) :: :inet.port_number()
  def endpoint(pid), do: GenServer.call(pid, :endpoint, @ready_timeout + 500)

  @spec close(pid()) :: :ok
  def close(pid), do: GenServer.call(pid, :close, 5000)

  @doc "Builds the client security value matching the peer's fixed server context."
  @spec security(Path.t()) :: Security.t()
  def security(store) do
    {:ok, security} =
      Security.new(
        mode: :oscore,
        master_secret: @master_secret,
        master_salt: @master_salt,
        sender_id: @sender_id,
        recipient_id: @recipient_id,
        id_context: @id_context,
        context_store: store
      )

    security
  end

  @impl GenServer
  def init({java, archive}) do
    suffix = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    workspace = Path.join(System.tmp_dir!(), "wotex-californium-#{suffix}")
    File.mkdir!(workspace)
    File.chmod!(workspace, 0o700)
    workspace = File.cd!(workspace, &File.cwd!/0)
    port = available_pair()

    File.write!(
      Path.join(workspace, "CaliforniumPlugtest3.properties"),
      "COAP.COAP_PORT=#{port}\nCOAP.COAP_SECURE_PORT=#{port + 1}\n"
    )

    {native, os_pid} =
      PeerProcess.open(
        java,
        ["-jar", archive, "--no-tcp", "--no-external", "--no-ipv6", "--notify-interval", "1s"],
        workspace
      )

    {:ok,
     %{
       native: native,
       os_pid: os_pid,
       workspace: workspace,
       port: port,
       ready: false,
       listening: false,
       waiter: nil,
       output: "",
       timer: Process.send_after(self(), :ready_timeout, @ready_timeout)
     }}
  end

  @impl GenServer
  def handle_call(:endpoint, from, state) do
    if state.ready, do: {:reply, state.port, state}, else: {:noreply, %{state | waiter: from}}
  end

  def handle_call(:close, _, state) do
    cleanup(state)
    {:stop, :normal, :ok, %{state | native: nil, workspace: nil}}
  end

  @impl GenServer
  def handle_info({native, {:data, bytes}}, %{native: native} = state) do
    # Peer logs carry protected payloads, so only a bounded partial line and the
    # exact listening marker are retained.
    [partial | lines] = String.split(state.output <> bytes, "\n") |> Enum.reverse()

    partial =
      binary_part(partial, max(byte_size(partial) - 8192, 0), min(byte_size(partial), 8192))

    # The endpoint line precedes the bound socket, so readiness needs both the
    # exact loopback endpoint and the server's own started marker.
    marker = "listen on coap://127.0.0.1:#{state.port}"
    listening = state.listening or Enum.any?(lines, &String.contains?(&1, marker))
    started = Enum.any?(lines, &String.contains?(&1, "PlugtestServer started"))
    state = %{state | output: partial, listening: listening}
    {:noreply, ready(state, state.ready or (listening and started))}
  end

  def handle_info({native, {:exit_status, status}}, %{native: native} = state),
    do: {:stop, {:peer_exit, status}, %{state | native: nil}}

  def handle_info(:ready_timeout, %{ready: false} = state), do: {:stop, :peer_ready_timeout, state}
  def handle_info(:ready_timeout, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state), do: cleanup(state)

  defp ready(state, ready) do
    if ready and not state.ready do
      Process.cancel_timer(state.timer)
      if state.waiter, do: GenServer.reply(state.waiter, state.port)
    end

    %{state | ready: ready}
  end

  defp cleanup(%{workspace: nil}), do: :ok

  defp cleanup(state) do
    Process.cancel_timer(state.timer)

    if state.native do
      System.cmd("/bin/kill", ["-TERM", Integer.to_string(state.os_pid)],
        stderr_to_stdout: true,
        env: clean_environment()
      )

      await_exit(state.native, state.os_pid, System.monotonic_time(:millisecond) + 5000)
    end

    File.rm_rf!(state.workspace)
    assert ports_free?(state.port)
  end

  defp await_exit(native, os_pid, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^native, {:exit_status, status}} -> assert status == PeerProcess.stopped_status()
      {^native, {:data, _}} -> await_exit(native, os_pid, deadline)
    after
      remaining ->
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(os_pid)],
          stderr_to_stdout: true,
          env: clean_environment()
        )

        assert_receive {^native, {:exit_status, _}}, 2000
    end
  end

  defp clean_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp available_pair(attempts \\ 128)

  defp available_pair(0), do: raise("no adjacent UDP peer ports available")

  defp available_pair(attempts) do
    {:ok, socket} = :gen_udp.open(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_udp.close(socket)

    if port < 65_535 and ports_free?(port), do: port, else: available_pair(attempts - 1)
  end

  defp ports_free?(port), do: Enum.all?([port, port + 1], &port_free?/1)

  defp port_free?(port) do
    case :gen_udp.open(port, [:binary, ip: {127, 0, 0, 1}]) do
      {:ok, udp} ->
        :gen_udp.close(udp)
        true

      _ ->
        false
    end
  end
end
