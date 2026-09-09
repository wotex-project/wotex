defmodule Wotex.BACnet.CStackPropertyTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.Test.{CStackPeer, RuntimeCredentials}
  alias Wotex.Runtime.{ConsumedThing, Context, Subscription}
  @moduletag interop: true, software: true, capture_log: true
  @moduletag requirements: ["WBA-S04", "WBA-V13"]

  setup do
    CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    session = CStackPeer.connect()
    writer = CStackPeer.connect()
    write(writer, 85, Encoding.create!({:real, 0.0}))
    write(writer, 81, Encoding.create!({:boolean, false}))
    before = CStackPeer.control()
    resources = CStackPeer.resources(session)
    writer_resources = CStackPeer.resources(writer)

    on_exit(fn ->
      BACnet.disconnect(session)
      BACnet.disconnect(writer)
    end)

    %{
      session: session,
      writer: writer,
      resources: resources,
      writer_resources: writer_resources,
      before: before
    }
  end

  for confirmed <- [true, false] do
    @tag corpus_case_id: if(confirmed, do: "WBA-CP11", else: "WBA-CP12")
    test "#{if confirmed, do: "WBA-CP11", else: "WBA-CP12"} Property COV confirmed=#{confirmed} respects increments and Status_Flags",
         context do
      subscription = subscribe(context.session, confirmed: unquote(confirmed), cov_increment: 0.25)
      reference = subscription.reference
      assert_receive {:wotex_bacnet, ^reference, {:ok, %Encoding{value: +0.0}, initial}}, 1000
      assert Enum.map(initial.report_values, & &1.property) == [85, 111]
      write(context.writer, 85, Encoding.create!({:real, 0.125}))
      refute_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 100
      write(context.writer, 85, Encoding.create!({:real, 0.25}))
      assert_receive {:wotex_bacnet, ^reference, {:ok, %Encoding{value: 0.25}, threshold}}, 1000
      assert threshold.process_identifier == initial.process_identifier
      write(context.writer, 81, Encoding.create!({:boolean, true}))
      assert_receive {:wotex_bacnet, ^reference, {:ok, %Encoding{value: 0.25}, status}}, 1000

      assert %{value: %Encoding{type: :bitstring, value: {false, false, false, true}}} =
               Enum.find(status.report_values, &(&1.property == 111))

      expected_acks = context.before["notification_acks"] + unquote(if confirmed, do: 3, else: 0)

      snapshot =
        CStackPeer.await(
          &(&1["notification_acks"] == expected_acks and &1["active_invoke_ids"] == 0)
        )

      assert snapshot["property_subscribers"] == 1 and snapshot["object_subscribers"] == 0
      cancel(context.session, subscription)
      close(context)
    end
  end

  test "WBA-CP13 Status_Flags subscription cannot acquire Present_Value reports", context do
    subscription = subscribe(context.session, property: 111)
    reference = subscription.reference
    assert_receive {:wotex_bacnet, ^reference, {:ok, %Encoding{type: :bitstring}, initial}}, 1000
    assert Enum.map(initial.report_values, & &1.property) == [111]
    write(context.writer, 85, Encoding.create!({:real, 5.0}))
    refute_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 100
    write(context.writer, 81, Encoding.create!({:boolean, true}))

    assert_receive {:wotex_bacnet, ^reference,
                    {:ok, %Encoding{type: :bitstring, value: {false, false, false, true}}, flags}},
                   1000

    assert Enum.map(flags.report_values, & &1.property) == [111]
    cancel(context.session, subscription)
    close(context)
  end

  test "WBA-CP14 WBA-V08 WBA-V09 equal unconfirmed Property reports remain fresh after renewal",
       context do
    subscription = subscribe(context.session, lifetime: 4, renew: true)
    reference = subscription.reference
    assert_receive {:wotex_bacnet, ^reference, {:ok, initial, _}}, 1000
    assert_receive {:wotex_bacnet, ^reference, {:ok, ^initial, _}}, 2500
    snapshot = CStackPeer.control()
    assert snapshot["renewals"] == context.before["renewals"] + 1
    assert snapshot["property_subscribers"] == 1
    assert snapshot["notification_acks"] == context.before["notification_acks"]
    cancel(context.session, subscription)
    close(context)
  end

  test "WBA-CP15 Property COV capacity rejects a seventeenth record without eviction", context do
    subscriptions =
      for _ <- 1..16 do
        subscription = subscribe(context.session)
        reference = subscription.reference
        assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
        subscription
      end

    request = %{
      type: :cov_property,
      object_type: 1,
      instance: 1,
      property: 85,
      device_instance: 123,
      confirmed: false,
      lifetime: 4,
      renew: false
    }

    assert {:error, %{code: :remote_error}} = BACnet.subscribe(context.session, request)
    assert CStackPeer.control()["property_subscribers"] == 16
    write(context.writer, 85, Encoding.create!({:real, 5.0}))

    for subscription <- subscriptions do
      reference = subscription.reference
      assert_receive {:wotex_bacnet, ^reference, {:ok, %Encoding{value: 5.0}, _}}, 1000
    end

    for subscription <- subscriptions,
        do: assert(:ok == BACnet.unsubscribe(context.session, subscription))

    assert CStackPeer.await(&(&1["active_subscribers"] == 0))["property_subscribers"] == 0
    close(context)
  end

  test "WBA-CP16 unsupported Property COV selectors create no server subscription", context do
    for selector <- [%{property: 77}, %{instance: 999}, %{array_index: 0}] do
      request = %{
        type: :cov_property,
        object_type: 1,
        instance: 1,
        property: 85,
        device_instance: 123,
        confirmed: false,
        lifetime: 4,
        renew: false
      }

      assert {:error, %{code: :remote_error}} =
               BACnet.subscribe(context.session, Map.merge(request, selector))

      assert CStackPeer.control()["active_subscribers"] == 0
    end

    assert CStackPeer.control()["registrations"] == context.before["registrations"]
    close(context)
  end

  test "WBA-CP17 WBA-I05 WBA-V12 public Runtime observes and stops the original C-peer Property association",
       context do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "C peer Property observation",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{"href" => "bacnet://123/1,1/85", "op" => "observeproperty"},
              %{"href" => "bacnet://999/2,8/85", "op" => "unobserveproperty"}
            ]
          }
        }
      })

    {:ok, profile} = BACnet.profile(:ip_cov)

    options =
      CStackPeer.options(target: "123", cov: %{lifetime: 4, renew: false, cov_increment: 0.25})

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{bacnet_cov: {BACnet.Transport, options}},
        credentials: {RuntimeCredentials, []}
      )

    {:ok, execution} = Context.new(request_id: "c-property")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "reading", execution,
        id: :c_property,
        receiver: self(),
        restart: :temporary,
        max_queue_length: 1000,
        overflow: :stop
      )

    owner = start_supervised!(spec)
    assert_receive {:wotex_runtime, :c_property, {:ok, +0.0, initial}}, 1000
    assert initial.device_instance == 123 and initial.property == 85
    write(context.writer, 85, Encoding.create!({:real, 0.25}))
    assert_receive {:wotex_runtime, :c_property, {:ok, 0.25, changed}}, 1000
    assert changed.process_identifier == initial.process_identifier
    assert changed.device_instance == 123 and changed.property == 85
    assert :ok = Subscription.stop(owner)
    snapshot = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    assert snapshot["cancellations"] == context.before["cancellations"] + 1
    assert snapshot["property_subscribers"] == 0
    close(context)
  end

  test "WBA-CP18 WBA-V11 lost Property registration ACK cancels accepted server state", context do
    CStackPeer.control("fault register_ack 1")

    assert {:error, %{code: :deadline_exceeded, effect: :none}} =
             BACnet.subscribe(context.session, request())

    snapshot = CStackPeer.await(&(&1["active_subscribers"] == 0))
    assert snapshot["registrations"] == context.before["registrations"] + 1
    assert snapshot["dropped_acks"] == context.before["dropped_acks"] + 1
    assert snapshot["cancellations"] == context.before["cancellations"] + 1
    assert snapshot["active_invoke_ids"] == 0
    close(context)
  end

  test "WBA-CP19 WBA-V09 lost Property renewal ACK terminates and cancels its exact record",
       context do
    subscription = subscribe(context.session, renew: true)
    reference = subscription.reference
    monitor = Process.monitor(subscription.pid)
    assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
    CStackPeer.control("fault renew_ack 1")
    snapshot = CStackPeer.await(&(&1["renewals"] > context.before["renewals"]), 2500)
    assert snapshot["property_subscribers"] == 1
    assert snapshot["dropped_acks"] == context.before["dropped_acks"] + 1
    assert_receive {:wotex_bacnet, ^reference, {:error, %{code: :deadline_exceeded}}}, 2100
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1100
    refute_receive {:wotex_bacnet, ^reference, {:error, _}}, 20
    cancelled = CStackPeer.await(&(&1["active_subscribers"] == 0))
    assert cancelled["cancellations"] == context.before["cancellations"] + 1
    assert cancelled["active_invoke_ids"] == 0
    close(context)
  end

  test "WBA-CP20 WBA-C03 lost Property cancel ACK preserves failure after server deletion",
       context do
    subscription = subscribe(context.session)
    reference = subscription.reference
    monitor = Process.monitor(subscription.pid)
    assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
    CStackPeer.control("fault cancel_ack 1")
    started = System.monotonic_time(:millisecond)
    assert {:error, %{code: :deadline_exceeded}} = BACnet.unsubscribe(context.session, subscription)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 100
    assert System.monotonic_time(:millisecond) - started <= 1100
    snapshot = CStackPeer.control()
    assert snapshot["active_subscribers"] == 0 and snapshot["active_invoke_ids"] == 0
    assert snapshot["cancellations"] == context.before["cancellations"] + 1
    assert snapshot["dropped_acks"] == context.before["dropped_acks"] + 1
    close(context)
  end

  test "WBA-CP21 WBA-C03 lost Property cancellation leaves a finite remote lease", context do
    subscription = subscribe(context.session)
    reference = subscription.reference
    monitor = Process.monitor(subscription.pid)
    assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
    CStackPeer.control("fault cancel_request 1")
    started = System.monotonic_time(:millisecond)
    assert {:error, %{code: :deadline_exceeded}} = BACnet.unsubscribe(context.session, subscription)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 100
    assert System.monotonic_time(:millisecond) - started <= 1100
    snapshot = CStackPeer.control()
    assert snapshot["property_subscribers"] == 1
    assert snapshot["dropped_requests"] == context.before["dropped_requests"] + 1
    assert snapshot["cancellations"] == context.before["cancellations"]
    close(context)
    expired = CStackPeer.await(&(&1["active_subscribers"] == 0), 4100)
    assert expired["active_invoke_ids"] == 0
    assert expired["cancellations"] == context.before["cancellations"]
  end

  defp subscribe(session, options \\ []) do
    assert {:ok, subscription} = BACnet.subscribe(session, Enum.into(options, request()))
    subscription
  end

  defp request do
    %{
      type: :cov_property,
      object_type: 1,
      instance: 1,
      property: 85,
      device_instance: 123,
      confirmed: false,
      lifetime: 4,
      renew: false
    }
  end

  defp cancel(session, subscription) do
    monitor = Process.monitor(subscription.pid)
    assert :ok = BACnet.unsubscribe(session, subscription)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1100
    CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
  end

  defp write(session, property, value) do
    request = %{
      type: :write_property,
      object_type: 1,
      instance: 1,
      property: property,
      value: value
    }

    request = if property == 85, do: Map.put(request, :priority, 16), else: request
    assert {:ok, :written} = BACnet.send(session, request)
  end

  defp close(context) do
    write(context.writer, 81, Encoding.create!({:boolean, false}))
    write(context.writer, 85, Encoding.create!({:null, nil}))
    CStackPeer.close(context.session, context.resources)
    CStackPeer.close(context.writer, context.writer_resources)
  end
end
