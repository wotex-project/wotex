defmodule Wotex.BACnet.NativeSubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, COVRequest, Error, IPv4, NativeSubscription, Session}
  alias Wotex.BACnet.Test.{DiscoveryPeer, RuntimeClient}

  @request %{type: :cov_property, device_instance: 123, object_type: 1, instance: 7, property: 85}

  test "WBA-C03 WBA-I04 absolute subscription deadline bounds the callback and reclaims its late handle" do
    {:ok, session} = BACnet.connect(client: RuntimeClient, test_owner: self(), timeout: 1000)
    assert_receive {:native_connect, _}
    deadline = System.monotonic_time(:millisecond) + 80
    opening = Task.async(fn -> BACnet.subscribe_deadline(session, @request, deadline) end)
    assert_receive {:native_open, worker, _, subscription, timeout}
    assert timeout > 0 and timeout <= 80
    Process.sleep(max(deadline - System.monotonic_time(:millisecond), 0) + 1)
    send(worker, {:release, :ok})
    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} = Task.await(opening)
    assert_receive {:native_cancel, ^worker, ^subscription, 1000}
    monitor = Process.monitor(subscription.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_receive {:native_disconnect, _}, 0
    assert :ok = BACnet.disconnect(session)
    assert_receive {:native_disconnect, _}
  end

  test "WBA-C03 expired and malformed native subscriptions invoke no callback" do
    session = %Session{client: RuntimeClient, handle: self(), timeout: 1000}
    expired = System.monotonic_time(:millisecond) - 1

    assert {:error, %Error{code: :deadline_exceeded}} =
             BACnet.subscribe_deadline(session, @request, expired)

    assert {:error, %Error{code: :invalid_subscription}} =
             BACnet.subscribe_deadline(session, %{}, expired)

    for forged <- [
          nil,
          %{session | timeout: 0},
          %{session | client: nil},
          %{session | client: "module"}
        ] do
      assert {:error, %Error{code: :invalid_subscription}} =
               NativeSubscription.open(forged, @request, expired)
    end

    assert {:error, %Error{code: :invalid_subscription}} =
             NativeSubscription.open(session, @request, nil)

    refute_receive {:native_open, _, _, _, _}, 0
    refute_receive {:native_cancel, _, _, _}, 0
  end

  test "WBA-C03 first-party subscription adapters retain exact deadline and reject forged shapes" do
    deadline = System.monotonic_time(:millisecond) - 1
    {:ok, request} = COVRequest.new(@request, self())
    {:ok, client} = DiscoveryPeer.start_link(owner: self())

    {:ok, handle} =
      BACstack.connect(
        stack_client: client,
        stack_client_kind: :wotex,
        destination: {{127, 0, 0, 1}, 47_808},
        timeout: 1000
      )

    for client_module <- [BACstack, IPv4] do
      wrapped = if client_module == IPv4, do: %{stack: handle}, else: handle

      assert {:error, %Error{code: :deadline_exceeded}} =
               client_module.subscribe_deadline(wrapped, request, self(), deadline, 1000)

      assert {:error, %Error{code: :invalid_subscription}} =
               client_module.subscribe_deadline(nil, request, self(), deadline, 1000)
    end

    for {request, receiver, timeout} <- [
          {request, spawn_receiver(), 1000},
          {%{request | confirmed: nil}, self(), 1000},
          {request, self(), 0}
        ] do
      assert {:error, %Error{code: :invalid_subscription}} =
               BACstack.subscribe_deadline(handle, request, receiver, deadline, timeout)

      if receiver != self(), do: send(receiver, :stop)
    end

    assert DiscoveryPeer.snapshot(client).actions == []
    assert :ok = BACstack.disconnect(handle)
    assert Process.alive?(client)
  end

  defp spawn_receiver, do: spawn(fn -> receive do: (:stop -> :ok) end)
end
