defmodule Wotex.BACnet.COVBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, COVListener, COVRequest, COVWire, Error, IPv4, OperationOwner}
  alias Wotex.BACnet.{Subscription, Tags, TestClient}
  alias Wotex.BACnet.Test.COVFaultClient
  @request %{type: :cov, object_type: 1, instance: 0, device_instance: 123, lifetime: 2}
  @destination {{127, 0, 0, 1}, 55_828}

  test "WBA-C01 WBA-S04 optional custom-client callbacks fail explicitly after whole-input validation" do
    {:ok, session} = BACnet.connect(client: TestClient)
    assert {:error, %Error{code: :not_supported}} = BACnet.subscribe(session, @request)
    assert {:error, %Error{code: :not_supported}} = BACnet.unsubscribe(session, handle())

    assert {:error, %Error{code: :not_supported}} =
             BACnet.subscribe(%{session | client: MissingClient}, @request)

    assert {:error, %Error{code: :invalid_subscription}} = BACnet.subscribe(nil, @request)
    assert {:error, %Error{code: :invalid_subscription}} = BACnet.unsubscribe(nil, handle())

    assert {:error, %Error{code: :invalid_subscription}} =
             BACnet.subscribe(session, Map.delete(@request, :device_instance))

    assert {:error, %Error{code: :invalid_subscription}} =
             BACnet.subscribe(session, %{@request | lifetime: 0})

    assert :ok = BACnet.disconnect(session)
  end

  test "WBA-S04 WBA-V06 raw borrowed SDK boundaries reject COV before local registration" do
    client = start_supervised!({COVFaultClient, self()})

    {:ok, session} =
      BACnet.connect(client: BACstack, stack_client: client, destination: @destination)

    assert {:error, %Error{code: :not_supported}} = BACnet.subscribe(session, @request)
    assert :sys.get_state(session.handle.owner).subscriptions == %{}
    refute_receive {:fault_call, _, _, _}, 20
    assert :ok = BACnet.disconnect(session)
    assert Process.alive?(client)
  end

  test "WBA-C05 WBA-S04 invalid native handles and receiver mismatches never reach a client" do
    {:ok, request} = COVRequest.new(@request, self())
    client = start_supervised!({COVFaultClient, self()})
    config = %{owner: client, generation: make_ref()}
    assert {:error, %Error{}} = BACstack.subscribe(nil, request, self(), 100)
    assert {:error, %Error{}} = BACstack.subscribe(config, %{request | lifetime: 0}, self(), 100)
    assert {:error, %Error{}} = BACstack.subscribe(config, request, client, 100)
    assert {:error, %Error{}} = BACstack.unsubscribe(config, :invalid, 100)
    assert {:error, %Error{}} = BACstack.unsubscribe(nil, handle(), 100)
    assert {:error, %Error{}} = IPv4.subscribe(nil, request, self(), 100)
    assert {:error, %Error{}} = IPv4.unsubscribe(nil, handle(), 100)
    refute_receive {:fault_call, _, _, _}, 20

    assert {:error, %Error{code: :transport_error}} =
             COVWire.exchange(%{}, request, 7, now() + 100, false)

    assert {:error, %Error{code: :invalid_subscription}} =
             COVWire.exchange(%{}, %{request | lifetime: 0}, 7, now() + 100, false)
  end

  test "WBA-C03 WBA-S04 dead session owner calls return promptly without unsafe fallback" do
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    subscription = handle()
    {:ok, request} = COVRequest.new(@request, self())

    assert {:error, %Error{code: :connection_closed}} =
             OperationOwner.subscribe(
               dead,
               subscription.session_generation,
               request,
               now() + 100,
               100
             )

    assert {:error, %Error{code: :connection_closed}} =
             OperationOwner.unsubscribe(
               dead,
               subscription.session_generation,
               subscription,
               now() + 100
             )
  end

  test "WBA-C03 WBA-S04 local listener rejects invalid registration replies and times out finitely" do
    for result <- [{:error, Error.new(:busy)}, {:ok, :bad}, :invalid] do
      client = start_supervised!({COVFaultClient, self()})
      listener = listener(client, 100)
      monitor = Process.monitor(listener)

      assert_receive {:fault_call, ^client, {:wotex_client, :register_cov, _, @destination, _},
                      from}

      GenServer.reply(from, result)
      assert_receive {:cov_listener_error, ^listener, %Error{}}, 100
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 100
      assert_receive {:fault_call, ^client, {:wotex_client, :unregister_cov}, _}
      stop_supervised!(COVFaultClient)
    end

    client = start_supervised!({COVFaultClient, self()})
    listener = listener(client, 10)
    assert_receive {:fault_call, ^client, {:wotex_client, :register_cov, _, @destination, _}, from}
    send(listener, :unrelated)
    assert_receive {:cov_listener_error, ^listener, %Error{code: :deadline_exceeded}}, 100
    GenServer.reply(from, {:ok, 9})
    refute_receive {:cov_listener, ^listener, _}, 20
  end

  test "WBA-C03 WBA-S04 local listener tracks owner and client death while registration is pending" do
    client = start_supervised!({COVFaultClient, self()})
    listener = listener(client, 1000)
    assert_receive {:fault_call, ^client, {:wotex_client, :register_cov, _, @destination, _}, _}
    stop_supervised!(COVFaultClient)
    assert_receive {:cov_listener_error, ^listener, %Error{code: :connection_closed}}, 100

    client = start_supervised!({COVFaultClient, self()})

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    listener = listener(client, 1000, owner)
    monitor = Process.monitor(listener)
    assert_receive {:fault_call, ^client, {:wotex_client, :register_cov, _, @destination, _}, _}
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 100
  end

  test "WBA-C04 WBA-S04 failed confirmed report acknowledgments never deliver a successful value" do
    for failure <- [:error, :dead_client, :bad_reference] do
      client = start_supervised!({COVFaultClient, self()})
      listener = ready_listener(client)
      reference = if failure == :bad_reference, do: :invalid, else: make_ref()
      send(listener, {:bacnet_client, reference, notification(), {@destination, nil, nil}, client})

      case failure do
        :error ->
          assert_receive {:fault_call, ^client, {:reply, _, _, []}, from}
          GenServer.reply(from, {:error, :injected_send_failure})

        :dead_client ->
          assert_receive {:fault_call, ^client, {:reply, _, _, []}, _}
          stop_supervised!(COVFaultClient)

        :bad_reference ->
          :ok
      end

      assert_receive {:cov_listener_error, ^listener, %Error{code: :acknowledgment_failed}}, 100
      refute_receive {:cov_report, ^listener, _, _}, 10
      if Process.alive?(client), do: stop_supervised!(COVFaultClient)
    end
  end

  test "WBA-C05 WBA-S04 listener enforces internal queue and SDK overflow failures" do
    client = start_supervised!({COVFaultClient, self()})
    listener = ready_listener(client)
    send(listener, :unrelated)
    GenServer.cast(listener, :unrelated)
    assert Process.alive?(listener)
    send(listener, {:wotex_cov_error, :slow_consumer})
    assert_receive {:cov_listener_error, ^listener, %Error{code: :slow_consumer}}
    assert_receive {:fault_call, ^client, {:wotex_client, :unregister_cov}, _}

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    listener = ready_listener(client, owner)
    for _ <- 1..1000, do: send(owner, :queued)
    send(listener, {:bacnet_client, make_ref(), notification(), {@destination, nil, nil}, client})
    assert_receive {:fault_call, ^client, {:wotex_client, :unregister_cov}, _}
    assert {:messages, messages} = Process.info(owner, :messages)
    assert {:cov_listener_error, listener, Error.new(:slow_consumer)} in messages
    refute_receive {:fault_call, ^client, {:reply, _, _, _}, _}, 10
  end

  test "WBA-C01 WBA-C08 malformed optional callback results never masquerade as unsupported" do
    for mode <- [:malformed_handle, :malformed_success, :exception] do
      {:ok, session} = BACnet.connect(client: Wotex.BACnet.Test.COVPort, mode: mode)
      assert {:error, %Error{} = error} = BACnet.subscribe(session, @request)
      expected = if mode == :exception, do: :transport_exception, else: :invalid_transport_return
      assert error.code == expected
      refute inspect(error) =~ "private-credential-canary"

      assert {:error, %Error{code: :invalid_transport_return}} =
               BACnet.unsubscribe(session, handle())

      BACnet.disconnect(session)
    end
  end

  defp ready_listener(client, owner \\ self()) do
    listener = listener(client, 1000, owner)
    assert_receive {:fault_call, ^client, {:wotex_client, :register_cov, _, @destination, _}, from}
    GenServer.reply(from, {:ok, 7})

    if owner == self() do
      assert_receive {:cov_listener, ^listener, 7}
    else
      assert :sys.get_state(listener).pending == nil
    end

    listener
  end

  defp notification do
    {:ok, tags} =
      Tags.decode(
        <<9, 7, 0x1C, 8::10, 123::22, 0x2C, 1::10, 0::22, 0x39, 2, 0x4E, 9, 85, 0x2E, 0x44,
          1.5::float-32, 0x2F, 0x4F>>
      )

    {:ok, apdu} = Elixir.BACnet.Protocol.APDU.decode(<<2, 0x65, 44, 1>>)
    %{apdu | parameters: tags}
  end

  defp listener(client, timeout, owner \\ self()) do
    {:ok, request} = COVRequest.new(@request, self())

    {:ok, listener} =
      COVListener.start_link(%{
        client: client,
        owner: owner,
        request: request,
        destination: @destination,
        deadline: now() + timeout
      })

    listener
  end

  defp handle,
    do: %Subscription{
      pid: self(),
      reference: make_ref(),
      generation: make_ref(),
      session_generation: make_ref()
    }

  defp now, do: System.monotonic_time(:millisecond)
end
