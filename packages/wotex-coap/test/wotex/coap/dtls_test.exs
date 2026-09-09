defmodule Wotex.CoAP.DTLSTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Security}
  alias Wotex.CoAP.Datagram.DTLS
  @moduletag :capture_log
  @key "fixture-key-12345"
  @cipher %{key_exchange: :psk, cipher: :aes_128_gcm, mac: :aead, prf: :sha256}

  test "WCO-S05 WCO-V12 native PSK exchanges authenticate with a real OTP DTLS peer" do
    {peer, listener, port} = peer()
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)

    {:ok, session} =
      CoAP.connect(host: "127.0.0.1", port: port, scheme: :coaps, security: security, timeout: 1000)

    assert_receive {:identity, "client"}
    adapter = :sys.get_state(session.pid).handle
    state = :sys.get_state(adapter.pid)

    assert {:ok, information} =
             :ssl.connection_information(state.socket, [:protocol, :selected_cipher_suite])

    assert information[:protocol] == :"dtlsv1.2" and information[:selected_cipher_suite] == @cipher
    refute Map.has_key?(state.config, :options)
    refute inspect(:sys.get_status(adapter.pid)) =~ @key
    {:ok, {_, client_port}} = :ssl.sockname(state.socket)
    task = Task.async(fn -> CoAP.get(session, "/secure") end)
    assert_receive {:request, request}
    assert Codec.option(request, 11) == ["secure"]

    send(
      peer.pid,
      {:reply, %{request | type: :ack, code: 69, options: [{12, <<42>>}], payload: "value"}}
    )

    assert {:ok, %{payload: "value", code: 69}} = Task.await(task)

    assert {:error, %Error{code: :invalid_datagram_handle}} =
             DTLS.send(%{adapter | generation: make_ref()}, "foreign")

    assert :ok = CoAP.disconnect(session)
    assert :ok = DTLS.close(adapter)
    assert_socket_free(client_port)
    close_peer(peer, listener)
  end

  test "WCO-C02 WCO-S05 invalid security cannot acquire a socket or stop an unrelated process" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)

    for extra <- [
          [scheme: :coaps],
          [scheme: :coaps, security: %{security | key: "short"}],
          [security: security],
          [datagram: {DTLS, [security: security]}],
          [scheme: :coaps, security: security, datagram: {DTLS, []}],
          [scheme: :coaps, security: security, execution: {UnknownFixtureClock, []}]
        ] do
      assert {:error, %Error{}} = CoAP.connect([host: "127.0.0.1", port: port] ++ extra)
    end

    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 10)
    :gen_udp.close(socket)
    {:ok, config} = Connection.config(host: "127.0.0.1", scheme: :coaps, security: security)
    assert config.port == 5684 and config.adapter == DTLS
    {:ok, agent} = Agent.start_link(fn -> :untouched end)

    for pid <- [self(), agent, nil] do
      handle = %{pid: pid, generation: make_ref()}
      assert {:error, %Error{code: :invalid_datagram_handle}} = DTLS.close(handle)
      assert {:error, %Error{code: :invalid_datagram_handle}} = DTLS.send(handle, <<>>)
      assert {:error, %Error{code: :invalid_datagram_handle}} = DTLS.set_active_once(handle)
    end

    assert Agent.get(agent, & &1) == :untouched
    Agent.stop(agent)
    assert :ok = DTLS.close(%{pid: agent, generation: make_ref()})

    assert {:error, %Error{code: :connection_closed}} =
             DTLS.send(%{pid: agent, generation: make_ref()}, <<>>)

    assert {:error, %Error{code: :invalid_datagram}} = DTLS.send(nil, nil)
    assert {:error, %Error{}} = DTLS.send(nil, :binary.copy(<<0>>, 1153))
    assert {:error, %Error{code: :invalid_datagram_config}} = DTLS.open(nil, self(), 100)
  end

  test "WCO-S05 WCO-V12 wrong PSK and identity fail without a CoAP request or cleartext fallback" do
    for changes <- [[identity: "wrong"], [key: "wrong-key-1234567"]] do
      {peer, listener, port} = peer()

      {:ok, security} =
        Security.new(Keyword.merge([mode: :dtls_psk, identity: "client", key: @key], changes))

      assert {:error, %Error{} = error} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: security,
                 timeout: 300
               )

      refute inspect(error) =~ @key
      refute_received {:request, _}
      close_peer(peer, listener)
    end
  end

  test "WCO-C03 WCO-S05 owner death interrupts a DTLS handshake and releases its actual UDP port" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    owner = spawn(fn -> receive do: (:done -> :ok) end)
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)

    task =
      Task.async(fn ->
        CoAP.connect(
          host: "127.0.0.1",
          port: port,
          owner: owner,
          scheme: :coaps,
          security: security,
          timeout: 3000
        )
      end)

    assert {:ok, {_, client_port, <<22, 254, _::binary>>}} = :gen_udp.recv(peer, 0, 1000)
    started = System.monotonic_time(:millisecond)
    send(owner, :done)
    assert {:error, %Error{}} = Task.await(task, 1100)
    assert_socket_free(client_port)
    assert System.monotonic_time(:millisecond) - started < 1000
    :gen_udp.close(peer)
  end

  test "WCO-C03 WCO-V15 paused DTLS owners and close deadlines release authenticated sockets" do
    for cleanup <- [:owner_death, :close] do
      {peer, listener, port} = peer()
      owner = spawn(fn -> receive do: (:done -> :ok) end)
      {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)
      generation = make_ref()

      config = %{
        host: {127, 0, 0, 1},
        port: port,
        generation: generation,
        options: [security: security]
      }

      {:ok, adapter} = DTLS.open(config, owner, 1000)
      state = :sys.get_state(adapter.pid)
      {:ok, {_, client_port}} = :ssl.sockname(state.socket)
      assert {:error, %Error{code: :invalid_datagram_handle}} = GenServer.call(adapter.pid, :forged)

      assert {:error, %Error{code: :transport_error}} =
               GenServer.call(adapter.pid, {generation, :forged})

      send(adapter.pid, {:ssl_closed, :foreign})
      send(adapter.pid, {:ssl_error, :foreign, :secret})
      assert :ok = DTLS.set_active_once(adapter)
      monitor = Process.monitor(adapter.pid)
      true = :erlang.suspend_process(adapter.pid)

      case cleanup do
        :owner_death -> send(owner, :done)
        :close -> assert {:error, %Error{code: :cleanup_timeout}} = DTLS.close(adapter)
      end

      assert_receive {:DOWN, ^monitor, :process, _, :killed}, 1000
      assert_socket_free(client_port)
      assert :ok = DTLS.close(adapter)
      send(owner, :done)
      close_peer(peer, listener)
    end
  end

  test "WCO-S05 WCO-V12 authenticated record replay cannot emit an extra datagram" do
    {peer, listener, peer_port} = peer()
    {proxy, port} = proxy(peer_port)
    generation = make_ref()
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)

    config = %{
      host: {127, 0, 0, 1},
      port: port,
      generation: generation,
      options: [security: security]
    }

    {:ok, adapter} = DTLS.open(config, self(), 1000)
    assert :ok = DTLS.set_active_once(adapter)

    {:ok, bytes} =
      Codec.encode(%Wotex.CoAP.Message{type: :con, code: 1, message_id: 7, token: "token"})

    assert :ok = DTLS.send(adapter, bytes)
    assert_receive {:request, request}
    send(peer.pid, {:reply, %{request | type: :ack, code: 69, payload: "authenticated"}})
    assert_receive {:record, <<23, _::binary>> = record}
    send(proxy.pid, {:deliver, record})
    assert_receive {:wotex_datagram, ^generation, {:data, {127, 0, 0, 1}, ^port, response}}, 1500
    assert {:ok, %{payload: "authenticated"}} = Codec.decode(response)
    assert :ok = DTLS.set_active_once(adapter)
    send(proxy.pid, {:deliver, record})
    refute_receive {:wotex_datagram, ^generation, {:data, _, _, _}}, 30
    assert :ok = DTLS.close(adapter)
    send(proxy.pid, :close)
    Task.await(proxy)
    close_peer(peer, listener)
  end

  test "WCO-S05 WCO-V12 tampered records fail within the operation deadline and cleanup grace" do
    {peer, listener, peer_port} = peer()
    {proxy, port} = proxy(peer_port)
    {:ok, security} = Security.new(mode: :dtls_psk, identity: "client", key: @key)
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, scheme: :coaps, security: security)
    adapter = :sys.get_state(session.pid).handle
    {:ok, {_, client_port}} = :ssl.sockname(:sys.get_state(adapter.pid).socket)
    task = Task.async(fn -> CoAP.get(%{session | timeout: 200}, "/secure", confirmable: false) end)
    assert_receive {:request, request}
    send(peer.pid, {:reply, %{request | type: :non, code: 69, payload: "unauthenticated"}})
    assert_receive {:record, <<23, _::binary>> = record}
    prefix_size = byte_size(record) - 1
    <<prefix::binary-size(^prefix_size), last>> = record
    send(proxy.pid, {:deliver, <<prefix::binary, Bitwise.bxor(last, 1)>>})
    assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(task, 1000)
    assert :ok = CoAP.disconnect(session)
    assert_socket_free(client_port)
    send(proxy.pid, :close)
    Task.await(proxy)
    close_peer(peer, listener)
  end

  defp proxy(peer_port) do
    test = self()

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(socket)
        send(test, {:proxy_port, port})
        proxy_loop(socket, peer_port, nil, test)
      end)

    assert_receive {:proxy_port, port}
    {task, port}
  end

  defp proxy_loop(socket, peer_port, client_port, test) do
    receive do
      {:udp, ^socket, _, ^peer_port, <<23, _::binary>> = bytes} ->
        send(test, {:record, bytes})
        proxy_loop(socket, peer_port, client_port, test)

      {:udp, ^socket, _, ^peer_port, bytes} ->
        :ok = :gen_udp.send(socket, {127, 0, 0, 1}, client_port, bytes)
        proxy_loop(socket, peer_port, client_port, test)

      {:udp, ^socket, _, port, bytes} ->
        :ok = :gen_udp.send(socket, {127, 0, 0, 1}, peer_port, bytes)
        proxy_loop(socket, peer_port, port, test)

      {:deliver, bytes} ->
        :ok = :gen_udp.send(socket, {127, 0, 0, 1}, client_port, bytes)
        proxy_loop(socket, peer_port, client_port, test)

      :close ->
        :gen_udp.close(socket)
    end
  end

  defp peer do
    {:ok, _} = Application.ensure_all_started(:ssl)
    test = self()

    lookup = fn
      :psk, identity, key ->
        send(test, {:identity, identity})
        if identity == "client", do: {:ok, key}, else: :error
    end

    {:ok, listener} =
      :ssl.listen(0,
        protocol: :dtls,
        versions: [:"dtlsv1.2"],
        ciphers: [@cipher],
        verify: :verify_none,
        user_lookup_fun: {lookup, @key},
        mode: :binary,
        active: false,
        ip: {127, 0, 0, 1},
        log_level: :none,
        reuse_sessions: false
      )

    {:ok, {_, port}} = :ssl.sockname(listener)

    peer =
      Task.async(fn ->
        with {:ok, accepted} <- :ssl.transport_accept(listener, 1000),
             {:ok, socket} <- :ssl.handshake(accepted, 1000) do
          :ok = :ssl.setopts(socket, active: true)
          peer_loop(socket, test)
        else
          {:error, _} -> :ok
        end
      end)

    {peer, listener, port}
  end

  defp peer_loop(socket, test) do
    receive do
      {:ssl, ^socket, bytes} ->
        {:ok, request} = Codec.decode(bytes)
        send(test, {:request, request})
        peer_loop(socket, test)

      {:reply, message} ->
        {:ok, bytes} = Codec.encode(message)
        :ok = :ssl.send(socket, bytes)
        peer_loop(socket, test)

      {:ssl_closed, ^socket} ->
        :ok

      :close ->
        :ssl.close(socket, 100)
    after
      2000 -> :ssl.close(socket, 100)
    end
  end

  defp close_peer(peer, listener) do
    send(peer.pid, :close)
    :ssl.close(listener, 100)
    Task.await(peer, 1500)
  end

  defp assert_socket_free(port),
    do: assert_socket_free(port, System.monotonic_time(:millisecond) + 1000)

  defp assert_socket_free(port, deadline) do
    case :gen_udp.open(port, [:binary]) do
      {:ok, socket} ->
        :gen_udp.close(socket)

      {:error, :eaddrinuse} ->
        assert System.monotonic_time(:millisecond) < deadline

        receive do
        after
          1 -> assert_socket_free(port, deadline)
        end
    end
  end
end
