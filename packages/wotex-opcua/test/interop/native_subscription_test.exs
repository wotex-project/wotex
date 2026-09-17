defmodule Wotex.OPCUA.NativeSubscriptionInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session, Subscription}
  @moduletag :interop

  setup do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config))
    directory = Path.dirname(config)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    options = [
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

    assert {:ok, session} = Wotex.OPCUA.connect(options)
    {:ok, original} = read(session, peer["node_id"])
    %{session: session, peer: peer, original: original, options: options}
  end

  test "WOP-S04 a monitored Value delivers the initial and each fresh report once", context do
    %{session: session, peer: peer} = context
    request = %{node_id: peer["node_id"], publishing_interval_ms: 50, sampling_interval_ms: 0}
    assert {:ok, %Subscription{} = subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert inspect(subscription) =~ "Subscription"
    refute inspect(subscription) =~ inspect(reference)

    assert_receive {:wotex_opcua, ^reference, {:ok, initial, metadata}}, 5000
    assert %{"has_value" => true, "value" => %{"type" => "Double", "value" => first}} = initial
    assert first == context.original

    assert %{
             "sequence" => sequence,
             "client_handle" => handle,
             "overflow" => false,
             "datetime_resolution_ns" => 100,
             "raw_datetime_ticks_available" => true
           } = metadata

    for value <- [11.25, 12.5] do
      assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], value)

      assert_receive {:wotex_opcua, ^reference, {:ok, %{"value" => %{"value" => ^value}}, next}},
                     5000

      assert next["sequence"] > sequence and next["client_handle"] == handle
    end

    assert {1, 1} = resources(session, peer)

    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert {0, 0} = resources(session, peer)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], context.original)
    refute_receive {:wotex_opcua, ^reference, _}, 500
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-C05 receiver death cancels only its subscription and the Session stays usable",
       context do
    %{session: session, peer: peer} = context

    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    request = %{node_id: peer["node_id"], receiver: receiver, publishing_interval_ms: 50}
    assert {:ok, lost} = Wotex.OPCUA.subscribe(session, request)
    assert {:ok, kept} = Wotex.OPCUA.subscribe(session, %{node_id: peer["byte_node_id"]})
    kept_reference = kept.reference
    assert_receive {:wotex_opcua, ^kept_reference, {:ok, _, _}}, 5000
    %Session{handle: %{host: host}} = session
    Process.exit(receiver, :kill)

    assert eventually(fn ->
             state = :sys.get_state(host)
             not Map.has_key?(state.subscriptions, lost.reference) and map_size(state.controls) == 0
           end)

    assert :ok = Wotex.OPCUA.unsubscribe(session, lost)
    assert {1, 1} = resources(session, peer)
    assert {:ok, _} = read(session, peer["node_id"])
    assert :ok = Wotex.OPCUA.unsubscribe(session, kept)
    assert {0, 0} = resources(session, peer)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-C05 a full receiver queue ends delivery with one receiver_overflow", context do
    %{session: session, peer: peer} = context
    test = self()

    receiver =
      spawn(fn ->
        receive do
          :drain -> send(test, {:drained, drain([])})
        end
      end)

    request = %{
      node_id: peer["node_id"],
      receiver: receiver,
      publishing_interval_ms: 20,
      sampling_interval_ms: 0,
      max_queue_length: 2
    }

    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)

    for value <- [21.0, 22.0, 23.0, 24.0] do
      assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], value)
      Process.sleep(120)
    end

    %Session{handle: %{host: host}} = session

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
    assert {0, 0} = resources(session, peer)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], context.original)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-S04 a withheld notification is recovered once through Republish in order",
       context do
    %{session: session, peer: peer} = context
    request = %{node_id: peer["node_id"], publishing_interval_ms: 50, sampling_interval_ms: 0}
    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert {:ok, _, %{"sequence" => initial}} = next_report(reference)
    {before, republished} = faults(session, peer, 1, false)
    count = before + 1
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], 31.0)
    assert eventually(fn -> match?({^count, _}, faults(session, peer, 0, false)) end)
    refute_receive {:wotex_opcua, ^reference, _}, 100
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], 32.0)
    withheld = initial + 1
    fresh = initial + 2

    assert {:ok, %{"value" => %{"value" => 31.0}}, %{"sequence" => ^withheld}} =
             next_report(reference)

    assert {:ok, %{"value" => %{"value" => 32.0}}, %{"sequence" => ^fresh}} =
             next_report(reference)

    expected = republished + 1
    assert {^count, ^expected} = faults(session, peer, 0, false)
    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert {0, 0} = resources(session, peer)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], context.original)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-S04 an unavailable Republish ends only that subscription with sequence_gap",
       context do
    %{session: session, peer: peer} = context
    request = %{node_id: peer["node_id"], publishing_interval_ms: 50, sampling_interval_ms: 0}
    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert {:ok, _, _} = next_report(reference)
    assert {withheld, _} = faults(session, peer, 1, true)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], 33.0)
    expected = withheld + 1
    assert eventually(fn -> match?({^expected, _}, faults(session, peer, 0, false)) end)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], 34.0)

    assert {:error, %Error{code: :sequence_gap, effect: :none}} = next_report(reference)
    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert eventually(fn -> resources(session, peer) == {0, 0} end)
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], context.original)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-S04 a peer StatusChangeNotification ends the subscription as subscription_lost",
       context do
    %{session: session, peer: peer} = context
    request = %{node_id: peer["node_id"], publishing_interval_ms: 50, sampling_interval_ms: 0}
    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert {:ok, _, _} = next_report(reference)

    assert {:ok, %{"status" => 0, "outputs" => [%{"value" => 1}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: peer["loss_method_id"],
               value: %{object_id: peer["object_id"], arguments: []}
             })

    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], 35.0)

    assert {:error, %Error{code: :subscription_lost, details: %{status: 0x800A_0000}}} =
             next_report(reference)

    refute_receive {:wotex_opcua, ^reference, _}, 300
    assert eventually(fn -> resources(session, peer) == {0, 0} end)
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert {:ok, %{"status" => 0}} = write(session, peer["node_id"], context.original)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-S05 health uses a concrete Read and reports a missing node", context do
    %{session: session, peer: peer} = context
    assert :ok = Wotex.OPCUA.health_check(session, %{node_id: peer["node_id"]})

    assert {:error, %Error{code: :remote_error, details: %{status: status}}} =
             Wotex.OPCUA.health_check(session, %{node_id: "ns=2;s=missing"})

    assert Bitwise.band(status, 0x8000_0000) != 0
    assert :ok = Wotex.OPCUA.health_check(session, %{node_id: peer["node_id"]})
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-S04 a Bad acknowledgement status closes the Session and its peer subscriptions",
       context do
    %{session: session, peer: peer} = context
    %Session{handle: %{host: host}} = session
    request = %{node_id: peer["node_id"], publishing_interval_ms: 50, sampling_interval_ms: 0}
    assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
    reference = subscription.reference
    assert {:ok, _, _} = next_report(reference)
    {:ok, observer} = observer(context)

    assert {:ok, %{"outputs" => [%{"value" => 1}]}} =
             Wotex.OPCUA.send(observer, %{
               type: :call,
               node_id: peer["acks_method_id"],
               value: %{object_id: peer["object_id"], arguments: [%{type: "UInt32", value: 1}]}
             })

    monitor = Process.monitor(host)
    assert {:ok, %{"status" => 0}} = write(observer, peer["node_id"], 36.0)
    assert {:ok, _, _} = next_report(reference)
    assert {:ok, %{"status" => 0}} = write(observer, peer["node_id"], 37.0)
    assert {:error, %Error{code: :invalid_response, effect: :none}} = next_report(reference)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 5000
    refute_receive {:wotex_opcua, ^reference, _}, 100
    assert eventually(fn -> resources(observer, peer) == {0, 0} end)
    assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
    assert {:ok, %{"status" => 0}} = write(observer, peer["node_id"], context.original)
    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  test "WOP-S04 invalid requests and one-shot handles acquire no subscription", context do
    %{session: session, peer: peer} = context

    for request <- [
          %{node_id: peer["node_id"], queue_size: 0},
          %{node_id: peer["node_id"], keepalive_count: 10, lifetime_count: 29},
          %{node_id: peer["node_id"], unknown: true},
          %{node_id: "not a node"}
        ] do
      assert {:error, %Error{code: :invalid_value}} = Wotex.OPCUA.subscribe(session, request)
    end

    assert {:error, %Error{code: :remote_error}} =
             Wotex.OPCUA.subscribe(session, %{node_id: "ns=2;s=missing"})

    %Session{handle: %{host: host}} = session
    assert :sys.get_state(host).subscriptions == %{}
    assert {0, 0} = resources(session, peer)
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  defp observer(context), do: Wotex.OPCUA.connect(context.options)

  defp resources(session, peer) do
    assert {:ok, %{"status" => 0, "outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: peer["resources_method_id"],
               value: %{object_id: peer["object_id"], arguments: []}
             })

    {subscriptions, items}
  end

  defp faults(session, peer, withhold, discard) do
    assert {:ok, %{"status" => 0, "outputs" => [%{"value" => withheld}, %{"value" => republished}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: peer["faults_method_id"],
               value: %{
                 object_id: peer["object_id"],
                 arguments: [%{type: "UInt32", value: withhold}, %{type: "Boolean", value: discard}]
               }
             })

    {withheld, republished}
  end

  defp next_report(reference) do
    receive do
      {:wotex_opcua, ^reference, {:ok, value, metadata}} -> {:ok, value, metadata}
      {:wotex_opcua, ^reference, {:error, error}} -> {:error, error}
    after
      5000 -> flunk("no subscription report")
    end
  end

  defp drain(messages) do
    receive do
      message -> drain([message | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  defp read(session, node) do
    case Wotex.OPCUA.send(session, %{type: :read, node_id: node}) do
      {:ok, %{"value" => %{"value" => value}}} -> {:ok, value}
      other -> other
    end
  end

  defp write(session, node, value),
    do:
      Wotex.OPCUA.send(session, %{
        type: :write,
        node_id: node,
        value: %{type: "Double", value: value}
      })

  defp eventually(check, attempts \\ 300) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(check, attempts - 1)
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
