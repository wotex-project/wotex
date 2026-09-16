defmodule Wotex.CoAP.Test.LibcoapPeer do
  @moduledoc false

  use GenServer
  import ExUnit.Assertions
  alias Wotex.CoAP.Security
  @fixtures Path.expand("../fixtures/dtls_pki", __DIR__)
  @key "fixture-key-12345"

  @spec verify!() :: Path.t()
  def verify! do
    executable = System.fetch_env!("WOTEX_COAP_LIBCOAP_SERVER")
    assert Path.type(executable) == :absolute and File.regular?(executable)
    {version, _} = System.cmd(executable, ["-?"], stderr_to_stdout: true, env: clean_environment())
    assert version =~ "4.3.5" and version =~ "OpenSSL"
    digest = :crypto.hash(:sha256, File.read!(executable)) |> Base.encode16(case: :lower)
    Mix.shell().info("independent libcoap 4.3.5/OpenSSL server sha256: #{digest}")
    executable
  end

  @spec start_link({Path.t(), :psk | :pki, String.t()}) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec endpoint(pid()) :: :inet.port_number()
  def endpoint(pid), do: GenServer.call(pid, :endpoint, 15_500)

  @spec plain_endpoint(pid()) :: :inet.port_number()
  def plain_endpoint(pid), do: GenServer.call(pid, :plain_endpoint, 15_500)

  @spec close(pid()) :: :ok
  def close(pid), do: GenServer.call(pid, :close, 3000)

  @spec security(:psk, keyword()) :: Security.t()
  def security(:psk, options \\ []) do
    {:ok, security} =
      Security.new(Keyword.merge([mode: :dtls_psk, identity: "client", key: @key], options))

    security
  end

  @spec pki_security(keyword()) :: Security.t()
  def pki_security(options \\ []) do
    {:ok, security} =
      Security.new(
        Keyword.merge(
          [
            mode: :dtls_pki,
            trust_roots: [fixture("root.der")],
            certificate: fixture("client.der"),
            private_key: fixture("client-key.der"),
            server_identity: {:dns, "fixture.test"},
            crls: [fixture("valid-crl.der")]
          ],
          options
        )
      )

    security
  end

  @spec fixture(String.t()) :: binary()
  def fixture(name), do: File.read!(Path.join(@fixtures, name))

  @impl GenServer
  def init({executable, mode, certificate}) do
    suffix = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    workspace = Path.join(System.tmp_dir!(), "wotex-dtls-peer-#{suffix}")

    File.mkdir!(workspace)
    File.chmod!(workspace, 0o700)
    port = available_pair()

    args =
      [
        "-A",
        "127.0.0.1",
        "-p",
        Integer.to_string(port),
        "-v",
        "7",
        "-V",
        "0",
        "-d",
        "4",
        "-e",
        "-L",
        "1"
      ] ++
        credentials(mode, certificate, workspace)

    native =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        env: Enum.map(clean_environment(), fn {name, nil} -> {String.to_charlist(name), false} end)
      ])

    {:os_pid, os_pid} = Port.info(native, :os_pid)

    {:ok,
     %{
       native: native,
       os_pid: os_pid,
       workspace: workspace,
       port: port,
       ready: false,
       waiter: nil,
       output: "",
       timer: Process.send_after(self(), :ready_timeout, 15_000)
     }}
  end

  @impl GenServer
  def handle_call(:endpoint, from, state) do
    if state.ready,
      do: {:reply, state.port + 1, state},
      else: {:noreply, %{state | waiter: from}}
  end

  def handle_call(:plain_endpoint, from, state) do
    if state.ready,
      do: {:reply, state.port, state},
      else: {:noreply, %{state | waiter: {from, :plain}}}
  end

  def handle_call(:close, _, state) do
    cleanup(state)
    {:stop, :normal, :ok, %{state | native: nil, workspace: nil}}
  end

  @impl GenServer
  def handle_info({native, {:data, bytes}}, %{native: native} = state) do
    output = state.output <> bytes
    assert byte_size(output) <= 1_048_576
    ready = state.ready or String.contains?(output, "created DTLS endpoint")

    if ready and not state.ready do
      Process.cancel_timer(state.timer)

      case state.waiter do
        {from, :plain} -> GenServer.reply(from, state.port)
        from when is_tuple(from) -> GenServer.reply(from, state.port + 1)
        nil -> :ok
      end
    end

    {:noreply, %{state | ready: ready, output: output}}
  end

  def handle_info({native, {:exit_status, status}}, %{native: native} = state),
    do: {:stop, {:peer_exit, status}, %{state | native: nil}}

  def handle_info(:ready_timeout, %{ready: false} = state), do: {:stop, :peer_ready_timeout, state}
  def handle_info(:ready_timeout, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state), do: cleanup(state)

  defp cleanup(%{workspace: nil}), do: :ok

  defp cleanup(state) do
    Process.cancel_timer(state.timer)

    if state.native do
      System.cmd("/bin/kill", ["-TERM", Integer.to_string(state.os_pid)],
        stderr_to_stdout: true,
        env: clean_environment()
      )

      await_exit(state.native, state.os_pid, System.monotonic_time(:millisecond) + 1000)
    end

    File.rm_rf!(state.workspace)
    assert_ports_free(state.port)
  end

  defp await_exit(native, os_pid, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^native, {:exit_status, status}} -> assert status == 0
      {^native, {:data, _}} -> await_exit(native, os_pid, deadline)
    after
      remaining ->
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(os_pid)],
          stderr_to_stdout: true,
          env: clean_environment()
        )

        assert_receive {^native, {:exit_status, _}}, 1000
    end
  end

  defp clean_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp credentials(:psk, _, workspace) do
    path = Path.join(workspace, "identities.csv")
    File.write!(path, "fixture,client,#{@key}\n")
    ["-h", "fixture", "-k", "unmatched-identity-key", "-i", path]
  end

  defp credentials(:pki, certificate, workspace) do
    cert = pem(workspace, certificate <> ".der", :Certificate)
    key = pem(workspace, certificate <> "-key.der", :RSAPrivateKey)
    root = pem(workspace, "root.der", :Certificate)
    ["-c", cert, "-j", key, "-C", root]
  end

  defp pem(workspace, name, type) do
    path = Path.join(workspace, name <> ".pem")
    File.write!(path, :public_key.pem_encode([{type, fixture(name), :not_encrypted}]))
    path
  end

  defp available_pair(attempts \\ 128)

  defp available_pair(0), do: raise("no adjacent UDP/TCP peer ports available")

  defp available_pair(attempts) do
    {:ok, socket} = :gen_udp.open(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_udp.close(socket)

    if port < 65_535 and ports_free?(port) do
      port
    else
      available_pair(attempts - 1)
    end
  end

  defp assert_ports_free(port) do
    assert ports_free?(port)
  end

  defp ports_free?(port), do: Enum.all?([port, port + 1], &port_free?/1)

  defp port_free?(port) do
    case :gen_udp.open(port, [:binary, ip: {127, 0, 0, 1}]) do
      {:ok, udp} ->
        :gen_udp.close(udp)
        tcp_port_free?(port)

      _ ->
        false
    end
  end

  defp tcp_port_free?(port) do
    case :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, reuseaddr: true]) do
      {:ok, tcp} ->
        :gen_tcp.close(tcp)
        true

      _ ->
        false
    end
  end
end
