Code.require_file("../support/libcoap_peer.ex", __DIR__)
Code.require_file("../support/dtls_record_proxy.ex", __DIR__)

defmodule Wotex.CoAP.OSCOREInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Message, NativeBackend, Security, Subscription}
  alias Wotex.CoAP.Test.{DTLSRecordProxy, LibcoapPeer}
  @moduletag :interop
  @moduletag :capture_log
  @recipients Enum.map(1..12, &<<&1>>)

  setup_all do
    peer = LibcoapPeer.verify!()

    backend = %{
      executable: System.fetch_env!("WOTEX_COAP_NATIVE_WORKER"),
      manifest: System.fetch_env!("WOTEX_COAP_NATIVE_MANIFEST")
    }

    assert {:ok, _} = NativeBackend.verify(backend)
    %{executable: peer, backend: backend}
  end

  setup context do
    root = Path.join(System.tmp_dir!(), "wotex-oscore-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root = File.cd!(root, &File.cwd!/0)
    secret = :crypto.strong_rand_bytes(16)

    peer_context = %{
      master_secret: secret,
      master_salt: <<>>,
      sender_id: <<>>,
      recipient_ids: @recipients
    }

    spec =
      Supervisor.child_spec({LibcoapPeer, {context.executable, :oscore, peer_context}},
        id: make_ref(),
        restart: :temporary
      )

    peer = start_supervised!(spec)

    on_exit(fn ->
      if Process.alive?(peer), do: assert(:ok = LibcoapPeer.close(peer))
      File.rm_rf!(root)
    end)

    %{peer: peer, port: LibcoapPeer.plain_endpoint(peer), root: root, secret: secret}
  end

  test "WCO-S06 WCO-V13 same-stack libcoap protects unary methods, whole bodies and discovery",
       context do
    session = connect!(context, <<1>>)
    helper = helper_os_pid(session)
    path = "/wotex-oscore-#{System.unique_integer([:positive])}"
    body = :binary.copy("protected-whole-body-transfer", 1_500)
    assert byte_size(body) > 32_768

    assert {:ok, %Message{code: 69, payload: root}} = CoAP.get(session, "/")
    assert root =~ "libcoap"

    assert {:ok, %Message{code: 65, payload: ^body}} =
             CoAP.put(session, path, body, content_format: 42)

    assert {:ok, %Message{code: 69, payload: ^body}} = CoAP.get(session, path, accept: 42)

    assert {:ok, %Message{code: 68, payload: "changed"}} =
             CoAP.post(session, path, "changed", content_format: :text)

    assert {:ok, %Message{code: 66}} = CoAP.delete(session, path)

    assert {:error, %Error{code: :remote_response, effect: :none, details: %{code: 132}}} =
             CoAP.get(session, path)

    assert {:ok, links} = CoAP.discover(session, %{query: nil})
    assert Enum.any?(links, &(&1.href == "/time"))
    assert Enum.any?(links, &(&1.href == "/example_data"))

    assert :ok = CoAP.disconnect(session)
    refute Process.alive?(session.pid)
    refute os_process_alive?(helper)

    assert {:error, %Error{code: :fresh_context_required}} =
             CoAP.connect(connection_options(context, <<1>>))
  end

  test "WCO-S06 WCO-V13 a mismatched master secret yields no application result", context do
    options =
      connection_options(context, <<2>>, master_secret: :crypto.strong_rand_bytes(16))

    {:ok, session} = CoAP.connect(options)
    helper = helper_os_pid(session)
    monitor = Process.monitor(session.pid)

    assert {:error, %Error{code: :security_handshake_failed, effect: :none}} =
             CoAP.get(session, "/")

    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
    refute os_process_alive?(helper)
    assert {:error, %Error{code: :connection_closed, effect: :none}} = CoAP.get(session, "/")
    assert :ok = CoAP.disconnect(session)

    assert {:error, %Error{code: :fresh_context_required}} = CoAP.connect(options)
  end

  test "WCO-S02 WCO-S06 a 1 MiB protected body completes inside one interaction deadline",
       context do
    session = connect!(context, <<7>>, timeout: 60_000)
    path = "/wotex-oscore-mebibyte"
    body = :crypto.strong_rand_bytes(1_048_576)

    try do
      assert {:ok, %Message{code: 65, payload: ^body}} =
               CoAP.put(session, path, body, content_format: :octet_stream)

      assert {:ok, %Message{code: 69, payload: ^body}} = CoAP.get(session, path)
    after
      assert :ok = CoAP.disconnect(session)
    end
  end

  test "WCO-S03 WCO-S06 same-stack protected Observe delivers fresh changes and cancels its token",
       context do
    path = "/wotex-observe-#{System.unique_integer([:positive])}"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)
    session = connect!(context, <<3>>)
    helper = helper_os_pid(session)

    try do
      assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "10", content_format: :text)

      assert {:ok, %Subscription{reference: reference} = handle} =
               CoAP.subscribe(session, %{path: path})

      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "10"}, first}}, 5_000
      assert first.code == 69 and is_integer(first.observe)

      assert {:error, %Error{code: :observation_active}} = CoAP.get(session, "/")

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "11", content_format: :text)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "11"}, second}}, 5_000
      assert second.observe != first.observe

      large = :binary.copy("streamed-notification", 2_000)
      assert byte_size(large) > 32_768

      assert {:ok, %Message{code: 68}} =
               CoAP.put(writer, path, large, content_format: :octet_stream)

      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: ^large}, third}}, 5_000
      assert third.observe != second.observe

      assert :ok = CoAP.unsubscribe(session, handle)
      assert :ok = CoAP.unsubscribe(session, handle)
      refute Process.alive?(session.pid)
      refute os_process_alive?(helper)
      assert_subscriptions(context.peer, %{created: 1, removed: 1})

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "12", content_format: :text)
      refute_receive {:wotex_coap, ^reference, _}, 300
    after
      CoAP.disconnect(writer)
    end
  end

  test "WCO-C03 WCO-V09 WCO-V15 receiver death releases the production helper and peer observer",
       context do
    path = "/wotex-receiver-#{System.unique_integer([:positive])}"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)
    session = connect!(context, <<4>>)
    helper = helper_os_pid(session)
    test = self()

    try do
      assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "20", content_format: :text)

      receiver =
        spawn(fn ->
          receive do
            {:wotex_coap, _, {:ok, message, _}} -> send(test, {:initial, message.payload})
          end

          Process.sleep(:infinity)
        end)

      assert {:ok, %Subscription{}} = CoAP.subscribe(session, %{path: path, receiver: receiver})
      assert_receive {:initial, "20"}, 5_000

      monitor = Process.monitor(session.pid)
      Process.exit(receiver, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
      refute os_process_alive?(helper)
      assert_subscriptions(context.peer, %{created: 1, removed: 1})
    after
      CoAP.disconnect(writer)
    end
  end

  test "WCO-C03 WCO-V15 owner death during a protected exchange releases the helper", context do
    test = self()

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, session} = CoAP.connect(connection_options(context, <<5>>, owner: owner))
    helper = helper_os_pid(session)
    monitor = Process.monitor(session.pid)

    caller =
      spawn(fn ->
        send(test, {:result, CoAP.get(session, "/async?delay=3")})
      end)

    Process.sleep(200)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
    refute os_process_alive?(helper)
    assert_receive {:result, {:error, %Error{effect: :none}}}, 1_100
    refute Process.alive?(caller)
  end

  test "WCO-S01 WCO-S06 uncorrelated protected and plaintext responses cannot end the active exchange",
       context do
    proxy = start_proxy(context, :hold_all)
    session = connect!(Map.put(context, :port, DTLSRecordProxy.endpoint(proxy)), <<8>>)
    caller = Task.async(fn -> CoAP.get(session, "/") end)
    assert_receive {:held_datagram, ^proxy, first}, 5_000

    # A confirmable 2.05 response with an empty OSCORE option and a token that
    # no request of this generation used, as a peer retransmits toward a reused
    # endpoint after an earlier client exits.
    <<_::16, mid::16, _::binary>> = first
    stale_mid = rem(mid + 1_000, 65_536)
    token = :crypto.strong_rand_bytes(8)
    stale = <<1::2, 0::2, 8::4, 69, stale_mid::16, token::binary, 0x90, 0xFF>>
    :ok = DTLSRecordProxy.deliver(proxy, stale <> :crypto.strong_rand_bytes(16))

    # A plaintext 2.05 with another unused token is equally uncorrelated.
    plain_token = :crypto.strong_rand_bytes(8)
    plain = <<1::2, 0::2, 8::4, 69, rem(stale_mid + 1, 65_536)::16, plain_token::binary, 0xFF>>
    :ok = DTLSRecordProxy.deliver(proxy, plain <> "forged")
    :ok = DTLSRecordProxy.deliver(proxy, first)

    assert {:ok, %Message{code: 69, payload: root}} = forward_until(proxy, caller)
    assert root =~ "libcoap"
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-S01 WCO-S06 a malformed datagram cannot end the active protected exchange",
       context do
    proxy = start_proxy(context, :hold_all)
    session = connect!(Map.put(context, :port, DTLSRecordProxy.endpoint(proxy)), <<10>>)
    caller = Task.async(fn -> CoAP.get(session, "/") end)
    assert_receive {:held_datagram, ^proxy, first}, 5_000

    # The request's own MID and token with an option whose declared length runs
    # past the datagram, which libcoap's parser rejects before correlation.
    <<_::4, token_length::4, _, mid::16, rest::binary>> = first
    token = binary_part(rest, 0, token_length)
    malformed = <<1::2, 2::2, token_length::4, 69, mid::16, token::binary, 0xD5, 0x01>>
    :ok = DTLSRecordProxy.deliver(proxy, malformed)
    :ok = DTLSRecordProxy.deliver(proxy, first)

    assert {:ok, %Message{code: 69, payload: root}} = forward_until(proxy, caller)
    assert root =~ "libcoap"
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-C03 WCO-S03 exit cancellation acknowledges the peer's confirmable response",
       context do
    path = "/wotex-exit-cancel-3012"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)
    proxy = start_proxy(context, :trace)
    session = connect!(Map.put(context, :port, DTLSRecordProxy.endpoint(proxy)), <<9>>)
    test = self()

    try do
      assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "30", content_format: :text)

      receiver =
        spawn(fn ->
          receive do
            {:wotex_coap, _, {:ok, _, _}} -> send(test, :initial)
          end

          Process.sleep(:infinity)
        end)

      assert {:ok, %Subscription{}} = CoAP.subscribe(session, %{path: path, receiver: receiver})
      assert_receive :initial, 5_000
      helper = helper_os_pid(session)
      drain_trace(proxy)
      monitor = Process.monitor(session.pid)
      Process.exit(receiver, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
      refute os_process_alive?(helper)
      assert_subscriptions(context.peer, %{created: 1, removed: 1})

      # Datagrams the helper exchanged after receiver death: every confirmable
      # message from the peer has an acknowledgment or reset with its MID.
      trace = drain_trace(proxy)

      peer_confirmables =
        for {:to_client, <<1::2, 0::2, _::4, _, mid::16, _::binary>>} <- trace, do: mid

      acknowledged =
        for {:to_server, <<1::2, type::2, 0::4, 0, mid::16>>} <- trace, type in [2, 3], do: mid

      assert {:to_server, _} = List.first(trace)
      assert peer_confirmables -- acknowledged == []
    after
      CoAP.disconnect(writer)
    end
  end

  test "WCO-S03 WCO-V13 replayed, duplicate and stale protected notifications deliver no value",
       context do
    path = "/wotex-replay-#{System.unique_integer([:positive])}"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)
    proxy = start_proxy(context, :trace)
    session = connect!(Map.put(context, :port, DTLSRecordProxy.endpoint(proxy)), <<11>>)

    try do
      assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "40", content_format: :text)
      assert {:ok, %Subscription{reference: reference}} = CoAP.subscribe(session, path)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "40"}, _}}, 5_000
      drain_trace(proxy)

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "41", content_format: :text)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "41"}, _}}, 5_000

      [notification | _] =
        for {:to_client, <<1::2, 0::2, _::4, 69, _::binary>> = bytes} <- drain_trace(proxy),
            do: bytes

      # The same authenticated ciphertext three more times, back to back.
      for _ <- 1..3, do: :ok = DTLSRecordProxy.deliver(proxy, notification)
      refute_receive {:wotex_coap, ^reference, _}, 500

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "42", content_format: :text)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "42"}, _}}, 5_000

      # After 42, the authenticated 41 is older than the delivered serial.
      for _ <- 1..3, do: :ok = DTLSRecordProxy.deliver(proxy, notification)
      refute_receive {:wotex_coap, ^reference, _}, 500

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "43", content_format: :text)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "43"}, _}}, 5_000
    after
      CoAP.disconnect(session)
      CoAP.disconnect(writer)
    end
  end

  test "WCO-S03 WCO-V13 tampered and unprotected notifications do not cancel the observation",
       context do
    path = "/wotex-tamper-#{System.unique_integer([:positive])}"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)
    proxy = start_proxy(context, :hold_all)
    session = connect!(Map.put(context, :port, DTLSRecordProxy.endpoint(proxy)), <<12>>)

    try do
      assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "50", content_format: :text)
      test = self()
      caller = Task.async(fn -> CoAP.subscribe(session, %{path: path, receiver: test}) end)
      assert {:ok, %Subscription{reference: reference}} = forward_until(proxy, caller)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "50"}, _}}, 5_000

      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "51", content_format: :text)
      notification = held_notification(proxy)

      <<_::4, token_length::4, _, mid::16, token::binary-size(token_length), _::binary>> =
        notification

      # An unprotected 2.05 with the observation token, Observe and a payload, then
      # the genuine notification with its authentication tag altered. Neither is
      # acknowledged, so the peer retransmits the genuine notification.
      unprotected =
        <<1::2, 0::2, token_length::4, 69, rem(mid + 7, 65_536)::16, token::binary, 0x61, 9, 0xFF,
          "forged">>

      :ok = DTLSRecordProxy.deliver(proxy, unprotected)
      tag_byte = binary_part(notification, byte_size(notification) - 1, 1)
      <<last>> = tag_byte

      tampered =
        binary_part(notification, 0, byte_size(notification) - 1) <> <<Bitwise.bxor(last, 1)>>

      :ok = DTLSRecordProxy.deliver(proxy, tampered)
      refute_receive {:wotex_coap, ^reference, _}, 500

      # libcoap acknowledges the refused confirmable message at the message layer,
      # so value 51 is lost as if the datagram were dropped. The observation stays
      # active and delivers the next change.
      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, "52", content_format: :text)
      forward_until_value(proxy, reference, "52")
    after
      CoAP.disconnect(session)
      CoAP.disconnect(writer)
    end
  end

  test "WCO-S06 WCO-I02 Runtime ConsumedThing uses the production helper for protected calls",
       context do
    path = "wotex-runtime-#{System.unique_integer([:positive])}"
    {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: context.port, timeout: 5_000)

    try do
      assert {:ok, %Message{code: 65}} =
               CoAP.put(writer, "/" <> path, ~s({"value":1}), content_format: :json)

      {:ok, profile} = CoAP.profile(:oscore)
      security = security(context, <<6>>)

      {:ok, td} =
        Wotex.ThingDescription.from_map(%{
          "@context" => "https://www.w3.org/2022/wot/td/v1.1",
          "title" => "Same-stack OSCORE Thing",
          "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
          "security" => ["none"],
          "properties" => %{
            "reading" => %{
              "forms" => [
                %{
                  "href" => "coap://127.0.0.1:#{context.port}/#{path}",
                  "contentType" => "application/json",
                  "op" => ["readproperty"]
                }
              ]
            }
          }
        })

      {:ok, thing} =
        Wotex.Runtime.ConsumedThing.new(td,
          profiles: [profile],
          transports: %{
            coap_oscore: {Wotex.CoAP.Transport, [timeout: 5_000, native_backend: context.backend]}
          },
          credentials: {__MODULE__.Credentials, security}
        )

      {:ok, runtime} = Wotex.Runtime.Context.new(request_id: "same-stack-oscore-read")

      assert {:ok, result} =
               Wotex.Runtime.ConsumedThing.read_property(thing, "reading", runtime)

      assert result.payload == %{"value" => 1}
      assert result.metadata.code == 69
    after
      CoAP.disconnect(writer)
    end
  end

  defmodule Credentials do
    @moduledoc false

    @behaviour Wotex.Runtime.Credentials

    @impl Wotex.Runtime.Credentials
    def resolve(_, _, _, credential), do: {:ok, credential}
  end

  defp start_proxy(context, mode) do
    start_supervised!(
      Supervisor.child_spec({DTLSRecordProxy, {context.port, self(), mode}},
        id: make_ref(),
        restart: :temporary
      )
    )
  end

  defp forward_until(proxy, caller) do
    receive do
      {:held_datagram, ^proxy, bytes} ->
        :ok = DTLSRecordProxy.deliver(proxy, bytes)
        forward_until(proxy, caller)

      {ref, result} when ref == caller.ref ->
        Process.demonitor(ref, [:flush])
        result
    after
      5_000 -> flunk("protected exchange did not complete through the proxy")
    end
  end

  defp held_notification(proxy) do
    receive do
      {:held_datagram, ^proxy, <<1::2, 0::2, _::4, 69, _::binary>> = bytes} ->
        bytes

      {:held_datagram, ^proxy, bytes} ->
        :ok = DTLSRecordProxy.deliver(proxy, bytes)
        held_notification(proxy)
    after
      5_000 -> flunk("the peer sent no confirmable notification")
    end
  end

  defp forward_until_value(proxy, reference, payload) do
    receive do
      {:held_datagram, ^proxy, bytes} ->
        :ok = DTLSRecordProxy.deliver(proxy, bytes)
        forward_until_value(proxy, reference, payload)

      {:wotex_coap, ^reference, {:ok, %Message{payload: ^payload}, _}} ->
        :ok

      {:wotex_coap, ^reference, other} ->
        flunk("observation delivered #{inspect(other)} instead of #{inspect(payload)}")
    after
      10_000 -> flunk("observation did not deliver #{inspect(payload)}")
    end
  end

  defp drain_trace(proxy, trace \\ []) do
    receive do
      {:proxy_datagram, ^proxy, direction, bytes} ->
        drain_trace(proxy, [{direction, bytes} | trace])
    after
      50 -> Enum.reverse(trace)
    end
  end

  defp connect!(context, sender, options \\ []) do
    assert {:ok, session} = CoAP.connect(connection_options(context, sender, options))
    session
  end

  defp connection_options(context, sender, overrides \\ []) do
    {owner, overrides} = Keyword.pop(overrides, :owner)
    {timeout, overrides} = Keyword.pop(overrides, :timeout, 5_000)

    [
      host: "127.0.0.1",
      port: context.port,
      timeout: timeout,
      security: security(context, sender, overrides),
      native_backend: context.backend
    ] ++ if(owner, do: [owner: owner], else: [])
  end

  defp security(context, sender, overrides \\ []) do
    store = Path.join(context.root, "store-" <> Base.encode16(sender, case: :lower))
    File.mkdir_p!(store)
    File.chmod!(store, 0o700)

    {:ok, security} =
      Security.new(
        Keyword.merge(
          [
            mode: :oscore,
            master_secret: context.secret,
            master_salt: <<>>,
            sender_id: sender,
            recipient_id: <<>>,
            context_store: store
          ],
          overrides
        )
      )

    security
  end

  defp helper_os_pid(session) do
    %{os_pid: os_pid} = :sys.get_state(session.pid)
    assert is_integer(os_pid)
    os_pid
  end

  defp os_process_alive?(os_pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(os_pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
      )

    status == 0
  end

  defp assert_subscriptions(peer, expected, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 2_000
    actual = LibcoapPeer.subscriptions(peer)

    cond do
      actual == expected ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        assert actual == expected

      true ->
        Process.sleep(20)
        assert_subscriptions(peer, expected, deadline)
    end
  end
end
