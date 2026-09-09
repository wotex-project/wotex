defmodule Wotex.BACnet.StackCOVTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Stack.Client
  alias Wotex.BACnet.{BACstack, CharacterString, COVRequest, IPv4, StackClient}
  @moduletag :capture_log
  @destination {{127, 0, 0, 1}, 55_826}
  @corpus Jason.decode!(File.read!(Path.expand("../../fixtures/cov_transport_v1.json", __DIR__)))
  @receipts Enum.find(@corpus["cases"], &(&1["id"] == "WBA-CT01"))
  @assemblies Enum.find(@corpus["cases"], &(&1["id"] == "WBA-CT02"))
  @capacity Enum.find(@corpus["cases"], &(&1["id"] == "WBA-CT03"))
  @request %{
    type: :cov,
    object_type: @receipts["request"]["object_type"],
    instance: @receipts["request"]["instance"],
    device_instance: @receipts["request"]["device_instance"]
  }

  setup do
    {:ok, peer} = :gen_udp.open(55_826, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, handle} = IPv4.connect(local_ip: :none, local_port: 55_827, destination: @destination)
    {:ok, request} = COVRequest.new(@request, self())

    on_exit(fn ->
      IPv4.disconnect(handle)
      :gen_udp.close(peer)
    end)

    %{peer: peer, handle: handle, client: handle.stack.client, request: request}
  end

  test "WBA-S03 WBA-S04 wrapper selection validates the live local boundary before I/O", c do
    assert :ok = StackClient.verify(c.client, 100)

    assert {:ok, borrowed} =
             BACstack.connect(
               stack_client: c.client,
               stack_client_kind: :wotex,
               destination: @destination
             )

    assert borrowed.stack_client_kind == :wotex
    assert :ok = BACstack.disconnect(borrowed)
    assert Process.alive?(c.client)

    for kind <- [:other, nil, "wotex"] do
      assert {:error, %{code: :invalid_options}} =
               BACstack.connect(
                 stack_client: c.client,
                 stack_client_kind: kind,
                 destination: @destination
               )
    end

    # An actual raw SDK client deliberately has no wrapper handshake callback.
    sdk = :sys.get_state(c.client).sdk

    {:ok, raw} =
      Client.start_link(
        transport: {sdk.transport_mod, sdk.transport_pid},
        segmentator: sdk.segmentator,
        segments_store: sdk.segments_store
      )

    on_exit(fn -> if Process.alive?(raw), do: GenServer.stop(raw) end)
    before = :sys.get_state(raw)

    assert {:error, %{code: :unsupported_stack_client}} =
             BACstack.connect(
               stack_client: raw,
               stack_client_kind: :wotex,
               destination: @destination
             )

    assert :sys.get_state(raw) == before
    assert {:ok, borrowed} = BACstack.connect(stack_client: raw, destination: @destination)
    assert borrowed.stack_client_kind == :bacstack
    assert :ok = BACstack.disconnect(borrowed)
    assert Process.alive?(raw)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
    assert {:error, _} = StackClient.verify(self(), 1)

    wrong =
      spawn(fn ->
        receive do
          {:"$gen_call", from, _} -> GenServer.reply(from, :unsupported)
        end
      end)

    assert {:error, %{code: :unsupported_stack_client}} = StackClient.verify(wrong, 100)
  end

  test "WBA-S03 failed owned wrapper admission releases its already-acquired stack", c do
    group = :sys.get_state(c.handle.owner)

    assert {:error, %{code: :unsupported_stack_client}} =
             BACstack.connect_owned(
               [stack_client: self(), destination: @destination],
               c.handle.owner
             )

    for key <- [:client, :segmentator, :segments_store, :transport],
        do: refute(Process.alive?(Map.fetch!(group, key)))

    refute Process.alive?(c.handle.owner)
    assert {:ok, port} = :gen_udp.open(55_827, [:binary, active: false])
    :gen_udp.close(port)
  end

  test "WBA-S04 WBA-V06 WBA-V07 every confirmed receipt retains its reply reference", c do
    assert {:ok, id} = register(c.client, c.request)
    bytes = notification(id, @receipts["notification"]["invoke_id"], <<0x73, 255, 0, 255>>)
    send_apdu(c.peer, bytes)
    send_apdu(c.peer, bytes)

    assert_receive {:bacnet_client, first, %APDU.ConfirmedServiceRequest{} = apdu,
                    {@destination, _, _}, client},
                   1000

    assert client == c.client
    assert_receive {:bacnet_client, second, ^apdu, {@destination, _, _}, ^client}, 1000
    assert first != second

    assert map_size(:sys.get_state(client).cov.replies) ==
             @receipts["expected"]["reply_contexts_before_ack"]

    assert {:ok, report} = Wotex.BACnet.COV.notification(apdu)

    assert [%{value: %Encoding{value: %CharacterString{character_set: 255, bytes: <<0, 255>>}}}] =
             report.values

    wrong = %APDU.SimpleACK{invoke_id: 8, service: :confirmed_cov_notification}
    assert {:error, %{code: :invalid_cov_acknowledgment}} = Client.reply(client, first, wrong)
    ack = %{wrong | invoke_id: 7}
    foreign = Task.async(fn -> Client.reply(client, first, ack) end)
    assert {:error, %{code: :invalid_cov_acknowledgment}} = Task.await(foreign)

    assert {:error, %{code: :invalid_cov_acknowledgment}} =
             Client.reply(client, first, ack, foo: true)

    assert {:error, %{code: :invalid_cov_acknowledgment}} =
             GenServer.call(client, {:reply, first, %{}, []})

    for ref <- [first, second] do
      assert :ok = Client.reply(client, ref, ack)
      assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 0, 0x20, 7, 1>>}} = :gen_udp.recv(c.peer, 0, 1000)
    end

    assert :sys.get_state(client).cov.replies == %{}
    assert :sys.get_state(client).sdk.app_reply_mapping == %{}
    assert :sys.get_state(client).sdk.app_reply_timers == %{}
    assert {:error, :app_timeout} = Client.reply(client, first, ack)
    assert :ok = GenServer.call(client, {:wotex_client, :unregister_cov})
    assert :sys.get_state(client).cov.filters == %{}
  end

  test "WBA-S04 WBA-V06 unrelated identity and malformed notifications allocate nothing", c do
    {:ok, id} = register(c.client, c.request)

    for bytes <- [
          notification(id + 1, 1),
          notification(id, 1, <<0>>, 124),
          notification(id, 1, <<0x72, 0, 255>>),
          notification(id, 1) <> <<0>>,
          <<16, 2, 0>>,
          <<0, 0, 1, 1, 0>>
        ] do
      send_apdu(c.peer, bytes)
    end

    Process.sleep(20)
    refute_receive {:bacnet_client, _, _, _, _}, 20
    assert :sys.get_state(c.client).cov.replies == %{}
    assert :sys.get_state(c.client).cov.assemblies == %{}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
    assert {:error, %{code: :invalid_subscription}} = register(c.client, c.request)

    assert {:error, %{code: :invalid_subscription}} =
             register(c.client, %{c.request | device_instance: nil})
  end

  test "WBA-S02 WBA-S04 WBA-N02 request and response segmentation cannot share an assembly", c do
    {:ok, identifier} = register(c.client, c.request)

    read =
      Task.async(fn ->
        IPv4.request(
          c.handle,
          %{type: :read_property, object_type: 1, instance: 0, property: 85},
          1000
        )
      end)

    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, id, 12, _::binary>>}} =
             :gen_udp.recv(c.peer, 0, 1000)

    response = <<0x0C, 1::10, 0::22, 0x19, 85, 0x3E, 0x21, 42, 0x3F>>
    <<response_first::binary-size(5), response_last::binary>> = response
    <<_::binary-size(4), payload::binary>> = notification(identifier, id)
    <<cov_first::binary-size(6), cov_last::binary>> = payload
    send_apdu(c.peer, <<0x3C, id, 0, 2, 12, response_first::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    send_apdu(c.peer, <<0x0C, 0x65, id, 0, 2, 1, cov_first::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    sdk = :sys.get_state(c.client).sdk

    assert map_size(:sys.get_state(sdk.segments_store).sequences) ==
             @assemblies["expected"]["simultaneous_assemblies"]

    send_apdu(c.peer, <<0x38, id, 1, 2, 12, response_last::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    send_apdu(c.peer, <<0x08, 0x65, id, 1, 2, 1, cov_last::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    assert {:ok, %Encoding{type: :unsigned_integer, value: 42}} = Task.await(read)
    assert_receive {:bacnet_client, ref, %APDU.ConfirmedServiceRequest{invoke_id: ^id}, _, _}, 1000

    assert :ok =
             Client.reply(c.client, ref, %APDU.SimpleACK{
               invoke_id: id,
               service: :confirmed_cov_notification
             })

    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    assert :sys.get_state(c.client).cov.assemblies == %{}
    assert :sys.get_state(sdk.segments_store).sequences == %{}
  end

  test "WBA-S03 WBA-S04 caller death cancels pending SDK state without closing borrowed stack", c do
    {:ok, apdu} = Wotex.BACnet.COV.request(c.request, 1)
    worker = spawn(fn -> Client.send(c.client, @destination, apdu) end)

    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, first_id, 5, _::binary>>}} =
             :gen_udp.recv(c.peer, 0, 1000)

    Process.exit(worker, :kill)
    wait_empty(c.client, 100)
    assert Process.alive?(c.client)
    assert :sys.get_state(c.client).sdk.apdu_timers == %{}
    assert :sys.get_state(c.client).calls == %{}
    assert Map.has_key?(:sys.get_state(c.client).invoke_ids.retired, first_id)
    next = Task.async(fn -> Client.send(c.client, @destination, apdu) end)

    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, second_id, 5, _::binary>>}} =
             :gen_udp.recv(c.peer, 0, 1000)

    assert first_id != second_id
    send_apdu(c.peer, <<0x20, first_id, 5>>)
    assert Task.yield(next, 10) == nil
    send_apdu(c.peer, <<0x20, second_id, 5>>)
    assert {:ok, %APDU.SimpleACK{invoke_id: ^second_id}} = Task.await(next)
  end

  test "WBA-S03 WBA-S04 WBA-V09 listener capacity, owner death and identity reuse remain bounded",
       c do
    parent = self()

    owners =
      for _ <- 1..@capacity["live_listeners"] do
        spawn(fn ->
          send(parent, {:registered, self(), register(c.client, c.request)})

          receive do
            :stop -> :ok
          end
        end)
      end

    on_exit(fn -> Enum.each(owners, &Process.exit(&1, :kill)) end)

    ids =
      for _ <- 1..@capacity["live_listeners"] do
        assert_receive {:registered, _, {:ok, id}}, 1000
        id
      end

    assert Enum.sort(ids) == Enum.to_list(1..64)
    assert {:error, %{code: :busy}} = register(c.client, c.request)
    assert map_size(:sys.get_state(c.client).cov.filters) == 64
    first = hd(owners)
    Process.exit(first, :kill)
    wait_until(fn -> not Map.has_key?(:sys.get_state(c.client).cov.filters, first) end)
    assert {:ok, new_id} = register(c.client, c.request)
    assert new_id == @capacity["expected"]["identifier_after_release"]
    send(c.client, {:DOWN, make_ref(), :process, self(), :forged})
    assert Map.has_key?(:sys.get_state(c.client).cov.filters, self())
    assert :ok = GenServer.call(c.client, {:wotex_client, :unregister_cov})
    assert :ok = GenServer.call(c.client, {:wotex_client, :unregister_cov})
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S04 WBA-V07 unconfirmed equal reports are fresh and reply contexts expire", c do
    request = %{c.request | confirmed: false}
    {:ok, id} = register(c.client, request)
    <<_::32, payload::binary>> = notification(id, 1)
    for _ <- 1..2, do: send_apdu(c.peer, <<16, 2, payload::binary>>)

    for _ <- 1..2 do
      assert_receive {:bacnet_client, _, %APDU.UnconfirmedServiceRequest{}, _, _}, 1000
    end

    assert :sys.get_state(c.client).cov.replies == %{}
    assert :ok = GenServer.call(c.client, {:wotex_client, :unregister_cov})
    {:ok, id} = register(c.client, c.request)
    send_apdu(c.peer, notification(id, 2))
    assert_receive {:bacnet_client, ref, _, _, _}, 1000
    send_apdu(c.peer, <<0x0C, 0x65, 3, 0, 2, 1, 0x09>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    Process.sleep(1050)
    state = :sys.get_state(c.client)
    assert state.cov.replies == %{}
    assert state.cov.assemblies == %{}
    assert :sys.get_state(state.sdk.segments_store).sequences == %{}

    assert {:error, :app_timeout} =
             Client.reply(c.client, ref, %APDU.SimpleACK{
               invoke_id: 2,
               service: :confirmed_cov_notification
             })

    # Already-fired expirations are idempotent and cannot resurrect context.
    send(c.client, {:wotex_cov_expire, :reply, ref})
    send(c.client, {:wotex_cov_expire, :assembly, {@destination, 3}})
    assert :sys.get_state(c.client).cov.replies == %{}
  end

  test "WBA-S04 WBA-V09 slow native listener is removed before unbounded allocation", c do
    {:ok, request} = COVRequest.new(Map.put(@request, :max_queue_length, 1), self())
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:registered, self(), register(c.client, request)})

        receive do
          :release -> :ok
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:registered, ^owner, {:ok, id}}
    send(owner, :busy)
    send_apdu(c.peer, notification(id, 4))
    wait_until(fn -> not Map.has_key?(:sys.get_state(c.client).cov.filters, owner) end)
    assert :sys.get_state(c.client).cov.replies == %{}
    {:messages, messages} = Process.info(owner, :messages)
    assert messages == [:busy, {:wotex_cov_error, :slow_consumer}]
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S02 WBA-S04 segmented COV rejects changed headers and unwinds all listener resources",
       c do
    {:ok, id} = register(c.client, c.request)
    <<_::32, payload::binary>> = notification(id, 1)
    <<first::binary-size(5), last::binary>> = payload
    send_apdu(c.peer, <<0x0C, 0x65, 1, 0, 2, 1, first::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    send_apdu(c.peer, <<0x08, 0x64, 1, 1, 2, 1, last::binary>>)
    wait_until(fn -> :sys.get_state(c.client).cov.assemblies == %{} end)
    refute_receive {:bacnet_client, _, _, _, _}, 10
    send_apdu(c.peer, notification(id, 2))
    assert_receive {:bacnet_client, _, _, _, _}, 1000
    send_apdu(c.peer, <<0x0C, 0x65, 3, 0, 2, 1, first::binary>>)
    assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
    assert :ok = GenServer.call(c.client, {:wotex_client, :unregister_cov})
    state = :sys.get_state(c.client)
    assert state.cov.filters == %{} and state.cov.replies == %{} and state.cov.assemblies == %{}
    assert :sys.get_state(state.sdk.segments_store).sequences == %{}
  end

  test "WBA-S02 WBA-S03 WBA-V05 pending capacity and retired-ID exhaustion fail before I/O", c do
    {:ok, apdu} = Wotex.BACnet.COV.request(c.request, 1)
    workers = for _ <- 1..64, do: spawn(fn -> Client.send(c.client, @destination, apdu) end)
    on_exit(fn -> Enum.each(workers, &Process.exit(&1, :kill)) end)
    for _ <- 1..64, do: assert({:ok, _} = :gen_udp.recv(c.peer, 0, 1000))
    assert map_size(:sys.get_state(c.client).sdk.apdu_timers) == 64
    assert {:error, %{code: :busy}} = Client.send(c.client, @destination, apdu)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    Enum.each(workers, &Process.exit(&1, :kill))
    wait_until(fn -> :sys.get_state(c.client).sdk.apdu_timers == %{} end)

    for _ <- 1..192 do
      worker = spawn(fn -> Client.send(c.client, @destination, apdu) end)
      assert {:ok, _} = :gen_udp.recv(c.peer, 0, 1000)
      Process.exit(worker, :kill)
      wait_until(fn -> :sys.get_state(c.client).sdk.apdu_timers == %{} end)
    end

    assert map_size(:sys.get_state(c.client).invoke_ids.retired) == 256
    assert :sys.get_state(c.client).calls == %{}
    assert {:error, %{code: :busy}} = Client.send(c.client, @destination, apdu)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    # Forged/stale SDK timer keys cannot allocate a retirement entry.
    send(c.client, {:apdu_timer, {@destination, nil, 999}})
    GenServer.cast(c.client, :unrelated)
    assert map_size(:sys.get_state(c.client).invoke_ids.retired) == 256
  end

  defp wait_until(fun, attempts \\ 100)
  defp wait_until(fun, 0), do: assert(fun.())

  defp wait_until(fun, attempts) do
    if not fun.() do
      Process.sleep(2)
      wait_until(fun, attempts - 1)
    end
  end

  defp register(client, request),
    do: GenServer.call(client, {:wotex_client, :register_cov, request, @destination})

  defp notification(identifier, invoke, value \\ <<0x21, 42>>, device \\ 123) do
    process = :binary.encode_unsigned(identifier)

    <<2, 0x65, invoke, 1, 0::4, 1::1, byte_size(process)::3, process::binary, 0x1C, 8::10,
      device::22, 0x2C, 1::10, 0::22, 0x39, 60, 0x4E, 0x09, 85, 0x2E, value::binary, 0x2F, 0x4F>>
  end

  defp send_apdu(peer, apdu),
    do:
      :gen_udp.send(
        peer,
        {127, 0, 0, 1},
        55_827,
        <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 4, apdu::binary>>
      )

  defp wait_empty(client, remaining) when remaining > 0 do
    if Process.alive?(client) and :sys.get_state(client).sdk.apdu_timers != %{} do
      Process.sleep(1)
      wait_empty(client, remaining - 1)
    end
  end
end
