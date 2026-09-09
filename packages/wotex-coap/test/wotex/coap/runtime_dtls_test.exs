Code.require_file("../../support/runtime_dtls_peer.ex", __DIR__)
Code.require_file("../../support/runtime_security_credentials.ex", __DIR__)

defmodule Wotex.CoAP.RuntimeDTLSTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Mapping, Transport}
  alias Wotex.CoAP.Test.{RuntimeDTLSPeer, RuntimeSecurityCredentials}

  alias Wotex.Runtime.{
    BindingProfile,
    ConsumedThing,
    Context,
    ExecutionContext,
    Request,
    Subscription
  }

  @moduletag :capture_log

  test "WCO-I02 WCO-S05 DTLS profile and mapping require an explicit secure route" do
    {:ok, profile} = CoAP.profile(:dtls)
    assert BindingProfile.id(profile) == :coaps
    assert BindingProfile.supports_scheme?(profile, "coaps")
    refute BindingProfile.supports_scheme?(profile, "coap")

    for operation <- [
          :readproperty,
          :writeproperty,
          :invokeaction,
          :observeproperty,
          :unobserveproperty,
          :subscribeevent,
          :unsubscribeevent
        ],
        do: assert(BindingProfile.supports_operation?(profile, operation))

    for media <- ["application/json", "application/octet-stream", "text/plain;charset=utf-8"],
        do: assert(BindingProfile.supports_media_type?(profile, media))

    for {href, scheme, port} <- [
          {"coap://127.0.0.1/x", :coap, 5683},
          {"coaps://127.0.0.1/x", :coaps, 5684}
        ] do
      {:ok, form} = Wotex.Form.new(%{"href" => href})
      assert {:ok, mapping} = Mapping.command(form, :readproperty, nil)
      assert mapping.scheme == scheme and mapping.port == port
      assert mapping.form == form
    end
  end

  test "WCO-I02 WCO-I03 WCO-I04 typed immediate and configured PSK/PKI authenticate all unary operations" do
    for mode <- [:psk, :pki],
        custody <- [:immediate, :configured],
        operation <- [:readproperty, :writeproperty, :invokeaction] do
      {peer, listener, port} = RuntimeDTLSPeer.peer(mode)
      security = credential(mode)
      config = if custody == :configured, do: [security: security], else: []
      immediate = if custody == :immediate, do: security
      consumed = consumed(port, config, immediate)
      {:ok, context} = Context.new(request_id: "secure")
      call = Task.async(fn -> invoke(consumed, operation, context) end)
      assert_receive {:request, request}, 1500
      assert request.code == %{readproperty: 1, writeproperty: 3, invokeaction: 2}[operation]
      assert Codec.option(request, 11) == ["value"]
      assert Codec.option(request, 17) == [<<50>>]
      if operation != :readproperty, do: assert(request.payload == "false")

      send(
        peer.pid,
        {:reply, %{request | type: :ack, code: 69, options: [{12, <<50>>}], payload: "false"}}
      )

      assert {:ok, result} = Task.await(call)

      assert result.payload == false and result.request_id == "secure" and
               result.operation == operation

      assert result.metadata == %{code: 69}
      refute inspect(result) =~ (security.key || "fixture-key")
      RuntimeDTLSPeer.close_peer(peer, listener)
    end
  end

  test "WCO-I03 WCO-I04 security, profile and custody mismatches acquire no socket" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    {:ok, context} = Context.new(request_id: "invalid-security")
    {:ok, secured} = CoAP.profile(:dtls)
    security = credential(:psk)
    before_ports = MapSet.new(Port.list())

    for {scheme, profile, immediate, config} <- [
          {"coaps", secured, nil, []},
          {"coaps", secured, security, [security: security]},
          {"coaps", secured, nil, [security: nil]},
          {"coaps", secured, %{security | key: "short"}, []},
          {"coaps", secured, :secret, []},
          {"coaps", CoAP.profile(), security, []},
          {"coap", secured, security, []},
          {"coap", CoAP.profile(), security, []},
          {"coap", CoAP.profile(), nil, [security: security]}
        ] do
      request = request(scheme, port, profile, context)
      execution = ExecutionContext.new(context, immediate)

      assert {:error, %Error{effect: :none, class: :permanent}} =
               Transport.request(request, execution, config)
    end

    stream = %{request("coaps", port, secured, context) | operation: :observeproperty}

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.subscribe(stream, self(), ExecutionContext.new(context, security), [])

    assert MapSet.difference(MapSet.new(Port.list()), before_ports) == MapSet.new()
    assert {:error, :timeout} = :gen_udp.recv(peer, 0, 20)
  end

  test "WCO-I04 WCO-V12 authentication failure or handshake deadline transmits no CoAP mutation" do
    for {mode, certificate, security} <- [
          {:psk, "server", RuntimeDTLSPeer.security(:psk, key: "wrong-key-1234567")},
          {:pki, "wrong-san", credential(:pki)},
          {:pki, "expired", credential(:pki)}
        ] do
      {peer, listener, port} = RuntimeDTLSPeer.peer(mode, certificate)
      consumed = consumed(port, [], security)
      {:ok, context} = Context.new(request_id: "auth-failure")
      assert {:error, error} = ConsumedThing.write_property(consumed, "value", false, context)
      assert error.details.cause.code in [:security_handshake_failed, :deadline_exceeded, :timeout]

      assert error.class ==
               if(error.details.cause.code == :security_handshake_failed,
                 do: :permanent,
                 else: :timeout
               )

      refute_received {:request, _}
      RuntimeDTLSPeer.close_peer(peer, listener)
    end
  end

  test "WCO-I05 WCO-S05 configured DTLS Property and Event streams retain their cancellation route" do
    for mode <- [:psk, :pki], kind <- [:property, :event] do
      {peer, listener, port} = RuntimeDTLSPeer.peer(mode)
      consumed = consumed(port, [security: credential(mode)], nil)
      {:ok, context} = Context.new(request_id: "secure-stream")

      function =
        if kind == :property, do: :observation_child_spec, else: :event_subscription_child_spec

      {:ok, spec} =
        apply(ConsumedThing, function, [
          consumed,
          "value",
          context,
          [id: {mode, kind}, receiver: self(), restart: :temporary]
        ])

      owner = start_supervised!(spec)
      assert_receive {:request, initial}, 1500
      assert Codec.option(initial, 6) == [<<>>]
      assert Codec.option(initial, 17) == [<<50>>]
      options = [{6, <<10>>}, {12, <<50>>}]

      send(
        peer.pid,
        {:reply, %{initial | type: :ack, code: 69, options: options, payload: "false"}}
      )

      assert_receive {:wotex_runtime, _, {:ok, false, %{observe: 10}}}, 1500
      handle = await(fn -> :sys.get_state(owner).handle end)
      relay = :sys.get_state(handle.pid)
      connection = :sys.get_state(relay.session.pid)
      assert_receive {:client_port, :peer, client_port}, 1000

      monitors =
        Enum.map([handle.pid, relay.session.pid, connection.handle.pid], &Process.monitor/1)

      refute Map.has_key?(Map.from_struct(handle), :security)
      refute inspect(:sys.get_status(handle.pid)) =~ "fixture-key"

      notification = %{
        initial
        | type: :con,
          message_id: 900,
          code: 69,
          options: [{6, <<11>>}, {12, <<50>>}],
          payload: "false"
      }

      send(peer.pid, {:reply, notification})
      assert_receive {:request, %{type: :ack, code: 0, message_id: 900}}, 1000
      assert_receive {:wotex_runtime, _, {:ok, false, %{observe: 11}}}, 1000
      stop = Task.async(fn -> Subscription.stop(owner) end)
      assert_receive {:request, cancellation}, 1000
      assert cancellation.token == initial.token
      assert Codec.option(cancellation, 6) == [<<1>>]
      assert Codec.option(cancellation, 11) == ["value"]
      send(peer.pid, {:reply, %{cancellation | type: :ack, code: 69, options: [], payload: ""}})
      assert :ok = Task.await(stop, 1500)
      for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1000)
      assert_socket_free(client_port)
      RuntimeDTLSPeer.close_peer(peer, listener)
    end
  end

  test "WCO-C03 WCO-I04 WCO-I05 receiver death interrupts a DTLS handshake and releases its UDP port" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    receiver = spawn(fn -> receive do: (:done -> :ok) end)
    consumed = consumed(port, [security: credential(:psk)], nil)
    {:ok, context} = Context.new(request_id: "opening-owner-death")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "value", context,
        id: :handshake,
        receiver: receiver,
        restart: :temporary
      )

    owner = start_supervised!(spec)
    monitor = Process.monitor(owner)
    assert {:ok, {_, client_port, <<22, 254, _::binary>>}} = :gen_udp.recv(peer, 0, 1000)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1000
    assert_socket_free(client_port)
  end

  test "WCO-C03 WCO-I05 receiver death cancels an authenticated persistent association" do
    for mode <- [:psk, :pki] do
      {peer, listener, port} = RuntimeDTLSPeer.peer(mode)
      receiver = spawn(fn -> receive do: (:done -> :ok) end)
      consumed = consumed(port, [security: credential(mode)], nil)
      {:ok, context} = Context.new(request_id: "bound-owner-death")

      {:ok, spec} =
        ConsumedThing.observation_child_spec(consumed, "value", context,
          id: mode,
          receiver: receiver,
          restart: :temporary
        )

      owner = start_supervised!(spec)
      assert_receive {:request, initial}, 1500

      send(
        peer.pid,
        {:reply,
         %{initial | type: :ack, code: 69, options: [{6, <<10>>}, {12, <<50>>}], payload: "false"}}
      )

      handle = await(fn -> :sys.get_state(owner).handle end)
      assert Process.alive?(handle.pid)
      assert_receive {:client_port, :peer, client_port}, 1000
      monitor = Process.monitor(owner)
      Process.exit(receiver, :kill)
      assert_receive {:request, cancellation}, 1000
      assert cancellation.token == initial.token and Codec.option(cancellation, 6) == [<<1>>]
      send(peer.pid, {:reply, %{cancellation | type: :ack, code: 69, options: [], payload: ""}})
      assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1000
      assert_socket_free(client_port)
      RuntimeDTLSPeer.close_peer(peer, listener)
    end
  end

  defp credential(:psk), do: RuntimeDTLSPeer.security(:psk)
  defp credential(:pki), do: RuntimeDTLSPeer.pki_security()

  defp consumed(port, config, immediate) do
    href = "coaps://127.0.0.1:#{port}/value"
    unary = %{"href" => href, "contentType" => "application/json"}
    observe = Map.put(unary, "op", "observeproperty")
    event = Map.put(unary, "op", "subscribeevent")

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Secure fixture",
        "securityDefinitions" => %{"configured" => %{"scheme" => "nosec"}},
        "security" => ["configured"],
        "properties" => %{
          "value" => %{
            "observable" => true,
            "forms" => [
              unary,
              observe,
              %{"href" => "coaps://127.0.0.1:1/unused", "op" => "unobserveproperty"}
            ]
          }
        },
        "actions" => %{"value" => %{"forms" => [unary]}},
        "events" => %{
          "value" => %{
            "forms" => [
              event,
              %{"href" => "coaps://127.0.0.1:1/unused", "op" => "unsubscribeevent"}
            ]
          }
        }
      })

    {:ok, profile} = CoAP.profile(:dtls)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{coaps: {Transport, [timeout: 1000] ++ config}},
        credentials: {RuntimeSecurityCredentials, immediate}
      )

    consumed
  end

  defp invoke(consumed, :readproperty, context),
    do: ConsumedThing.read_property(consumed, "value", context)

  defp invoke(consumed, :writeproperty, context),
    do: ConsumedThing.write_property(consumed, "value", false, context)

  defp invoke(consumed, :invokeaction, context),
    do: ConsumedThing.invoke_action(consumed, "value", false, context)

  defp request(scheme, port, profile, context) do
    href = "#{scheme}://127.0.0.1:#{port}/value"
    {:ok, form} = Wotex.Form.new(%{"href" => href, "op" => ["readproperty", "observeproperty"]})

    %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "value",
      form: form,
      resolved_href: href,
      profile: profile,
      request_id: context.request_id,
      deadline: context.deadline,
      input: nil
    }
  end

  defp await(fun), do: await(fun, System.monotonic_time(:millisecond) + 1000)

  defp await(fun, deadline) do
    case fun.() do
      nil ->
        assert System.monotonic_time(:millisecond) < deadline
        Process.sleep(1)
        await(fun, deadline)

      value ->
        value
    end
  end

  defp assert_socket_free(port) do
    assert :ok ==
             await(fn ->
               case :gen_udp.open(port, [:binary]) do
                 {:ok, socket} -> :gen_udp.close(socket)
                 {:error, :eaddrinuse} -> nil
               end
             end)
  end
end
