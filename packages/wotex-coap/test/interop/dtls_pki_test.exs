Code.require_file("../support/libcoap_peer.ex", __DIR__)
Code.require_file("../support/dtls_record_proxy.ex", __DIR__)
Code.require_file("../support/runtime_capture.ex", __DIR__)
Code.require_file("../support/runtime_security_credentials.ex", __DIR__)

defmodule Wotex.CoAP.IndependentDTLSTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Message}
  alias Wotex.CoAP.Datagram.DTLS
  alias Wotex.CoAP.Test.{DTLSRecordProxy, LibcoapPeer, RuntimeCapture, RuntimeSecurityCredentials}
  alias Wotex.Runtime.{ConsumedThing, Context, Retry, Subscription}
  @moduletag :interop
  @moduletag :capture_log

  setup_all do
    %{executable: LibcoapPeer.verify!()}
  end

  test "WCO-S05 WCO-V12 both exact cipher profiles complete independent blockwise operations", c do
    for mode <- [:psk, :pki] do
      with_peer(c, mode, &exchange_cycle(&1, mode))
    end
  end

  test "WCO-S05 WCO-V12 independent PKI accepts exact DNS/IP SAN and both private-key encodings",
       c do
    with_peer(c, :pki, fn port ->
      for identity <- [{:dns, "fixture.test"}, {:ip, {127, 0, 0, 1}}],
          key <- ["client-key.der", "client-pkcs8.der"] do
        credentials =
          LibcoapPeer.pki_security(
            server_identity: identity,
            private_key: LibcoapPeer.fixture(key)
          )

        with_session(port, credentials, fn session ->
          assert {:ok, %{code: 69}} = CoAP.get(session, "/")
        end)
      end
    end)
  end

  test "WCO-S05 WCO-V12 independent certificate, usage, trust and revocation faults fail closed",
       c do
    valid = LibcoapPeer.fixture("valid-crl.der")
    prefix_size = byte_size(valid) - 1
    <<prefix::binary-size(^prefix_size), last>> = valid
    tampered = <<prefix::binary, Bitwise.bxor(last, 1)>>

    for {certificate, overrides} <- [
          {"expired", []},
          {"wrong-san", []},
          {"cn-only", []},
          {"wildcard", [server_identity: {:dns, "sensor.fixture.test"}]},
          {"wrong-ku", []},
          {"wrong-eku", []},
          {"critical", []},
          {"server", [trust_roots: [LibcoapPeer.fixture("untrusted-root.der")]]},
          {"revoked", [crls: [LibcoapPeer.fixture("revoked-crl.der")]]},
          {"server", [crls: [LibcoapPeer.fixture("expired-crl.der")]]},
          {"server", [crls: [tampered]]}
        ] do
      with_peer(c, :pki, certificate, fn port ->
        reject_connection(port, LibcoapPeer.pki_security(overrides))
      end)
    end
  end

  test "WCO-S05 WCO-V12 independent PSK identity/key and security-mode mismatches cannot succeed",
       c do
    for {mode, credentials} <- [
          {:psk, LibcoapPeer.security(:psk, identity: "wrong")},
          {:psk, LibcoapPeer.security(:psk, key: "wrong-key-1234567")},
          {:psk, LibcoapPeer.pki_security()},
          {:pki, LibcoapPeer.security(:psk)}
        ] do
      with_peer(c, mode, fn port ->
        reject_connection(port, credentials)
      end)
    end
  end

  test "WCO-S05 WCO-V12 independent PSK/PKI records authenticate once and reject replay", c do
    for mode <- [:psk, :pki] do
      with_peer(c, mode, fn peer_port ->
        with_proxy(peer_port, fn proxy, port ->
          generation = make_ref()

          config = %{
            host: {127, 0, 0, 1},
            port: port,
            generation: generation,
            options: [security: security(mode)]
          }

          assert {:ok, adapter} = DTLS.open(config, self(), 1000)

          try do
            for message_id <- [7, 8] do
              assert :ok = DTLS.set_active_once(adapter)
              request = %Message{type: :con, code: 1, message_id: message_id, token: "token"}
              assert {:ok, bytes} = Codec.encode(request)
              assert :ok = DTLS.send(adapter, bytes)
              assert_receive {:dtls_record, ^proxy, record}, 1500
              assert :ok = DTLSRecordProxy.deliver(proxy, record)

              assert_receive {:wotex_datagram, ^generation, {:data, {127, 0, 0, 1}, ^port, reply}},
                             1500

              assert {:ok, %{code: 69, message_id: ^message_id, payload: body}} =
                       Codec.decode(reply)

              assert byte_size(body) > 0
              assert :ok = DTLS.set_active_once(adapter)
              assert :ok = DTLSRecordProxy.deliver(proxy, record)
              refute_receive {:wotex_datagram, ^generation, {:data, _, _, _}}, 30
            end
          after
            assert :ok = DTLS.close(adapter)
          end
        end)
      end)
    end
  end

  test "WCO-S05 WCO-V12 independent PSK/PKI ciphertext corruption returns no plaintext value", c do
    for mode <- [:psk, :pki] do
      with_peer(c, mode, fn peer_port ->
        with_proxy(peer_port, fn proxy, port ->
          session = connect(port, security(mode))

          try do
            task =
              Task.async(fn -> CoAP.get(%{session | timeout: 200}, "/", confirmable: false) end)

            assert_receive {:dtls_record, ^proxy, record}, 1000
            size = byte_size(record) - 1
            <<prefix::binary-size(^size), last>> = record
            assert :ok = DTLSRecordProxy.deliver(proxy, <<prefix::binary, Bitwise.bxor(last, 1)>>)
            assert {:error, %Error{effect: :none}} = Task.await(task, 1200)
          after
            close_session(session)
          end
        end)
      end)
    end
  end

  test "WCO-S03 WCO-S05 WCO-V15 independent PSK/PKI Observe retains authenticated cancellation",
       c do
    for mode <- [:psk, :pki] do
      with_peer(c, mode, &observe_cycle(&1, mode))
    end
  end

  test "WCO-I03 WCO-I04 independent secure Runtime calls preserve each representation and identity",
       c do
    for mode <- [:psk, :pki],
        {media, values} <- [
          {"application/json", [false, 0, nil, [], %{"reading" => [1, "é"]}]},
          {"application/octet-stream", [<<0, 255, 1>>, :binary.copy(<<1, 255>>, 1500)]},
          {"text/plain;charset=utf-8", ["temperature: 20 °C", String.duplicate("é", 1500)]}
        ] do
      with_peer(c, mode, fn port -> runtime_unary(port, mode, media, values) end)
    end
  end

  test "WCO-I04 WCO-V12 independent authentication failures cannot dispatch Runtime mutations",
       c do
    for {mode, certificate, credentials} <- [
          {:psk, "server", LibcoapPeer.security(:psk, key: "wrong-key-1234567")},
          {:pki, "wrong-san", security(:pki)},
          {:pki, "revoked",
           LibcoapPeer.pki_security(crls: [LibcoapPeer.fixture("revoked-crl.der")])}
        ] do
      with_peer(c, mode, certificate, fn port -> runtime_rejection(port, credentials) end)
    end
  end

  test "WCO-I05 WCO-V15 independent secure Runtime Property and Event streams close the original route",
       c do
    for mode <- [:psk, :pki], kind <- [:property, :event], closure <- [:stop, :receiver_death] do
      with_peer(c, mode, fn port -> runtime_stream(port, mode, kind, closure) end)
    end
  end

  defp runtime_unary(peer_port, mode, media, values) do
    for value <- values,
        custody <- [:immediate, :configured],
        operation <- [:writeproperty, :readproperty, :invokeaction] do
      with_proxy(peer_port, :forward, fn _, port ->
        credentials = security(mode)
        options = if custody == :configured, do: [security: credentials], else: []
        immediate = if custody == :immediate, do: credentials
        transport = {RuntimeCapture, {self(), [timeout: 3000] ++ options}}
        consumed = runtime_thing(port, media, transport, immediate)
        request_id = "#{mode}-#{custody}-#{operation}"
        deadline = System.monotonic_time(:millisecond) + 3000
        {:ok, context} = Context.new(request_id: request_id, deadline: deadline)
        assert {:ok, result} = runtime_call(consumed, operation, value, context)
        assert result.payload === value
        assert result.operation == operation and result.request_id == request_id
        assert result.status == :ok
        assert result.metadata.code in if(operation == :readproperty, do: [69], else: [65, 68])
        assert_receive {:selected_request, selected}
        assert_receive {:callback_owner, _}
        assert selected.resolved_href == "coaps://127.0.0.1:#{port}/value"
        assert selected.deadline == deadline and selected.request_id == request_id
        assert Wotex.Form.to_map(selected.form)["example:hint"] == %{"values" => [nil, false, 0]}
      end)
    end
  end

  defp runtime_rejection(peer_port, credentials) do
    with_proxy(peer_port, fn _, port ->
      consumed =
        runtime_thing(port, "application/json", {CoAP.Transport, [timeout: 600]}, credentials)

      {:ok, context} = Context.new(request_id: "rejected-mutation")
      assert {:error, error} = ConsumedThing.write_property(consumed, "value", false, context)
      assert error.details.cause.code in [:security_handshake_failed, :timeout, :deadline_exceeded]
      assert Retry.decision(:writeproperty, error, attempt: 1, max_attempts: 2) == :stop
      refute inspect(error) =~ "wrong-key"
    end)
  end

  defp runtime_stream(peer_port, mode, kind, closure) do
    with_session(peer_port, security(mode), fn writer ->
      assert {:ok, %{code: 65}} = CoAP.put(writer, "/value", "false", content_format: 50)

      with_proxy(peer_port, :forward, fn _, port ->
        runtime_stream_cycle(port, mode, kind, closure, writer)
      end)
    end)
  end

  defp runtime_stream_cycle(port, mode, kind, closure, writer) do
    transport = {CoAP.Transport, [timeout: 3000, security: security(mode), renew: false]}
    consumed = runtime_thing(port, "application/json", transport, nil)
    {:ok, context} = Context.new(request_id: "independent-stream")
    parent = self()
    receiver = spawn_link(fn -> relay_reports(parent) end)
    on_exit(fn -> if Process.alive?(receiver), do: send(receiver, :done) end)

    function =
      if kind == :property, do: :observation_child_spec, else: :event_subscription_child_spec

    {:ok, spec} =
      apply(ConsumedThing, function, [
        consumed,
        "value",
        context,
        [
          id: make_ref(),
          receiver: receiver,
          restart: :temporary,
          max_queue_length: 1000,
          overflow: :stop
        ]
      ])

    owner = start_supervised!(spec)
    monitor = Process.monitor(owner)
    assert_receive {:wotex_runtime, _, {:ok, false, %{code: 69, observe: initial}}}, 1500
    assert {:ok, %{code: 68}} = CoAP.put(writer, "/value", "0", content_format: 50)
    assert_receive {:wotex_runtime, _, {:ok, 0, %{code: 69, observe: updated}}}, 1500
    assert updated != initial

    case closure do
      :stop -> assert :ok = Subscription.stop(owner)
      :receiver_death -> send(receiver, :done)
    end

    assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1000
    assert {:ok, %{code: 68}} = CoAP.put(writer, "/value", "true", content_format: 50)
    refute_receive {:wotex_runtime, _, _}, 50
    send(receiver, :done)
  end

  defp relay_reports(parent) do
    receive do
      :done ->
        :ok

      message ->
        send(parent, message)
        relay_reports(parent)
    end
  end

  defp runtime_call(consumed, :readproperty, _, context),
    do: ConsumedThing.read_property(consumed, "value", context)

  defp runtime_call(consumed, :writeproperty, value, context),
    do: ConsumedThing.write_property(consumed, "value", value, context)

  defp runtime_call(consumed, :invokeaction, value, context),
    do: ConsumedThing.invoke_action(consumed, "value", value, context)

  defp runtime_thing(port, media, transport, immediate) do
    form = %{
      "href" => "value",
      "contentType" => media,
      "example:hint" => %{"values" => [nil, false, 0]}
    }

    stop = %{"href" => "coaps://127.0.0.1:1/unused"}

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "base" => "coaps://127.0.0.1:#{port}/",
        "title" => "Independent secure Thing",
        "securityDefinitions" => %{"configured" => %{"scheme" => "nosec"}},
        "security" => ["configured"],
        "properties" => %{
          "value" => %{
            "observable" => true,
            "forms" => [
              form,
              Map.put(form, "op", "observeproperty"),
              Map.put(stop, "op", "unobserveproperty")
            ]
          }
        },
        "actions" => %{"value" => %{"forms" => [form]}},
        "events" => %{
          "value" => %{
            "forms" => [
              Map.put(form, "op", "subscribeevent"),
              Map.put(stop, "op", "unsubscribeevent")
            ]
          }
        }
      })

    {:ok, profile} = CoAP.profile(:dtls)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{coaps: transport},
        credentials: {RuntimeSecurityCredentials, immediate}
      )

    consumed
  end

  defp exchange_cycle(port, mode) do
    with_session(port, security(mode), fn session ->
      socket = :sys.get_state(:sys.get_state(session.pid).handle.pid).socket
      {:ok, information} = :ssl.connection_information(socket, [:protocol, :selected_cipher_suite])
      assert information[:protocol] == :"dtlsv1.2"

      assert information[:selected_cipher_suite] == %{
               key_exchange: if(mode == :psk, do: :psk, else: :ecdhe_rsa),
               cipher: :aes_128_gcm,
               mac: :aead,
               prf: :sha256
             }

      body = :binary.copy("independent-authenticated-body", 100)
      assert {:ok, %{code: 69, payload: root}} = CoAP.get(session, "/")
      assert byte_size(root) > 0

      assert {:ok, %{code: 65, payload: ^body}} =
               CoAP.put(session, "/value", body, content_format: 42)

      assert {:ok, %{code: 69, payload: ^body}} = CoAP.get(session, "/value", accept: 42)
      assert {:ok, %{code: 66}} = CoAP.delete(session, "/value")

      assert {:error, %Error{code: :remote_response, details: %{code: 132}}} =
               CoAP.get(session, "/value")
    end)
  end

  defp observe_cycle(port, mode) do
    with_session(port, security(mode), fn writer ->
      with_session(port, security(mode), [observation_options: [accept: 42]], fn observer ->
        assert {:ok, %{code: 65}} = CoAP.put(writer, "/reading", "initial", content_format: 42)

        assert {:ok, handle} =
                 CoAP.subscribe(observer, %{path: "/reading", receiver: self(), renew: false})

        reference = handle.reference
        assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "initial"}, _}}, 1000
        assert {:ok, %{code: 68}} = CoAP.put(writer, "/reading", "updated", content_format: 42)
        assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "updated"}, _}}, 1500
        assert :ok = CoAP.unsubscribe(observer, handle)
        assert :ok = CoAP.unsubscribe(observer, handle)

        assert {:ok, %{code: 68}} =
                 CoAP.put(writer, "/reading", "after-cancel", content_format: 42)

        refute_receive {:wotex_coap, ^reference, _}, 50
        assert {:ok, %{code: 66}} = CoAP.delete(writer, "/reading")
      end)
    end)
  end

  defp with_peer(c, mode, certificate \\ "server", fun) do
    spec =
      Supervisor.child_spec({LibcoapPeer, {c.executable, mode, certificate}},
        id: make_ref(),
        restart: :temporary
      )

    peer = start_supervised!(spec)

    try do
      fun.(LibcoapPeer.endpoint(peer))
    after
      assert :ok = LibcoapPeer.close(peer)
    end
  end

  defp security(:psk), do: LibcoapPeer.security(:psk)
  defp security(:pki), do: LibcoapPeer.pki_security()

  defp reject_connection(peer_port, credentials) do
    with_proxy(peer_port, fn proxy, port ->
      assert {:error, %Error{code: code, effect: :none}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 port: port,
                 scheme: :coaps,
                 security: credentials,
                 timeout: 600
               )

      assert code in [:security_handshake_failed, :timeout]
      refute_received {:dtls_record, ^proxy, _}
    end)
  end

  defp with_proxy(peer_port, mode \\ :hold, fun) do
    spec =
      Supervisor.child_spec({DTLSRecordProxy, {peer_port, self(), mode}},
        id: make_ref(),
        restart: :temporary
      )

    proxy = start_supervised!(spec)

    try do
      fun.(proxy, DTLSRecordProxy.endpoint(proxy))
    after
      assert %{plaintext: 0, records: records, port: port, client_port: client_port} =
               DTLSRecordProxy.close(proxy)

      assert records > 0
      assert_port_free(port)
      assert_port_free(client_port)
    end
  end

  defp with_session(peer_port, credentials, options \\ [], fun) do
    with_proxy(peer_port, :forward, fn _, port ->
      session = connect(port, credentials, options)

      try do
        fun.(session)
      after
        close_session(session)
      end
    end)
  end

  defp assert_port_free(port),
    do: assert_port_free(port, System.monotonic_time(:millisecond) + 1000)

  defp assert_port_free(port, deadline) do
    case :gen_udp.open(port, [:binary, ip: {127, 0, 0, 1}]) do
      {:ok, socket} ->
        :gen_udp.close(socket)

      {:error, :eaddrinuse} ->
        assert System.monotonic_time(:millisecond) < deadline

        receive do
        after
          1 -> assert_port_free(port, deadline)
        end
    end
  end

  defp connect(port, security, options \\ []) do
    assert {:ok, session} =
             CoAP.connect(
               [host: "127.0.0.1", port: port, scheme: :coaps, security: security, timeout: 3000] ++
                 options
             )

    session
  end

  defp close_session(session) do
    monitor = Process.monitor(session.pid)
    assert :ok = CoAP.disconnect(session)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :ok = CoAP.disconnect(session)
  end
end
