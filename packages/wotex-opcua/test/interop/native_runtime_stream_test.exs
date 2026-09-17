defmodule Wotex.OPCUA.NativeRuntimeStreamInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Open62541, TestNosecCredentials, Transport}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Subscription}
  @moduletag :interop

  setup do
    config_path = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config_path))
    directory = Path.dirname(config_path)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    connection = [
      client: Open62541,
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      endpoint: peer["endpoint"],
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: peer["client_uri"],
      server_uri: peer["server_uri"],
      certificate: peer["certificate"],
      private_key: Path.join(directory, "client.key.der"),
      server_certificate: peer["server_certificate"],
      trust_certificate: Path.join(directory, "ca.der"),
      crl: peer["crl"],
      authentication: %{type: :anonymous}
    ]

    config =
      connection ++
        [
          target: peer["endpoint"],
          subscription: %{publishing_interval_ms: 50, sampling_interval_ms: 0}
        ]

    {:ok, observer} = Wotex.OPCUA.connect(connection)
    {:ok, %{"value" => %{"value" => original}}} = read(observer, peer["node_id"])

    on_exit(fn ->
      {:ok, session} = Wotex.OPCUA.connect(connection)
      write(session, peer["node_id"], original)
      Wotex.OPCUA.disconnect(session)
    end)

    {:ok, context} = Context.new(request_id: "runtime-observe")
    %{peer: peer, config: config, observer: observer, context: context, original: original}
  end

  test "WOP-V13 a Runtime Property observation delivers peer values and deletes on stop",
       context do
    %{peer: peer, observer: observer} = context
    consumed = consumed(peer, context.config)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "reading", context.context,
               id: :reading,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    owner = start_supervised!(spec)
    initial = context.original

    assert_receive {:wotex_runtime, :reading,
                    {:ok, ^initial,
                     %{
                       opcua_type: "Double",
                       status: 0,
                       sequence: first,
                       client_handle: handle,
                       overflow: false,
                       datetime_resolution_ns: 100,
                       raw_datetime_ticks_available: true
                     }}},
                   5000

    assert {1, 1} = resources(observer, peer)

    for value <- [41.5, 42.5] do
      assert {:ok, %{"status" => 0}} = write(observer, peer["node_id"], value)

      assert_receive {:wotex_runtime, :reading,
                      {:ok, ^value, %{sequence: sequence, client_handle: ^handle}}},
                     5000

      assert sequence > first
    end

    assert {:ok, bytes_spec} =
             ConsumedThing.observation_child_spec(consumed, "bytes", context.context,
               id: :bytes,
               receiver: self(),
               restart: :temporary
             )

    bytes_owner = start_supervised!(bytes_spec, id: :bytes)
    assert_receive {:wotex_runtime, :bytes, {:ok, bytes, %{opcua_type: "ByteString"}}}, 5000
    assert is_binary(bytes)
    assert :ok = Subscription.stop(bytes_owner)
    assert :ok = Subscription.stop(owner)
    assert {0, 0} = resources(observer, peer)
    refute_receive {:wotex_runtime, :reading, {:ok, _, _}}, 200
    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  test "WOP-V13 Runtime owner death and peer loss release the observation", context do
    %{peer: peer, observer: observer} = context
    consumed = consumed(peer, context.config)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "reading", context.context,
               id: :killed,
               receiver: self(),
               restart: :temporary
             )

    owner = start_supervised!(spec)
    assert_receive {:wotex_runtime, :killed, {:ok, _, _}}, 5000
    assert {1, 1} = resources(observer, peer)
    Process.exit(owner, :kill)
    assert eventually(fn -> resources(observer, peer) == {0, 0} end, 1000)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "reading", context.context,
               id: :lost,
               receiver: self(),
               restart: :temporary
             )

    owner = start_supervised!(spec, id: :lost)
    monitor = Process.monitor(owner)
    assert_receive {:wotex_runtime, :lost, {:ok, _, _}}, 5000

    assert {:ok, %{"outputs" => [%{"value" => 1}]}} =
             call(observer, peer["loss_method_id"], [])

    assert {:ok, %{"status" => 0}} = write(observer, peer["node_id"], 43.5)
    assert_receive {:wotex_runtime, :lost, {:error, _}}, 5000
    assert_receive {:wotex_runtime, :lost, {:status, :session_lost}}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :session_lost}}, 1000
    assert eventually(fn -> resources(observer, peer) == {0, 0} end, 1000)
    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  test "WOP-V13 an Event subscription and a one-shot client acquire no peer subscription",
       context do
    %{peer: peer, observer: observer} = context

    for {name, config} <- [
          {"alarm", context.config},
          {"reading", Keyword.put(context.config, :lifecycle, :oneshot)}
        ] do
      consumed = consumed(peer, config)
      id = {:rejected, name}

      child =
        if name == "alarm",
          do:
            ConsumedThing.event_subscription_child_spec(consumed, name, context.context,
              id: id,
              receiver: self(),
              restart: :temporary
            ),
          else:
            ConsumedThing.observation_child_spec(consumed, name, context.context,
              id: id,
              receiver: self(),
              restart: :temporary
            )

      assert {:ok, spec} = child
      owner = start_supervised!(spec, id: id)
      monitor = Process.monitor(owner)
      assert_receive {:wotex_runtime, ^id, {:error, _}}, 5000
      assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, _}}, 1000
      assert {0, 0} = resources(observer, peer)
    end

    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  defp consumed(peer, config) do
    href = &(peer["endpoint"] <> "?id=" <> URI.encode_www_form(&1))
    observe = ["readproperty", "observeproperty", "unobserveproperty"]

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:peer",
        "title" => "Peer",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [%{"href" => href.(peer["node_id"]), "op" => observe}]
          },
          "bytes" => %{
            "observable" => true,
            "forms" => [%{"href" => href.(peer["byte_node_id"]), "op" => observe}]
          }
        },
        "events" => %{
          "alarm" => %{
            "forms" => [
              %{"href" => href.(peer["node_id"]), "op" => ["subscribeevent", "unsubscribeevent"]}
            ]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(
        id: :opcua_session,
        schemes: ["opc.tcp"],
        operations: [
          :readproperty,
          :observeproperty,
          :unobserveproperty,
          :subscribeevent,
          :unsubscribeevent
        ]
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{opcua_session: {Transport, config}},
        credentials: {TestNosecCredentials, nil}
      )

    consumed
  end

  defp resources(session, peer) do
    {:ok, %{"outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
      call(session, peer["resources_method_id"], [])

    {subscriptions, items}
  end

  defp call(session, method, arguments),
    do:
      Wotex.OPCUA.send(session, %{
        type: :call,
        node_id: method,
        value: %{object_id: "ns=0;i=85", arguments: arguments}
      })

  defp read(session, node), do: Wotex.OPCUA.send(session, %{type: :read, node_id: node})

  defp write(session, node, value),
    do:
      Wotex.OPCUA.send(session, %{
        type: :write,
        node_id: node,
        value: %{type: "Double", value: value}
      })

  defp eventually(check, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    poll(check, deadline)
  end

  defp poll(check, deadline) do
    cond do
      check.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        poll(check, deadline)
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
