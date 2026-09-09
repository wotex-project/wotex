defmodule Wotex.BACnet.CStackCOVTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.Test.CStackPeer
  @moduletag interop: true, software: true, capture_log: true
  @moduletag requirements: ["WBA-V13"]

  setup do
    before = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    session = CStackPeer.connect()
    writer = CStackPeer.connect()
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

  test "WBA-CP02 WBA-N02 WBA-N03 independent discovery, batch read and priority release", context do
    assert {:ok, [device]} = BACnet.who_is(context.session, 123, 123)
    assert device.instance == 123
    assert device.source == context.session.handle.stack.destination
    assert {:ok, properties} = BACnet.read_properties(context.session, 1, 1, [85, 77, 111])
    assert %Encoding{type: :real} = properties[85]
    assert %Encoding{type: :character_string} = properties[77]
    assert %Encoding{type: :bitstring} = properties[111]
    write(context.writer, Encoding.create!({:real, 42.5}))

    assert {:ok, %Encoding{type: :real, value: 42.5}} =
             BACnet.read_property(context.session, 1, 1, 85)

    assert CStackPeer.control()["priority"] == 16
    write(context.writer, Encoding.create!({:null, nil}))
    assert CStackPeer.control()["priority"] == 0
    assert CStackPeer.control()["who_is"] == context.before["who_is"] + 1
    close(context)
  end

  for confirmed <- [true, false] do
    @tag corpus_case_id: if(confirmed, do: "WBA-CP03", else: "WBA-CP04")
    test "#{if confirmed, do: "WBA-CP03", else: "WBA-CP04"} WBA-S04 independent object COV confirmed=#{confirmed}",
         context do
      confirmed = unquote(confirmed)

      request = %{
        type: :cov,
        object_type: 1,
        instance: 1,
        device_instance: 123,
        lifetime: 4,
        renew: false,
        confirmed: confirmed
      }

      assert {:ok, subscription} = BACnet.subscribe(context.session, request)
      reference = subscription.reference
      assert_receive {:wotex_bacnet, ^reference, {:ok, initial, metadata}}, 1000

      assert metadata.device_instance == 123 and metadata.object_type == 1 and
               metadata.instance == 1

      assert Enum.map(initial, & &1.property) |> Enum.sort() == [85, 111]
      assert metadata.report_values == initial
      value = property(initial, 85).value + 5.0
      write(context.writer, Encoding.create!({:real, value}))
      assert_receive {:wotex_bacnet, ^reference, {:ok, changed, changed_metadata}}, 1000
      assert property(changed, 85) == Encoding.create!({:real, value})
      assert %Encoding{type: :bitstring} = property(changed, 111)
      assert changed_metadata.process_identifier == metadata.process_identifier
      expected_acks = context.before["notification_acks"] + unquote(if confirmed, do: 2, else: 0)

      before_cancel =
        CStackPeer.await(
          &(&1["notification_acks"] == expected_acks and &1["active_invoke_ids"] == 0)
        )

      assert before_cancel["active_subscribers"] == 1
      assert before_cancel["registrations"] == context.before["registrations"] + 1
      monitor = Process.monitor(subscription.pid)
      assert :ok = BACnet.unsubscribe(context.session, subscription)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1100

      after_cancel =
        CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))

      assert after_cancel["cancellations"] == context.before["cancellations"] + 1
      assert after_cancel["control_acks"] == context.before["control_acks"] + 2
      write(context.writer, Encoding.create!({:null, nil}))
      refute_receive {:wotex_bacnet, ^reference, _}, 20
      close(context)
    end
  end

  test "WBA-CP05 WBA-S04 WBA-V09 finite renewal is observed in the independent registry",
       context do
    subscription = subscribe(context, lifetime: 4, renew: true)
    renewed = CStackPeer.await(&(&1["renewals"] > context.before["renewals"]), 2500)
    assert renewed["active_subscribers"] == 1
    assert renewed["registrations"] == context.before["registrations"] + 1
    assert :ok = BACnet.unsubscribe(context.session, subscription)
    CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    close(context)
  end

  test "WBA-CP06 WBA-S04 WBA-V11 lost registration ACK closes accepted server state", context do
    CStackPeer.control("fault register_ack 1")

    request = %{
      type: :cov,
      object_type: 1,
      instance: 1,
      device_instance: 123,
      lifetime: 4,
      renew: false,
      confirmed: false
    }

    assert {:error, %{code: :deadline_exceeded, effect: :none}} =
             BACnet.subscribe(context.session, request)

    after_cancel = CStackPeer.await(&(&1["active_subscribers"] == 0))
    assert after_cancel["registrations"] == context.before["registrations"] + 1
    assert after_cancel["dropped_acks"] == context.before["dropped_acks"] + 1
    assert after_cancel["cancellations"] == context.before["cancellations"] + 1
    assert after_cancel["active_invoke_ids"] == 0
    close(context)
  end

  test "WBA-CP07 WBA-S04 WBA-V09 lost renewal ACK cannot extend the established lease", context do
    subscription = subscribe(context, lifetime: 4, renew: true)
    reference = subscription.reference
    monitor = Process.monitor(subscription.pid)
    CStackPeer.control("fault renew_ack 1")
    renewed = CStackPeer.await(&(&1["renewals"] > context.before["renewals"]), 2500)
    assert renewed["active_subscribers"] == 1
    assert renewed["dropped_acks"] == context.before["dropped_acks"] + 1
    assert_receive {:wotex_bacnet, ^reference, {:error, error}}, 2100
    assert error.code == :deadline_exceeded
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1100
    after_cancel = CStackPeer.await(&(&1["active_subscribers"] == 0))
    assert after_cancel["cancellations"] == context.before["cancellations"] + 1
    close(context)
  end

  test "WBA-CP08 WBA-C03 lost cancellation ACK retains the unknown result after local release",
       context do
    subscription = subscribe(context)
    monitor = Process.monitor(subscription.pid)
    CStackPeer.control("fault cancel_ack 1")
    started = System.monotonic_time(:millisecond)
    assert {:error, %{code: :deadline_exceeded}} = BACnet.unsubscribe(context.session, subscription)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 100
    assert System.monotonic_time(:millisecond) - started <= 1100
    snapshot = CStackPeer.control()
    assert snapshot["active_subscribers"] == 0
    assert snapshot["dropped_acks"] == context.before["dropped_acks"] + 1
    assert snapshot["cancellations"] == context.before["cancellations"] + 1
    close(context)
  end

  test "WBA-CP09 WBA-C03 local close and server expiry are separate after a lost cancellation",
       context do
    subscription = subscribe(context)
    monitor = Process.monitor(subscription.pid)
    CStackPeer.control("fault cancel_request 1")
    started = System.monotonic_time(:millisecond)
    assert {:error, %{code: :deadline_exceeded}} = BACnet.unsubscribe(context.session, subscription)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 100
    assert System.monotonic_time(:millisecond) - started <= 1100
    local_closed = CStackPeer.control()
    assert local_closed["active_subscribers"] == 1
    assert local_closed["dropped_requests"] == context.before["dropped_requests"] + 1
    assert local_closed["cancellations"] == context.before["cancellations"]
    close(context)
    expired = CStackPeer.await(&(&1["active_subscribers"] == 0), 4100)
    assert expired["active_invoke_ids"] == 0
    assert expired["cancellations"] == context.before["cancellations"]
  end

  defp subscribe(context, options \\ []) do
    request = %{
      type: :cov,
      object_type: 1,
      instance: 1,
      device_instance: 123,
      lifetime: 4,
      renew: false,
      confirmed: false
    }

    assert {:ok, subscription} = BACnet.subscribe(context.session, Enum.into(options, request))
    reference = subscription.reference
    assert_receive {:wotex_bacnet, ^reference, {:ok, _, _}}, 1000
    subscription
  end

  defp property(values, id), do: Enum.find(values, &(&1.property == id)).value

  defp write(session, value) do
    assert {:ok, :written} =
             BACnet.send(session, %{
               type: :write_property,
               object_type: 1,
               instance: 1,
               property: 85,
               priority: 16,
               value: value
             })
  end

  defp close(context) do
    CStackPeer.close(context.session, context.resources)
    CStackPeer.close(context.writer, context.writer_resources)
  end
end
