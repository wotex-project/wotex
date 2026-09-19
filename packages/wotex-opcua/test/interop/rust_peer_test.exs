defmodule Wotex.OPCUA.RustPeerInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Address, Browse, Error, Open62541, TestNosecCredentials, Transport}
  alias Wotex.Runtime.{ConsumedThing, Context, Result, Subscription}
  @moduletag :interop

  @corpus "priv/fixtures/native-contract-v1.json"
  @corpus_sha256 :crypto.hash(:sha256, File.read!(@corpus)) |> Base.encode16(case: :lower)
  @cases Map.new(Jason.decode!(File.read!(@corpus))["cases"], &{&1["id"], &1})
  @policies %{
    "Basic256Sha256" => :basic256sha256,
    "Aes128_Sha256_RsaOaep" => :aes128_sha256_rsaoaep,
    "Aes256_Sha256_RsaPss" => :aes256_sha256_rsapss
  }

  # The second independent peer runs the async-opcua Rust server.
  # Its fixture methods report the server's own live browse continuation points
  # across every Session and the number of requests its Cancel service found.
  setup context do
    peer = Jason.decode!(File.read!(System.fetch_env!("WOTEX_OPCUA_RUST_CONFIG")))
    fixture = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG") |> Path.dirname()
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")
    digest = fn path -> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) end

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest.(executable),
      guardian: guardian,
      guardian_digest: digest.(guardian),
      endpoint: peer["endpoint"],
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: "urn:wotex:fixture:client",
      server_uri: "urn:wotex:fixture:server",
      certificate: Path.join(fixture, "client.der"),
      private_key: Path.join(fixture, "client.key.der"),
      server_certificate: Path.join(fixture, "server.der"),
      trust_certificate: Path.join(fixture, "ca.der"),
      crl: Path.join(fixture, "clean.crl"),
      authentication: %{type: :anonymous}
    ]

    base = %{peer: peer, fixture: fixture, options: options}

    if context[:rust_session] do
      assert {:ok, session} = Wotex.OPCUA.connect(options)
      on_exit(fn -> Wotex.OPCUA.disconnect(session) end)

      node = node_resolver(session, peer["namespace_uri"])
      Map.merge(base, %{session: session, node: node})
    else
      base
    end
  end

  for number <- 30..38 do
    id = "WOP-X-F#{number}"

    @tag case: id, corpus_sha256: @corpus_sha256, rust_session: true
    test "#{id} executes every service against the independent Rust policy and token", context do
      %{"input" => input, "expectation" => %{"value" => expected}} =
        Map.fetch!(@cases, unquote(id))

      assert input["independent_peer"] == "async-opcua-rust-peer-1"

      options =
        Keyword.merge(context.options,
          security_policy: Map.fetch!(@policies, input["policy"]),
          authentication: token(context, input["user_token"])
        )

      assert {:ok, session} = Wotex.OPCUA.connect(options)
      %Wotex.OPCUA.Session{handle: %{host: host}} = session
      processes = native_processes(host)
      read = %{type: :read, node_id: context.node.("value")}
      {:ok, %{"value" => %{"value" => original}}} = Wotex.OPCUA.send(session, read)

      {:ok, subscription} =
        Wotex.OPCUA.subscribe(session, %{
          node_id: context.node.("value"),
          publishing_interval_ms: 50
        })

      reference = subscription.reference

      results = %{
        "read" =>
          match?({:ok, %{"value" => %{"value" => ^original}}}, Wotex.OPCUA.send(session, read)),
        "write" =>
          match?(
            {:ok, %{"status" => 0}},
            Wotex.OPCUA.send(session, %{
              type: :write,
              node_id: context.node.("value"),
              value: %{type: "Double", value: 42.25}
            })
          ),
        "readback" =>
          match?({:ok, %{"value" => %{"value" => 42.25}}}, Wotex.OPCUA.send(session, read)),
        "call" =>
          match?(
            {:ok, %{"outputs" => [%{"value" => 3.5}]}},
            Wotex.OPCUA.send(session, %{
              type: :call,
              node_id: context.node.("add"),
              value: %{
                object_id: context.node.("fixture"),
                arguments: [%{type: "Double", value: 1.25}, %{type: "Double", value: 2.25}]
              }
            })
          ),
        "browse" => browsed?(session, context.node),
        "subscribe" =>
          receive do
            {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => value}}, _}} ->
              value in [original, 42.25]
          after
            5000 -> false
          end,
        "cancel" => Wotex.OPCUA.unsubscribe(session, subscription) == :ok
      }

      {active_subscriptions, active_items} = resources(session, context.node)
      assert active_items == 0

      {:ok, %{"status" => 0}} =
        Wotex.OPCUA.send(session, %{
          type: :write,
          node_id: context.node.("value"),
          value: %{type: "Double", value: original}
        })

      live_continuations = count(session, context.node, "continuation_points")
      monitor = Process.monitor(host)
      results = Map.put(results, "close", Wotex.OPCUA.disconnect(session) == :ok)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
      assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end)

      observed = %{
        "operations_succeeded" => Enum.count(input["operations"], &Map.fetch!(results, &1)),
        "active_peer_subscriptions" => active_subscriptions,
        "active_peer_continuations" => live_continuations,
        "active_local_resources" => Enum.count([host | processes], &alive?/1)
      }

      assert observed == expected
      assert Enum.sort(Map.keys(results)) == Enum.sort(input["operations"])
    end
  end

  @tag rust_session: true
  test "WOP-S04 WOP-V10 independent monitoring delivers initial and fresh reports once",
       %{session: session, node: node} do
    baseline = native_descendants()
    node_id = node.("value")

    {:ok, %{"value" => %{"value" => original}}} =
      Wotex.OPCUA.send(session, %{type: :read, node_id: node_id})

    request = %{
      node_id: node_id,
      publishing_interval_ms: 50,
      sampling_interval_ms: 0,
      queue_size: 2,
      keepalive_count: 2,
      lifetime_count: 6
    }

    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference

    try do
      assert_receive {:wotex_opcua, ^reference,
                      {:ok, %{"value" => %{"type" => "Double", "value" => ^original}}, initial}},
                     5000

      assert %{
               "sequence" => initial_sequence,
               "client_handle" => client_handle,
               "overflow" => false,
               "datetime_resolution_ns" => 100,
               "raw_datetime_ticks_available" => true
             } = initial

      assert resources(session, node) == {1, 1}

      assert {:ok, %{"status" => 0}} = write(session, node_id, 51.25)

      assert_receive {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => 51.25}}, fresh}},
                     5000

      assert fresh["sequence"] > initial_sequence
      assert fresh["client_handle"] == client_handle
      assert fresh["overflow"] == false

      assert {:ok, %{"status" => 0}} = write(session, node_id, 52.5)

      assert_receive {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => 52.5}}, newest}},
                     5000

      assert newest["sequence"] > fresh["sequence"]
      assert newest["client_handle"] == client_handle
      refute_receive {:wotex_opcua, ^reference, _}, 300

      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      assert eventually(fn -> resources(session, node) == {0, 0} end)
    after
      assert {:ok, %{"status" => 0}} = write(session, node_id, original)
    end

    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert native_descendants() == baseline
  end

  @tag rust_session: true
  test "WOP-S04 WOP-V11 independent Republish recovers a withheld report once",
       %{session: session, node: node} do
    node_id = node.("value")

    {:ok, %{"value" => %{"value" => original}}} =
      Wotex.OPCUA.send(session, %{type: :read, node_id: node_id})

    assert {:ok, subscription} =
             Wotex.OPCUA.subscribe(session, %{
               node_id: node_id,
               publishing_interval_ms: 50,
               sampling_interval_ms: 0
             })

    reference = subscription.reference

    try do
      assert {:ok, _, %{"sequence" => initial}} = next_report(reference)
      {before, republished} = republish_faults(session, node, 1, false)
      assert {:ok, %{"status" => 0}} = write(session, node_id, 71.0)
      expected = before + 1
      assert eventually(fn -> match?({^expected, _}, republish_faults(session, node, 0, false)) end)
      refute_receive {:wotex_opcua, ^reference, _}, 100
      assert {:ok, %{"status" => 0}} = write(session, node_id, 72.0)

      assert {:ok, %{"value" => %{"value" => 71.0}}, %{"sequence" => sequence}} =
               next_report(reference)

      assert sequence == initial + 1

      assert {:ok, %{"value" => %{"value" => 72.0}}, %{"sequence" => next_sequence}} =
               next_report(reference)

      assert next_sequence == initial + 2
      assert {^expected, count} = republish_faults(session, node, 0, false)
      assert count == republished + 1
      refute_receive {:wotex_opcua, ^reference, _}, 300
      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      assert eventually(fn -> resources(session, node) == {0, 0} end)
    after
      assert {:ok, %{"status" => 0}} = write(session, node_id, original)
    end
  end

  @tag rust_session: true
  test "WOP-S04 WOP-V11 unavailable independent Republish ends the subscription",
       %{session: session, node: node} do
    node_id = node.("value")

    {:ok, %{"value" => %{"value" => original}}} =
      Wotex.OPCUA.send(session, %{type: :read, node_id: node_id})

    assert {:ok, subscription} =
             Wotex.OPCUA.subscribe(session, %{
               node_id: node_id,
               publishing_interval_ms: 50,
               sampling_interval_ms: 0
             })

    reference = subscription.reference

    try do
      assert {:ok, _, _} = next_report(reference)
      {before, republished} = republish_faults(session, node, 1, true)
      assert {:ok, %{"status" => 0}} = write(session, node_id, 73.0)
      expected = before + 1
      assert eventually(fn -> match?({^expected, _}, republish_faults(session, node, 0, false)) end)
      refute_receive {:wotex_opcua, ^reference, _}, 100
      assert {:ok, %{"status" => 0}} = write(session, node_id, 74.0)

      assert {:error, %Error{code: :sequence_gap, effect: :none}} = next_report(reference)
      refute_receive {:wotex_opcua, ^reference, _}, 300
      assert eventually(fn -> resources(session, node) == {0, 0} end)
      assert {^expected, count} = republish_faults(session, node, 0, false)
      assert count == republished + 1
      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)

      assert {:ok, %{"value" => %{"type" => "Double"}}} =
               Wotex.OPCUA.send(session, %{type: :read, node_id: node_id})
    after
      assert {:ok, %{"status" => 0}} = write(session, node_id, original)
    end
  end

  @tag rust_session: true
  test "WOP-C05 WOP-V12 independent receiver death cancels only its subscription",
       %{session: session, node: node} do
    baseline = native_descendants()

    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    request = %{
      node_id: node.("value"),
      receiver: receiver,
      publishing_interval_ms: 50,
      sampling_interval_ms: 0
    }

    assert {:ok, lost} = Wotex.OPCUA.subscribe(session, request)

    assert {:ok, kept} =
             Wotex.OPCUA.subscribe(session, %{
               node_id: node.("value"),
               publishing_interval_ms: 50,
               sampling_interval_ms: 0
             })

    kept_reference = kept.reference
    assert_receive {:wotex_opcua, ^kept_reference, {:ok, _, _}}, 5000
    assert resources(session, node) == {2, 2}

    %Wotex.OPCUA.Session{handle: %{host: host}} = session
    Process.exit(receiver, :kill)

    assert eventually(fn ->
             state = :sys.get_state(host)

             not Map.has_key?(state.subscriptions, lost.reference) and
               resources(session, node) == {1, 1}
           end)

    assert :ok = Wotex.OPCUA.unsubscribe(session, lost)

    assert {:ok, %{"value" => %{"type" => "Double"}}} =
             Wotex.OPCUA.send(session, %{type: :read, node_id: node.("value")})

    assert :ok = Wotex.OPCUA.unsubscribe(session, kept)
    assert eventually(fn -> resources(session, node) == {0, 0} end)
    assert native_descendants() == baseline
  end

  @tag rust_session: true
  test "WOP-C05 WOP-V11 independent receiver overflow is terminal once",
       %{session: session, node: node} do
    baseline = native_descendants()
    test = self()
    node_id = node.("value")

    {:ok, %{"value" => %{"value" => original}}} =
      Wotex.OPCUA.send(session, %{type: :read, node_id: node_id})

    receiver =
      spawn(fn ->
        receive do
          :drain -> send(test, {:drained, drain([])})
        end
      end)

    request = %{
      node_id: node_id,
      receiver: receiver,
      publishing_interval_ms: 20,
      sampling_interval_ms: 0,
      max_queue_length: 2
    }

    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)

    try do
      for value <- [61.0, 62.0, 63.0, 64.0] do
        assert {:ok, %{"status" => 0}} = write(session, node_id, value)
        Process.sleep(120)
      end

      %Wotex.OPCUA.Session{handle: %{host: host}} = session

      assert eventually(fn ->
               not Map.has_key?(:sys.get_state(host).subscriptions, subscription.reference)
             end)

      send(receiver, :drain)
      assert_receive {:drained, messages}, 1000
      reference = subscription.reference

      assert [{:wotex_opcua, ^reference, {:error, %Error{code: :receiver_overflow}}} | _] =
               Enum.reverse(messages)

      assert Enum.count(messages, &match?({:wotex_opcua, _, {:error, _}}, &1)) == 1
      assert length(messages) == 3
      assert eventually(fn -> resources(session, node) == {0, 0} end)
      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    after
      assert {:ok, %{"status" => 0}} = write(session, node_id, original)
    end

    assert native_descendants() == baseline
  end

  @tag rust_session: true
  test "WOP-S04 WOP-V12 independent lifetime expiry ends only the subscription",
       %{session: session, node: node, options: options} do
    baseline = native_descendants()
    %Wotex.OPCUA.Session{handle: %{host: host}} = session

    request = %{
      node_id: node.("value"),
      publishing_interval_ms: 50,
      sampling_interval_ms: 0,
      keepalive_count: 2,
      lifetime_count: 6
    }

    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert_receive {:wotex_opcua, ^reference, {:ok, _, _}}, 5000
    assert {:ok, observer} = Wotex.OPCUA.connect(options)

    try do
      assert resources(observer, node) == {1, 1}
      [_, sdk] = native_processes(host)

      assert {_, 0} =
               System.cmd("/bin/kill", ["-STOP", Integer.to_string(sdk)], env: [{"LC_ALL", "C"}])

      expired =
        try do
          eventually(fn -> resources(observer, node) == {0, 0} end, 100)
        after
          System.cmd("/bin/kill", ["-CONT", Integer.to_string(sdk)], env: [{"LC_ALL", "C"}])
        end

      assert expired,
             "expected the independent peer to release the expired subscription, got #{inspect(resources(observer, node))}"

      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :subscription_lost, effect: :none}}},
                     5000

      refute_receive {:wotex_opcua, ^reference, _}, 300
      assert resources(observer, node) == {0, 0}

      assert {:ok, %{"value" => %{"type" => "Double"}}} =
               Wotex.OPCUA.send(session, %{type: :read, node_id: node.("value")})

      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    after
      assert :ok = Wotex.OPCUA.disconnect(observer)
    end

    assert eventually(fn -> native_descendants() == baseline end)
  end

  test "WOP-S02 WOP-V12 independent server loss is terminal without reconnect", context do
    baseline = native_descendants()
    {peer, endpoint} = variant(context, "server_loss")
    options = Keyword.put(context.options, :endpoint, endpoint)
    assert {:ok, session} = Wotex.OPCUA.connect(options)
    node = node_resolver(session, context.peer["namespace_uri"])
    %Wotex.OPCUA.Session{handle: %{host: host}} = session
    processes = native_processes(host)

    assert {:ok, subscription} =
             Wotex.OPCUA.subscribe(session, %{
               node_id: node.("value"),
               publishing_interval_ms: 50,
               sampling_interval_ms: 0
             })

    reference = subscription.reference
    assert_receive {:wotex_opcua, ^reference, {:ok, _, _}}, 5000
    assert resources(session, node) == {1, 1}
    monitor = Process.monitor(host)
    stop_peer(peer)

    assert_receive {:wotex_opcua, ^reference,
                    {:error,
                     %Error{
                       code: :connection_failed,
                       effect: :none,
                       details: %{status: 0x800E_0000, phase: :exchange}
                     }}},
                   10_000

    assert_receive {:DOWN, ^monitor, :process, ^host, _}, 5000
    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end)
    assert eventually(fn -> native_descendants() == baseline end)

    {restarted, restarted_endpoint} = variant(context, "server_loss")
    assert {:ok, fresh} = Wotex.OPCUA.connect(Keyword.put(options, :endpoint, restarted_endpoint))
    fresh_node = node_resolver(fresh, context.peer["namespace_uri"])

    assert {:ok, %{"value" => %{"type" => "Double"}}} =
             Wotex.OPCUA.send(fresh, %{type: :read, node_id: fresh_node.("value")})

    assert resources(fresh, fresh_node) == {0, 0}
    assert :ok = Wotex.OPCUA.disconnect(fresh)
    stop_peer(restarted)
    assert eventually(fn -> native_descendants() == baseline end)
  end

  test "WOP-I05 WOP-V13 Runtime observation ends once when the independent peer is lost",
       context do
    baseline = native_descendants()
    {peer, endpoint} = variant(context, "server_loss")
    options = Keyword.put(context.options, :endpoint, endpoint)
    assert {:ok, observer} = Wotex.OPCUA.connect(options)
    node = node_resolver(observer, context.peer["namespace_uri"])
    %Wotex.OPCUA.Session{handle: %{host: host}} = observer
    host_monitor = Process.monitor(host)

    config =
      options ++
        [
          target: endpoint,
          subscription: %{publishing_interval_ms: 50, sampling_interval_ms: 0}
        ]

    runtime_peer = Map.put(context.peer, "endpoint", endpoint)
    {consumed, _} = runtime_consumers(runtime_peer, node.("value"), config)
    {:ok, runtime_context} = Context.new(request_id: "rust-runtime-loss")

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "reading", runtime_context,
               id: :rust_runtime_loss,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    owner = start_supervised!(spec, id: :rust_runtime_loss)
    owner_monitor = Process.monitor(owner)

    assert_receive {:wotex_runtime, :rust_runtime_loss, {:ok, _, %{opcua_type: "Double"}}},
                   5000

    assert resources(observer, node) == {1, 1}
    stop_peer(peer)

    assert_receive {:wotex_runtime, :rust_runtime_loss,
                    {:error,
                     %Wotex.Runtime.Error{
                       code: :undecodable_frame,
                       phase: :subscription,
                       class: :unavailable,
                       details: %{
                         cause: %{
                           module: Wotex.OPCUA.Error,
                           code: :connection_failed,
                           class: :unavailable
                         }
                       }
                     }}},
                   10_000

    assert_receive {:wotex_runtime, :rust_runtime_loss, {:status, :transport_down}}, 1000
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, {:shutdown, :transport_down}}, 1000
    assert_receive {:DOWN, ^host_monitor, :process, ^host, _}, 5000
    refute_receive {:wotex_runtime, :rust_runtime_loss, _}, 300
    assert eventually(fn -> native_descendants() == baseline end)

    {restarted, restarted_endpoint} = variant(context, "server_loss")
    restarted_options = Keyword.put(context.options, :endpoint, restarted_endpoint)
    assert {:ok, restarted_observer} = Wotex.OPCUA.connect(restarted_options)
    restarted_node = node_resolver(restarted_observer, context.peer["namespace_uri"])

    restarted_config =
      restarted_options ++
        [
          target: restarted_endpoint,
          subscription: %{publishing_interval_ms: 50, sampling_interval_ms: 0}
        ]

    restarted_peer = Map.put(context.peer, "endpoint", restarted_endpoint)

    {restarted_consumed, _} =
      runtime_consumers(restarted_peer, restarted_node.("value"), restarted_config)

    assert {:ok, restarted_spec} =
             ConsumedThing.observation_child_spec(
               restarted_consumed,
               "reading",
               runtime_context,
               id: :rust_runtime_loss_restarted,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    restarted_owner = start_supervised!(restarted_spec, id: :rust_runtime_loss_restarted)

    assert_receive {:wotex_runtime, :rust_runtime_loss_restarted,
                    {:ok, _, %{opcua_type: "Double"}}},
                   5000

    assert resources(restarted_observer, restarted_node) == {1, 1}
    assert :ok = Subscription.stop(restarted_owner)
    assert eventually(fn -> resources(restarted_observer, restarted_node) == {0, 0} end)
    assert :ok = Wotex.OPCUA.disconnect(restarted_observer)
    stop_peer(restarted)
    assert eventually(fn -> native_descendants() == baseline end)
  end

  @tag rust_session: true
  test "WOP-N03 WOP-N04 the independent server counts every continuation the client holds",
       %{session: session, peer: peer, node: node} do
    paged = node.("paged")
    children = for index <- 1..peer["children"], do: node.("child#{index}")
    live = fn -> count(session, node, "continuation_points") end
    assert live.() == 0

    assert {:ok, %Browse.Page{status: 0, references: first, continuation: cursor}} =
             Browse.references(session, paged, page_size: 5)

    assert length(first) == 5
    assert %Browse.Continuation{} = cursor
    assert live.() == 1

    assert {:ok, %Browse.Page{status: 0, references: second, continuation: next}} =
             Browse.next(session, cursor)

    assert length(second) == 5
    assert live.() == 1
    assert :ok = Browse.release(session, next)
    assert live.() == 0
    assert {:error, %Error{code: :invalid_continuation}} = Browse.next(session, next)
    assert {:error, %Error{code: :invalid_continuation}} = Browse.next(session, cursor)

    assert {:ok, %{status: 0, references: references}} = Browse.all(session, paged, page_size: 7)
    assert Enum.map(references, &Address.to_string(&1.node_id.node_id)) == children

    assert Enum.map(first ++ second, &Address.to_string(&1.node_id.node_id)) ==
             Enum.take(children, 10)

    assert live.() == 0

    assert {:ok, %Browse.Page{continuation: left}} =
             Browse.references(session, paged, page_size: 5)

    assert {:ok, %Browse.Page{continuation: right}} =
             Browse.references(session, paged, page_size: 5)

    assert live.() == 2
    assert :ok = Browse.release(session, left)
    assert live.() == 1

    assert {:ok, %Browse.Page{references: [_ | _], continuation: after_right}} =
             Browse.next(session, right)

    assert live.() == 1
    assert :ok = Browse.release(session, after_right)
    assert live.() == 0

    assert {:ok, listed} = Wotex.OPCUA.send(session, %{type: :browse, node_id: paged})
    assert listed == children
    assert live.() == 0
  end

  @tag rust_session: true
  test "WOP-N04 limit failures and an expired browse deadline release the server continuation",
       %{session: session, node: node} do
    paged = node.("paged")
    live = fn -> count(session, node, "continuation_points") end

    assert {:error, %Error{code: :response_limit, effect: :none}} =
             Browse.all(session, paged, page_size: 5, max_references: 12)

    assert live.() == 0

    assert {:error, %Error{code: :response_limit, effect: :none}} =
             Browse.all(session, paged, page_size: 5, max_pages: 2)

    assert live.() == 0

    assert {:ok, %Browse.Page{continuation: expiring}} =
             Browse.references(session, paged, page_size: 5, timeout_ms: 200)

    assert live.() == 1
    assert eventually(fn -> live.() == 0 end)
    assert {:error, %Error{code: :deadline_exceeded}} = Browse.next(session, expiring)
  end

  @tag rust_session: true
  test "WOP-C03 an expired or abandoned Call reaches the server's Cancel service",
       %{session: session, node: node} do
    cancelled = fn -> count(session, node, "cancel_count") end
    before = cancelled.()
    started = System.monotonic_time(:millisecond)
    slow = slow(node, 1500)

    assert {:error, %Error{code: :deadline_exceeded, effect: :unknown}} =
             Wotex.OPCUA.send(%{session | timeout: 300}, slow)

    assert eventually(fn -> cancelled.() == before + 1 end)

    caller = spawn(fn -> Wotex.OPCUA.send(session, slow) end)
    Process.sleep(200)
    Process.exit(caller, :kill)
    assert eventually(fn -> cancelled.() == before + 2 end)

    # Both late Call responses arrive after their Cancel; the Session discards
    # them and keeps serving.
    Process.sleep(max(started + 2500 - System.monotonic_time(:millisecond), 0))

    assert {:ok, %{"outputs" => [%{"type" => "UInt32", "value" => 1}]}} =
             Wotex.OPCUA.send(session, slow(node, 1))

    assert cancelled.() == before + 2
  end

  @tag rust_session: true
  test "WOP-I02 WOP-V13 Runtime profiles execute against the independent Rust peer", context do
    node = context.node.("value")
    baseline = native_descendants()
    read = %{type: :read, node_id: node}
    {:ok, %{"value" => %{"value" => original}}} = Wotex.OPCUA.send(context.session, read)

    on_exit(fn ->
      Wotex.OPCUA.send(context.session, %{
        type: :write,
        node_id: node,
        value: %{type: "Double", value: original}
      })
    end)

    config =
      context.options ++
        [
          target: context.peer["endpoint"],
          subscription: %{publishing_interval_ms: 50, sampling_interval_ms: 0}
        ]

    {session, oneshot} = runtime_consumers(context.peer, node, config)
    {:ok, runtime_context} = Context.new(request_id: "rust-runtime")

    assert {:ok, %Result{payload: ^original, metadata: %{opcua_type: "Double", status: 0}}} =
             ConsumedThing.read_property(session, "reading", runtime_context)

    assert eventually(fn -> native_descendants() == baseline end)

    assert {:ok, %Result{payload: nil, metadata: %{status: 0}}} =
             ConsumedThing.write_property(session, "reading", 44.5, runtime_context)

    assert {:ok, %Result{payload: 44.5}} =
             ConsumedThing.read_property(oneshot, "reading", runtime_context)

    assert {:ok, %Result{payload: "written"}} =
             ConsumedThing.write_property(oneshot, "reading", 45.5, runtime_context)

    assert eventually(fn -> native_descendants() == baseline end)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(session, "reading", runtime_context,
               id: :rust_runtime,
               receiver: self(),
               restart: :temporary
             )

    owner = start_supervised!(spec, id: :rust_runtime)

    assert_receive {:wotex_runtime, :rust_runtime,
                    {:ok, 45.5,
                     %{
                       opcua_type: "Double",
                       status: 0,
                       datetime_resolution_ns: 100,
                       raw_datetime_ticks_available: true
                     }}},
                   5000

    assert resources(context.session, context.node) == {1, 1}

    assert {:ok, %{"status" => 0}} =
             Wotex.OPCUA.send(context.session, %{
               type: :write,
               node_id: node,
               value: %{type: "Double", value: 46.5}
             })

    assert_receive {:wotex_runtime, :rust_runtime, {:ok, 46.5, %{opcua_type: "Double"}}}, 5000
    assert :ok = Subscription.stop(owner)
    assert eventually(fn -> resources(context.session, context.node) == {0, 0} end)
    assert eventually(fn -> native_descendants() == baseline end)

    assert {:ok, killed_spec} =
             ConsumedThing.observation_child_spec(session, "reading", runtime_context,
               id: :rust_runtime_killed,
               receiver: self(),
               restart: :temporary
             )

    killed = start_supervised!(killed_spec, id: :rust_runtime_killed)
    assert_receive {:wotex_runtime, :rust_runtime_killed, {:ok, 46.5, _}}, 5000
    assert resources(context.session, context.node) == {1, 1}
    Process.exit(killed, :kill)
    assert eventually(fn -> resources(context.session, context.node) == {0, 0} end)
    assert eventually(fn -> native_descendants() == baseline end)
  end

  @tag rust_session: true
  test "WOP-S01 WOP-S05 Runtime arrays roundtrip against the independent Rust peer", context do
    baseline = native_descendants()
    config = Keyword.put(context.options, :target, context.peer["endpoint"])

    for {identifier, type, original, written, dimensions} <- [
          {"int_array", "Int32", [-2_147_483_648, 0, 7], [2_147_483_647, -1], nil},
          {"double_array", "Double", [1.5, -0.0], [-0.0, 2.5e-300, 1.0e300], nil},
          {"int16_matrix", "Int16", [1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1], [2, 3]}
        ] do
      node = context.node.(identifier)
      consumed = runtime_array_consumer(context.peer, node, config)
      {:ok, runtime_context} = Context.new(request_id: "rust-runtime-#{identifier}")

      assert {:ok, %Result{payload: ^original, metadata: metadata}} =
               ConsumedThing.read_property(consumed, "samples", runtime_context)

      assert metadata.opcua_type == type
      assert metadata.status == 0
      assert Map.get(metadata, :opcua_dimensions) == dimensions

      input = %{"type" => type, "array" => true, "value" => written}
      input = if dimensions, do: Map.put(input, "dimensions", dimensions), else: input

      try do
        assert {:ok, %Result{payload: nil, metadata: %{status: 0}}} =
                 ConsumedThing.write_property(consumed, "samples", input, runtime_context)

        assert {:ok, %Result{payload: ^written, metadata: projected}} =
                 ConsumedThing.read_property(consumed, "samples", runtime_context)

        assert projected.opcua_type == type
        assert Map.get(projected, :opcua_dimensions) == dimensions

        if type == "Double" do
          [negative_zero | _] = written
          assert <<1::1, _::63>> = <<negative_zero::float-64>>
        end
      after
        restore = %{"type" => type, "array" => true, "value" => original}
        restore = if dimensions, do: Map.put(restore, "dimensions", dimensions), else: restore

        assert {:ok, %Result{payload: nil}} =
                 ConsumedThing.write_property(consumed, "samples", restore, runtime_context)
      end
    end

    assert eventually(fn -> native_descendants() == baseline end)
  end

  @tag rust_session: true
  test "WOP-S01 WOP-S05 Runtime validates every supported scalar from the Rust peer", context do
    baseline = native_descendants()
    config = Keyword.put(context.options, :target, context.peer["endpoint"])
    assert {:ok, runtime_context} = Context.new(request_id: "rust-runtime-scalars")

    assert {:ok, %{"value" => %{"value" => double}}} =
             Wotex.OPCUA.send(context.session, %{
               type: :read,
               node_id: context.node.("value")
             })

    scalars = [
      {"null_value", "Null", nil},
      {"boolean_value", "Boolean", true},
      {"sbyte_value", "SByte", -128},
      {"byte_value", "Byte", 255},
      {"int16_value", "Int16", -32_768},
      {"uint16_value", "UInt16", 65_535},
      {"int32_value", "Int32", -2_147_483_648},
      {"uint32_value", "UInt32", 4_294_967_295},
      {"int64_value", "Int64", -9_223_372_036_854_775_808},
      {"uint64_value", "UInt64", 18_446_744_073_709_551_615},
      {"float_value", "Float", -0.0},
      {"value", "Double", double},
      {"string_value", "String", "x\0é"},
      {"datetime_value", "DateTime", 132_541_920_000_000_001},
      {"guid_value", "Guid", "00112233-4455-6677-8899-aabbccddeeff"},
      {"bytestring_value", "ByteString", <<0, 255, 1>>},
      {"nodeid_value", "NodeId", context.node.("fixture")},
      {"status_code_value", "StatusCode", 0x4000_0000}
    ]

    for {identifier, type, expected} <- scalars do
      consumed = runtime_scalar_consumer(context.peer, context.node.(identifier), config)

      assert {:ok, %Result{payload: actual, metadata: %{opcua_type: ^type, status: 0}}} =
               ConsumedThing.read_property(consumed, "sample", runtime_context)

      assert actual == expected

      if type == "Float" do
        assert <<1::1, _::31>> = <<actual::float-32>>
      end
    end

    assert eventually(fn -> native_descendants() == baseline end)

    for {identifier, type, expected} <-
          Enum.filter(scalars, fn {_, type, _} ->
            type in ["DateTime", "Guid", "ByteString", "NodeId", "StatusCode"]
          end) do
      consumed = runtime_scalar_consumer(context.peer, context.node.(identifier), config)
      id = {:rust_runtime_scalar, identifier}

      assert {:ok, spec} =
               ConsumedThing.observation_child_spec(consumed, "sample", runtime_context,
                 id: id,
                 receiver: self(),
                 max_queue_length: 1000,
                 overflow: :stop,
                 restart: :temporary
               )

      owner = start_supervised!(spec, id: id)

      assert_receive {:wotex_runtime, ^id, {:ok, actual, %{opcua_type: ^type, status: 0}}},
                     5000

      assert actual == expected
      assert resources(context.session, context.node) == {1, 1}
      assert :ok = Subscription.stop(owner)
      assert eventually(fn -> resources(context.session, context.node) == {0, 0} end)
      assert eventually(fn -> native_descendants() == baseline end)
    end
  end

  for {number, fault} <- [
        {39, "expired_leaf"},
        {40, "wrong_host"},
        {41, "wrong_application_uri"},
        {42, "untrusted_ca"},
        {43, "revoked_leaf"},
        {44, "expired_crl"},
        {45, "mismatched_private_key"},
        {46, "none_downgrade"},
        {47, "unsupported_user_token"}
      ] do
    id = "WOP-X-F#{number}"

    @tag case: id, corpus_sha256: @corpus_sha256
    test "#{id} #{fault} rejects the independent Rust peer before application traffic", context do
      %{"input" => input, "expectation" => %{"value" => expected}} =
        Map.fetch!(@cases, unquote(id))

      assert input["fault"] == unquote(fault)
      assert input["independent_peer"] == "async-opcua-rust-peer-1"
      {options, peer} = fault_options(context, unquote(fault))
      began = System.monotonic_time(:millisecond)

      try do
        assert {:error, %Error{code: code, effect: :none}} =
                 Wotex.OPCUA.connect(Keyword.put(options, :timeout, 2000))

        assert System.monotonic_time(:millisecond) - began < 3000
        assert code in allowed_codes(unquote(fault))
        assert expected["authenticated"] == false
        assert expected["active_local_resources"] == 0
        assert eventually(fn -> native_descendants() == [] end)
      after
        stop_peer(peer)
      end

      assert expected["application_requests"] == peer_result(peer)["application_requests"]
    end
  end

  defp count(session, node, method) do
    assert {:ok, %{"outputs" => [%{"type" => "UInt32", "value" => value}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: node.(method),
               value: %{object_id: node.("fixture"), arguments: []}
             })

    value
  end

  defp republish_faults(session, node, withhold, discard) do
    assert {:ok,
            %{
              "outputs" => [
                %{"type" => "UInt32", "value" => withheld},
                %{"type" => "UInt32", "value" => republished}
              ]
            }} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: node.("republish_fault"),
               value: %{
                 object_id: node.("fixture"),
                 arguments: [
                   %{type: "UInt32", value: withhold},
                   %{type: "Boolean", value: discard}
                 ]
               }
             })

    {withheld, republished}
  end

  defp next_report(reference) do
    receive do
      {:wotex_opcua, ^reference, report} -> report
    after
      5000 -> flunk("timed out waiting for OPC UA report")
    end
  end

  defp node_resolver(session, namespace_uri) do
    assert {:ok, %{"value" => %{"type" => "String", "array" => true, "value" => namespaces}}} =
             Wotex.OPCUA.send(session, %{type: :read, node_id: "i=2255"})

    index = Enum.find_index(namespaces, &(&1 == namespace_uri))
    assert is_integer(index)
    &Address.to_string(%Address{namespace: index, kind: :string, identifier: &1})
  end

  defp write(session, node_id, value) do
    Wotex.OPCUA.send(session, %{
      type: :write,
      node_id: node_id,
      value: %{type: "Double", value: value}
    })
  end

  defp slow(node, milliseconds) do
    %{
      type: :call,
      node_id: node.("slow"),
      value: %{object_id: node.("fixture"), arguments: [%{type: "UInt32", value: milliseconds}]}
    }
  end

  defp resources(session, node) do
    assert {:ok,
            %{
              "outputs" => [
                %{"type" => "UInt32", "value" => subscriptions},
                %{"type" => "UInt32", "value" => items}
              ]
            }} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: node.("resources"),
               value: %{object_id: node.("fixture"), arguments: []}
             })

    {subscriptions, items}
  end

  defp browsed?(session, node) do
    case Browse.references(session, node.("fixture")) do
      {:ok, %Browse.Page{status: 0, continuation: nil, references: references}} ->
        Enum.any?(
          references,
          &(Address.to_string(&1.node_id.node_id) == node.("add"))
        )

      _ ->
        false
    end
  end

  defp token(_, "anonymous"), do: %{type: :anonymous}

  defp token(context, "username") do
    %{type: :username, username: context.peer["username"], password: context.peer["password"]}
  end

  defp token(context, "certificate") do
    %{
      type: :certificate,
      certificate: Path.join(context.fixture, "user.der"),
      private_key: Path.join(context.fixture, "user.key.der")
    }
  end

  defp runtime_consumers(peer, node, config) do
    href = peer["endpoint"] <> "?id=" <> URI.encode_www_form(node)

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:rust-peer",
        "title" => "Rust peer",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{
                "href" => href,
                "op" => [
                  "readproperty",
                  "writeproperty",
                  "observeproperty",
                  "unobserveproperty"
                ],
                "wotex:variantType" => "Double"
              }
            ]
          }
        }
      })

    {:ok, session_profile} = Wotex.OPCUA.profile(:session)

    {:ok, session} =
      ConsumedThing.new(td,
        profiles: [session_profile],
        transports: %{opcua_session: {Transport, config}},
        credentials: {TestNosecCredentials, nil}
      )

    {:ok, oneshot} =
      ConsumedThing.new(td,
        profiles: [Wotex.OPCUA.profile()],
        transports: %{opcua: {Transport, Keyword.put(config, :lifecycle, :oneshot)}},
        credentials: {TestNosecCredentials, nil}
      )

    {session, oneshot}
  end

  defp runtime_array_consumer(peer, node, config) do
    href = peer["endpoint"] <> "?id=" <> URI.encode_www_form(node)

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:rust-arrays",
        "title" => "Rust arrays",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "samples" => %{
            "type" => "array",
            "forms" => [%{"href" => href, "op" => ["readproperty", "writeproperty"]}]
          }
        }
      })

    {:ok, profile} = Wotex.OPCUA.profile(:session)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{opcua_session: {Transport, config}},
        credentials: {TestNosecCredentials, nil}
      )

    consumed
  end

  defp runtime_scalar_consumer(peer, node, config) do
    href = peer["endpoint"] <> "?id=" <> URI.encode_www_form(node)

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:rust-scalars",
        "title" => "Rust scalars",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "sample" => %{
            "observable" => true,
            "forms" => [
              %{
                "href" => href,
                "op" => ["readproperty", "observeproperty", "unobserveproperty"]
              }
            ]
          }
        }
      })

    {:ok, profile} = Wotex.OPCUA.profile(:session)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{opcua_session: {Transport, config}},
        credentials: {TestNosecCredentials, nil}
      )

    consumed
  end

  defp fault_options(context, fault) do
    directory = context.fixture
    anonymous = %{type: :anonymous}
    {peer, endpoint} = variant(context, fault)
    options = Keyword.put(context.options, :endpoint, endpoint)

    options =
      case fault do
        "expired_leaf" ->
          Keyword.put(options, :server_certificate, Path.join(directory, "expired.der"))

        "wrong_host" ->
          Keyword.put(options, :server_certificate, Path.join(directory, "wronghost.der"))

        "wrong_application_uri" ->
          Keyword.put(options, :server_uri, "urn:wotex:fixture:other")

        "untrusted_ca" ->
          Keyword.put(options, :trust_certificate, Path.join(directory, "other-ca.der"))

        "revoked_leaf" ->
          Keyword.put(options, :crl, Path.join(directory, "revoked.crl"))

        "expired_crl" ->
          Keyword.put(options, :crl, Path.join(directory, "expired.crl"))

        "mismatched_private_key" ->
          Keyword.put(options, :private_key, Path.join(directory, "other.key.der"))

        "unsupported_user_token" ->
          Keyword.put(options, :authentication, token(context, "username"))

        "none_downgrade" ->
          Keyword.put(options, :authentication, anonymous)
      end

    {options, peer}
  end

  defp variant(context, name) do
    executable = System.fetch_env!("WOTEX_OPCUA_RUST_EXECUTABLE")
    config = Path.join(context.fixture, "rust-config-#{name}.json")
    result = Path.join(context.fixture, "rust-result-#{name}.json")
    File.rm(config)
    File.rm(result)

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [context.fixture, Integer.to_string(context.peer["children"]), name]}
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    owned = %{port: port, pid: pid, result: result}
    on_exit(fn -> stop_peer(owned) end)
    await_ready(port, System.monotonic_time(:millisecond) + 15_000)
    peer = Jason.decode!(File.read!(config))
    {owned, peer["endpoint"]}
  end

  defp stop_peer(%{port: port, pid: pid}) do
    if Port.info(port), do: Port.close(port)

    unless eventually(fn -> not os_alive?(pid) end) do
      System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )
    end

    assert eventually(fn -> not os_alive?(pid) end)
  end

  defp peer_result(%{result: result}) do
    assert eventually(fn -> File.regular?(result) end)
    Jason.decode!(File.read!(result))
  end

  defp await_ready(port, deadline) do
    receive do
      {^port, {:data, {:eol, "rust peer ready"}}} -> :ok
      {^port, {:data, _}} -> await_ready(port, deadline)
      {^port, {:exit_status, status}} -> flunk("Rust variant peer exited: #{status}")
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("Rust variant peer did not become ready")
    end
  end

  defp allowed_codes("none_downgrade"),
    do: [:certificate_invalid, :authentication_failed, :connection_failed, :deadline_exceeded]

  defp allowed_codes(_),
    do: [:certificate_invalid, :authentication_failed, :connection_failed]

  defp native_descendants do
    {output, 0} =
      System.cmd("/bin/ps", ["-A", "-o", "pid=", "-o", "ppid=", "-o", "args="],
        env: [{"LC_ALL", "C"}]
      )

    rows =
      for line <- String.split(output, "\n", trim: true),
          [pid, ppid | arguments] <- [String.split(String.trim(line), ~r/\s+/)],
          do: {String.to_integer(pid), String.to_integer(ppid), List.first(arguments, "")}

    rows
    |> descendants([String.to_integer(System.pid())], [])
    |> Enum.filter(fn {_, executable} ->
      Path.basename(executable) in ["wotex_opcua_native", "wotex_opcua_custody"]
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp descendants(_, [], found), do: found

  defp descendants(rows, [parent | rest], found) do
    children = for {pid, ^parent, executable} <- rows, do: {pid, executable}

    descendants(
      rows,
      rest ++ Enum.map(children, &elem(&1, 0)),
      found ++ children
    )
  end

  defp native_processes(host) do
    %{port: port} = :sys.get_state(host)
    {:os_pid, guardian} = Port.info(port, :os_pid)

    {children, 0} =
      System.cmd("/usr/bin/pgrep", ["-P", Integer.to_string(guardian)], env: [{"LC_ALL", "C"}])

    [guardian | Enum.map(String.split(children), &String.to_integer/1)]
  end

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(pid), do: os_alive?(pid)

  defp drain(messages) do
    receive do
      message -> drain([message | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  defp os_alive?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )

    status == 0
  end

  defp eventually(check, attempts \\ 100) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(check, attempts - 1)
    end
  end
end
