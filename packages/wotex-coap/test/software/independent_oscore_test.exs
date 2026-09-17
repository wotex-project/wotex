Code.require_file("../support/californium_peer.ex", __DIR__)
Code.require_file("../support/oscore_relay.ex", __DIR__)

defmodule Wotex.CoAP.IndependentOSCORETest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Message, NativeBackend, Subscription}
  alias Wotex.CoAP.Test.{CaliforniumPeer, OSCORERelay}

  @moduletag :interop
  @moduletag :software
  @moduletag :capture_log

  setup_all do
    {java, archive} = CaliforniumPeer.verify!()

    backend = %{
      executable: System.fetch_env!("WOTEX_COAP_NATIVE_WORKER"),
      manifest: System.fetch_env!("WOTEX_COAP_NATIVE_MANIFEST")
    }

    assert {:ok, _} = NativeBackend.verify(backend)
    %{backend: backend, java: java, archive: archive}
  end

  setup context do
    root = Path.join(System.tmp_dir!(), "wotex-independent-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root = File.cd!(root, &File.cwd!/0)

    spec =
      Supervisor.child_spec({CaliforniumPeer, {context.java, context.archive}},
        id: make_ref(),
        restart: :temporary
      )

    peer = start_supervised!(spec)

    on_exit(fn ->
      if Process.alive?(peer), do: assert(:ok = CaliforniumPeer.close(peer))
      File.rm_rf!(root)
    end)

    Map.merge(context, %{peer: peer, port: CaliforniumPeer.endpoint(peer), root: root})
  end

  test "WCO-S06 WCO-V02 an independent OSCORE stack protects unary methods and discovery",
       context do
    session = connect!(context)

    assert {:ok, %Message{code: 69, payload: payload}} = CoAP.get(session, "/oscore")
    assert String.starts_with?(payload, "OSCORE Resource")
    assert payload =~ "Code: 1 (GET)"

    assert {:ok, %Message{code: 65, options: options}} =
             CoAP.post(session, "/oscore", "independent", content_format: :text)

    assert for({8, value} <- options, do: value) == ["location1", "location2", "location3"]

    assert {:ok, %Message{code: 68}} =
             CoAP.put(session, "/oscore", "independent", content_format: :text)

    assert {:ok, %Message{code: 66}} = CoAP.delete(session, "/oscore")
    assert {:ok, %Message{code: 69, payload: links}} = CoAP.get(session, "/.well-known/core")
    assert links =~ "</oscore>;osc"
    assert {:ok, :healthy} = CoAP.health_check(session)
  end

  test "WCO-S06 WCO-V04 an independent OSCORE stack transfers blockwise bodies both ways",
       context do
    session = connect!(context)

    assert {:ok, %Message{code: 69, payload: large}} = CoAP.get(session, "/large")
    assert byte_size(large) == 1280

    body = :binary.copy("independent-block-", 40)
    assert byte_size(body) > 64

    assert {:ok, %Message{code: 68}} =
             CoAP.put(session, "/large-update", body, content_format: :text)

    assert {:ok, %Message{code: 69, payload: ^body}} = CoAP.get(session, "/large-update")
  end

  test "WCO-S06 WCO-V05 WCO-V09 an independent OSCORE stack observes and stops on cancellation",
       context do
    {session, relay} = connect_through_relay!(context, :forward)
    test_pid = self()

    assert {:ok, %Subscription{reference: reference} = handle} =
             CoAP.subscribe(session, %{
               path: "/obs",
               receiver: test_pid,
               observation_kind: :property
             })

    observations = for _ <- 1..3, do: notification!(reference)
    assert Enum.map(observations, & &1.observe) == Enum.sort(Enum.map(observations, & &1.observe))
    assert Enum.uniq(Enum.map(observations, & &1.observe)) == Enum.map(observations, & &1.observe)
    assert Enum.all?(observations, &(&1.code == 69 and &1.max_age == 5))
    assert Enum.all?(observations, &(byte_size(&1.payload) > 0))

    assert :ok = CoAP.unsubscribe(session, handle)
    Process.sleep(2_500)
    settled = OSCORERelay.counts(relay)
    Process.sleep(2_500)
    assert OSCORERelay.counts(relay).to_client == settled.to_client
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-S06 WCO-V13 an independent OSCORE stack's replayed response is answered once",
       context do
    {session, relay} = connect_through_relay!(context, {:duplicate, 1})

    assert {:ok, %Message{code: 69, payload: payload}} = CoAP.get(session, "/oscore")
    assert String.starts_with?(payload, "OSCORE Resource")
    assert {:ok, %Message{code: 69}} = CoAP.get(session, "/test")

    # The peer answered twice and the relay delivered the first answer twice;
    # the replay neither produced a second result nor a client retransmission.
    assert %{to_peer: 2, to_client: 2, delivered: 3} = OSCORERelay.counts(relay)
    refute_received {:wotex_coap, _, _}
  end

  test "WCO-S06 WCO-V13 an independent OSCORE stack's tampered notification is discarded",
       context do
    {session, _} = connect_through_relay!(context, {:corrupt, 2})
    test_pid = self()

    assert {:ok, %Subscription{reference: reference}} =
             CoAP.subscribe(session, %{
               path: "/obs",
               receiver: test_pid,
               observation_kind: :property
             })

    first = notification!(reference)
    second = notification!(reference)
    assert second.observe > first.observe + 1
    refute_received {:wotex_coap, ^reference, {:error, %Error{}}}
  end

  defp notification!(reference) do
    receive do
      {:wotex_coap, ^reference, {:ok, %Message{code: code, payload: payload}, meta}} ->
        %{code: code, payload: payload, observe: meta.observe, max_age: meta.max_age}
    after
      15_000 -> flunk("no notification from the independent peer")
    end
  end

  defp connect_through_relay!(context, mode) do
    relay = start_supervised!({OSCORERelay, {context.port, mode}}, id: make_ref())
    session = connect!(context, OSCORERelay.endpoint(relay))
    {session, relay}
  end

  defp connect!(context, port \\ nil) do
    store = Path.join(context.root, "store-#{System.unique_integer([:positive])}")
    File.mkdir!(store)
    File.chmod!(store, 0o700)

    assert {:ok, session} =
             CoAP.connect(
               host: "127.0.0.1",
               port: port || context.port,
               timeout: 10_000,
               security: CaliforniumPeer.security(store),
               native_backend: context.backend
             )

    session
  end
end
