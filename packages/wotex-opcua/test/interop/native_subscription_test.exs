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

    assert {:ok, session} =
             Wotex.OPCUA.connect(
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
             )

    {:ok, original} = read(session, peer["node_id"])
    %{session: session, peer: peer, original: original}
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

  defp resources(session, peer) do
    assert {:ok, %{"status" => 0, "outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
             Wotex.OPCUA.send(session, %{
               type: :call,
               node_id: peer["resources_method_id"],
               value: %{object_id: peer["object_id"], arguments: []}
             })

    {subscriptions, items}
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
