defmodule Wotex.Matter.SubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Address, Error, Native, Subscription}

  @path %{fabric_id: 1, node_id: 3, endpoint: 1, cluster: 0x0201, member: 0}
  @event_path %{fabric_id: 1, node_id: 3, endpoint: 2, cluster: 0x0039, member: 3}
  @sensor_path %{fabric_id: 1, node_id: 3, endpoint: 4, cluster: 0x0402, member: 0}

  test "native Runtime credit waits for exact consumption tokens and advances only the contiguous prefix" do
    audit = temporary_path("acknowledged-reports")
    executable = native_fixture(audit, "reports")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    request = %{
      kind: :attribute,
      paths: [@path],
      min_interval_s: 1,
      max_interval_s: 60,
      queue_limit: 64,
      resubscribe: false
    }

    assert {:ok, subscription} =
             Native.subscribe_acknowledged(session.handle, request, self(), 3_000)

    assert_receive {:wotex_matter, _, %Native.Delivery{sequence: 1} = first}, 1_000
    assert_receive {:wotex_matter, _, %Native.Delivery{sequence: 2} = second}, 1_000
    refute inspect(first) =~ inspect(first.token)
    assert :sys.get_state(session.handle.pid).report_ledger.acknowledged_sequence == 0
    refute Enum.any?(audit_frames(audit), &(&1["event"] == "report_ack"))

    acknowledge = fn delivery, token ->
      send(
        delivery.connection,
        {:native_report_consumed, delivery.generation, delivery.reference, delivery.sequence, token}
      )
    end

    acknowledge.(first, make_ref())
    acknowledge.(%{first | reference: make_ref()}, first.token)
    acknowledge.(%{first | generation: "wrong-generation"}, first.token)
    acknowledge.(second, second.token)
    acknowledge.(second, second.token)
    state = :sys.get_state(session.handle.pid)
    assert state.report_ledger.acknowledged_sequence == 0
    assert state.report_ledger.pending[2].consumed
    refute state.report_ledger.pending[1].consumed
    acknowledge.(first, first.token)
    assert eventually(fn -> Enum.any?(audit_frames(audit), &(&1["event"] == "report_ack")) end)
    [ack] = Enum.filter(audit_frames(audit), &(&1["event"] == "report_ack"))
    assert ack["report_sequence"] == 2

    assert ack["acknowledged_bytes"] ==
             state.report_ledger.pending[1].bytes + state.report_ledger.pending[2].bytes

    assert :sys.get_state(session.handle.pid).report_ledger.pending == %{}
    assert :ok = Matter.unsubscribe(session, subscription)
    acknowledge.(first, first.token)
    assert :ok = Matter.disconnect(session)
    assert Enum.count(audit_frames(audit), &(&1["event"] == "report_ack")) == 1
  end

  test "the actual Runtime relay retains native credit until its owner decodes the bound frame" do
    audit = temporary_path("runtime-acknowledged-reports")
    executable = native_fixture(audit, "reports")
    assert {:ok, address} = Address.new(@path)
    config = [client: Native] ++ native_options(executable)

    assert {:ok, relay} =
             Wotex.Matter.RuntimeRelay.start(
               self(),
               "native-credit",
               :observeproperty,
               :attribute,
               address,
               config,
               [max_queue_length: 64],
               3_000
             )

    state = :sys.get_state(relay.pid)
    connection = state.session.handle.pid

    try do
      assert_receive {:wotex_transport_frame, first}, 1_000
      assert_receive {:wotex_transport_frame, second}, 1_000
      :sys.suspend(relay.pid)
      assert :sys.get_state(connection).report_ledger.acknowledged_sequence == 0
      refute Enum.any?(audit_frames(audit), &(&1["event"] == "report_ack"))
      :sys.resume(relay.pid)

      assert {:ok, %{value: 2150}, _} =
               Wotex.Matter.RuntimeRelay.decode(
                 second,
                 "native-credit",
                 :observeproperty,
                 :attribute,
                 address
               )

      assert eventually(fn -> :sys.get_state(connection).report_ledger.pending[2].consumed end)
      assert :sys.get_state(connection).report_ledger.acknowledged_sequence == 0

      assert :ignore =
               Wotex.Matter.RuntimeRelay.decode(
                 second,
                 "native-credit",
                 :observeproperty,
                 :attribute,
                 address
               )

      assert {:ok, %{value: 2150}, _} =
               Wotex.Matter.RuntimeRelay.decode(
                 first,
                 "native-credit",
                 :observeproperty,
                 :attribute,
                 address
               )

      assert eventually(fn -> :sys.get_state(connection).report_ledger.pending == %{} end)

      assert eventually(fn ->
               Enum.count(audit_frames(audit), &(&1["event"] == "report_ack")) == 1
             end)
    after
      if Process.alive?(relay.pid), do: :sys.resume(relay.pid)
      assert :ok = Wotex.Matter.RuntimeRelay.close(relay)
    end
  end

  test "retirement releases validated reports that the Runtime owner has not consumed" do
    audit = temporary_path("retired-acknowledged-reports")

    assert {:ok, session} =
             Matter.connect([client: Native] ++ native_options(native_fixture(audit, "reports")))

    request = %{
      kind: :attribute,
      paths: [@path],
      min_interval_s: 1,
      max_interval_s: 60,
      queue_limit: 64,
      resubscribe: false
    }

    assert {:ok, subscription} =
             Native.subscribe_acknowledged(session.handle, request, self(), 3_000)

    assert_receive {:wotex_matter, _, %Native.Delivery{sequence: 1}}, 1_000
    assert_receive {:wotex_matter, _, %Native.Delivery{sequence: 2}}, 1_000
    assert :sys.get_state(session.handle.pid).report_ledger.acknowledged_sequence == 0
    assert :ok = Matter.unsubscribe(session, subscription)
    state = :sys.get_state(session.handle.pid)
    assert state.report_ledger.pending == %{}
    assert state.report_ledger.acknowledged_sequence == 2
    assert :ok = Matter.disconnect(session)
    [ack] = Enum.filter(audit_frames(audit), &(&1["event"] == "report_ack"))
    assert ack["report_sequence"] == 2
  end

  test "WMA-B03 Runtime closes once when its native connection is killed" do
    audit = temporary_path("runtime-connection-death")
    assert {:ok, address} = Address.new(@path)
    config = [client: Native] ++ native_options(native_fixture(audit, "reports"))

    assert {:ok, relay} =
             Wotex.Matter.RuntimeRelay.start(
               self(),
               "connection-death",
               :observeproperty,
               :attribute,
               address,
               config,
               [max_queue_length: 64],
               3_000
             )

    state = :sys.get_state(relay.pid)
    connection = state.session.handle.pid
    port = :sys.get_state(connection).port
    monitor = Process.monitor(relay.pid)

    try do
      assert_receive {:wotex_transport_frame, frame}, 1_000
      Process.exit(connection, :kill)
      assert_receive {:wotex_transport, {:error, %Error{code: :transport_closed}}}, 1_000
      assert_receive {:wotex_transport_status, :session_lost}, 1_000
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert Port.info(port) == nil

      assert :ignore =
               Wotex.Matter.RuntimeRelay.decode(
                 frame,
                 "connection-death",
                 :observeproperty,
                 :attribute,
                 address
               )

      refute_receive {:wotex_transport, {:error, _}}, 20
      refute_receive {:wotex_transport_status, _}, 20
    after
      Wotex.Matter.RuntimeRelay.close(relay)
    end
  end

  test "a native producer exceeding unconsumed frame credit terminates once" do
    audit = temporary_path("unconsumed-overflow")

    assert {:ok, session} =
             Matter.connect(
               [client: Native] ++ native_options(native_fixture(audit, "credit_overflow"))
             )

    monitor = Process.monitor(session.handle.pid)

    request = %{
      kind: :attribute,
      paths: [@path],
      min_interval_s: 1,
      max_interval_s: 60,
      queue_limit: 1000,
      resubscribe: false
    }

    assert {:ok, subscription} =
             Native.subscribe_acknowledged(session.handle, request, self(), 3_000)

    reference = subscription.reference
    assert_receive {:wotex_matter, ^reference, {:error, %Error{code: :invalid_frame}}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    deliveries = drain([])

    assert Enum.count(deliveries, &match?({:wotex_matter, ^reference, %Native.Delivery{}}, &1)) ==
             64

    refute Enum.any?(deliveries, &match?({:wotex_matter, ^reference, {:error, _}}, &1))
    assert :ok = Matter.disconnect(session)
  end

  test "WMA-F08 distinct equal reports retain identity and cancellation is idempotent" do
    handler = {__MODULE__, make_ref()}
    test_pid = self()

    for event <- [:open, :deliver, :close] do
      :ok =
        :telemetry.attach(
          {handler, event},
          [:wotex, :matter, :subscription, event],
          fn name, measurements, metadata, _ ->
            send(test_pid, {:subscription_telemetry, name, measurements, metadata})
          end,
          nil
        )
    end

    on_exit(fn ->
      for event <- [:open, :deliver, :close], do: :telemetry.detach({handler, event})
    end)

    audit = temporary_path("reports")
    executable = native_fixture(audit, "reports")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, %Subscription{} = subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: [@path],
               min_interval_s: 1,
               max_interval_s: 60,
               max_queue_length: 64,
               resubscribe: false
             })

    refute inspect(subscription) =~ inspect(subscription.reference)
    refute inspect(subscription) =~ inspect(subscription.pid)

    assert_receive {:wotex_matter, reference,
                    {:ok, %{tag: :anonymous, type: :i16, value: 2150}, first}},
                   1_000

    assert_receive {:wotex_matter, ^reference,
                    {:ok, %{tag: :anonymous, type: :i16, value: 2150}, second}},
                   1_000

    assert reference == subscription.reference
    assert %Address{} = first.path
    assert first.data_version == 7
    assert second.data_version == 8
    assert first.report_id == 1
    assert second.report_id == 2
    assert first.min_interval_s == 2
    assert first.max_interval_s == 45

    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.unsubscribe(session, subscription)
    refute_receive {:wotex_matter, ^reference, _}, 50
    assert :ok = Matter.disconnect(session)

    assert_receive {:subscription_telemetry, [:wotex, :matter, :subscription, :open], %{count: 1},
                    %{kind: :attribute, result: :ok}}

    assert_receive {:subscription_telemetry, [:wotex, :matter, :subscription, :deliver],
                    %{count: 1}, %{kind: :attribute, result: :ok}}

    assert_receive {:subscription_telemetry, [:wotex, :matter, :subscription, :deliver],
                    %{count: 1}, %{kind: :attribute, result: :ok}}

    assert_receive {:subscription_telemetry, [:wotex, :matter, :subscription, :close], %{count: 1},
                    %{kind: :attribute, result: :cancelled}}

    frames = audit_frames(audit)
    assert Enum.count(frames, &(&1["event"] == "report_ack")) == 2
    assert Enum.count(frames, &(&1["operation"] == "unsubscribe")) == 1
  end

  test "WMA-V09 receiver death cancels the native stream" do
    audit = temporary_path("death")
    executable = native_fixture(audit, "quiet")
    receiver = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, subscription} =
             Matter.subscribe(session, %{kind: :attribute, paths: [@path], receiver: receiver})

    Process.exit(receiver, :kill)

    assert eventually(fn ->
             audit_frames(audit)
             |> Enum.any?(&(&1["operation"] == "unsubscribe"))
           end)

    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.disconnect(session)
  end

  test "WMA-V07 event identity and explicit null survive native delivery" do
    event_audit = temporary_path("event")
    event_executable = native_fixture(event_audit, "event")

    assert {:ok, event_session} =
             Matter.connect([client: Native] ++ native_options(event_executable))

    assert {:ok, event_subscription} =
             Matter.subscribe(event_session, %{kind: :event, paths: [@event_path]})

    assert_receive {:wotex_matter, event_reference,
                    {:ok,
                     %{
                       tag: :anonymous,
                       type: :structure,
                       value: [%{tag: {:context, 0}, type: :boolean, value: false}]
                     }, event_metadata}},
                   1_000

    assert event_reference == event_subscription.reference
    assert event_metadata.kind == :event
    assert event_metadata.path.cluster == 0x0039
    assert event_metadata.event_number == 0xFFFFFFFFFFFFFFFF
    assert event_metadata.priority == 2
    assert event_metadata.timestamp == %{kind: :epoch, value: 17}
    assert :ok = Matter.unsubscribe(event_session, event_subscription)
    assert :ok = Matter.disconnect(event_session)

    null_audit = temporary_path("null")
    null_executable = native_fixture(null_audit, "null")
    assert {:ok, null_session} = Matter.connect([client: Native] ++ native_options(null_executable))

    assert {:ok, null_subscription} =
             Matter.subscribe(null_session, %{kind: :attribute, paths: [@sensor_path]})

    assert_receive {:wotex_matter, null_reference,
                    {:ok, %{tag: :anonymous, type: :null, value: nil}, null_metadata}},
                   1_000

    assert null_reference == null_subscription.reference
    assert null_metadata.data_version == nil
    assert null_metadata.initial
    assert :ok = Matter.unsubscribe(null_session, null_subscription)
    assert :ok = Matter.disconnect(null_session)
  end

  test "WMA-V09 receiver queue overflow is terminal and cleans up" do
    audit = temporary_path("overflow")
    executable = native_fixture(audit, "reports")
    parent = self()

    receiver =
      spawn(fn ->
        receive do
          :release ->
            messages = drain([])
            send(parent, {:receiver_messages, messages})
        end
      end)

    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    assert {:ok, subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: [@path],
               receiver: receiver,
               max_queue_length: 1
             })

    assert eventually(fn ->
             audit_frames(audit)
             |> Enum.any?(&(&1["operation"] == "unsubscribe"))
           end)

    send(receiver, :release)
    assert_receive {:receiver_messages, messages}, 1_000

    assert Enum.any?(messages, fn
             {:wotex_matter, reference, {:error, %Error{code: :receiver_overflow}}} ->
               reference == subscription.reference

             _ ->
               false
           end)

    assert Enum.count(messages, &match?({:wotex_matter, _, {:ok, _, _}}, &1)) == 1
    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.disconnect(session)
  end

  test "native terminal failure is delivered once and the retirement barrier closes the handle" do
    audit = temporary_path("terminal")
    executable = native_fixture(audit, "terminal")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))
    assert {:ok, subscription} = Matter.subscribe(session, %{kind: :attribute, paths: [@path]})

    assert_receive {:wotex_matter, reference, {:error, %Error{code: :subscription_failed}}},
                   1_000

    assert reference == subscription.reference
    refute_receive {:wotex_matter, ^reference, _}, 50
    assert eventually(fn -> Matter.unsubscribe(session, subscription) == :ok end)
    assert :ok = Matter.unsubscribe(session, subscription)
    assert :ok = Matter.disconnect(session)
  end

  test "closing a session with an active subscription emits one bounded close event" do
    handler = {__MODULE__, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :matter, :subscription, :close],
        fn name, measurements, metadata, _ ->
          send(test_pid, {:subscription_telemetry, name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    audit = temporary_path("session-close")
    executable = native_fixture(audit, "quiet")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))
    assert {:ok, _subscription} = Matter.subscribe(session, %{kind: :attribute, paths: [@path]})
    assert :ok = Matter.disconnect(session)

    assert_receive {:subscription_telemetry, [:wotex, :matter, :subscription, :close], %{count: 1},
                    %{kind: :attribute, result: :session_closed}}

    refute_receive {:subscription_telemetry, _, _, _}, 50
  end

  test "subscription request boundaries are accepted" do
    audit = temporary_path("boundaries")
    executable = native_fixture(audit, "quiet")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    paths = for endpoint <- 1..64, do: %{@path | endpoint: endpoint}

    assert {:ok, subscription} =
             Matter.subscribe(session, %{
               kind: :attribute,
               paths: paths,
               min_interval_s: 0,
               max_interval_s: 65_535,
               max_queue_length: 10_000,
               resubscribe: false,
               timeout: 60_000
             })

    assert :ok = Matter.unsubscribe(session, subscription)

    assert Enum.count(audit_frames(audit), &(&1["operation"] == "subscribe")) == 1
    assert :ok = Matter.disconnect(session)
  end

  test "invalid paths intervals receivers and foreign handles fail before native I/O" do
    audit = temporary_path("invalid")
    executable = native_fixture(audit, "quiet")
    assert {:ok, session} = Matter.connect([client: Native] ++ native_options(executable))

    invalid = [
      %{kind: :attribute, paths: []},
      %{kind: :attribute, paths: [@path], min_interval_s: 2, max_interval_s: 1},
      %{kind: :attribute, paths: [@path], max_queue_length: 0},
      %{kind: :attribute, paths: [@path, @path]},
      %{kind: :attribute, paths: for(endpoint <- 1..65, do: %{@path | endpoint: endpoint})},
      %{kind: :event, paths: [@path]},
      %{kind: :attribute, paths: [%{@path | fabric_id: 2}]},
      %{kind: :attribute, paths: [@path], receiver: :not_a_pid}
    ]

    for request <- invalid do
      assert {:error, %Error{}} = Matter.subscribe(session, request)
    end

    refute Enum.any?(audit_frames(audit), &(&1["operation"] == "subscribe"))

    foreign = %Subscription{pid: self(), reference: make_ref(), generation: 1}
    assert {:error, %Error{code: :invalid_handle}} = Matter.unsubscribe(session, foreign)
    assert :ok = Matter.disconnect(session)
  end

  defp drain(messages) do
    receive do
      message -> drain([message | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  defp eventually(function, attempts \\ 50)
  defp eventually(function, 0), do: function.()

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(10)
      eventually(function, attempts - 1)
    end
  end

  defp audit_frames(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, :enoent} ->
        []
    end
  end

  defp native_options(executable) do
    paa = temporary_path("paa")
    File.mkdir_p!(paa)
    on_exit(fn -> File.rm_rf(paa) end)

    [
      executable: executable,
      lifecycle: :persistent,
      storage_path: temporary_path("store"),
      storage_mode: :create_new,
      authority: :generate_root,
      vendor_id: 65_521,
      fabric_id: 1,
      controller_node_id: 2,
      paa_trust_store: paa,
      timeout: 3_000
    ]
  end

  defp native_fixture(audit, mode) do
    path = temporary_path("subscription-host")

    script = ~S'''
    #!/usr/bin/env elixir
    audit = System.fetch_env!("WOTEX_MATTER_TEST_AUDIT")
    mode = System.fetch_env!("WOTEX_MATTER_TEST_MODE")

    read = fn ->
      case IO.read(:stdio, :line) do
        :eof -> System.halt(0)
        {:error, _} -> System.halt(1)
        line -> File.write!(audit, line, [:append]); line
      end
    end

    IO.puts(~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"}))
    flow = read.()
    [_, session_generation] = Regex.run(~r/"session_generation":"([0-9a-f]{32})"/, flow)
    read.()
    IO.puts(~s({"version":1,"id":"1","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}}))

    attribute_report = fn subscription_id, sequence, report_id, version ->
      metadata = ~s({"path":{"fabric_id":1,"node_id":3,"endpoint":1,"cluster":513,"member":0},"data_version":#{version},"initial":#{report_id == 1},"report_id":#{report_id},"min_interval_s":2,"max_interval_s":45,"sdk_subscription_id":73})
      IO.puts(~s({"version":1,"event":"subscription_report","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":1,"report_sequence":#{sequence},"kind":"attribute","value":{"tag":"anonymous","type":"i16","value":2150},"metadata":#{metadata}}))
    end

    event_report = fn subscription_id ->
      metadata = ~s({"path":{"fabric_id":1,"node_id":3,"endpoint":2,"cluster":57,"member":3},"event_number":18446744073709551615,"priority":2,"timestamp":{"kind":"epoch","value":17},"initial":true,"report_id":1,"min_interval_s":2,"max_interval_s":45,"sdk_subscription_id":73})
      value = ~s({"tag":"anonymous","type":"structure","value":[{"tag":["context",0],"type":"boolean","value":false}]})
      IO.puts(~s({"version":1,"event":"subscription_report","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":1,"report_sequence":1,"kind":"event","value":#{value},"metadata":#{metadata}}))
    end

    null_report = fn subscription_id ->
      metadata = ~s({"path":{"fabric_id":1,"node_id":3,"endpoint":4,"cluster":1026,"member":0},"data_version":null,"initial":true,"report_id":1,"min_interval_s":2,"max_interval_s":45,"sdk_subscription_id":73})
      IO.puts(~s({"version":1,"event":"subscription_report","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":1,"report_sequence":1,"kind":"attribute","value":{"tag":"anonymous","type":"null","value":null},"metadata":#{metadata}}))
    end

    loop = fn loop, subscription_id ->
      line = read.()

      cond do
        String.contains?(line, ~s("event":"report_ack")) ->
          loop.(loop, subscription_id)

        String.contains?(line, ~s("operation":"subscribe")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          [_, current] = Regex.run(~r/"subscription_id":"([0-9a-f]{32})"/, line)
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":{"subscription_id":"#{current}","generation":1,"min_interval_s":2,"max_interval_s":45,"sdk_subscription_id":73}}))
          case mode do
            "reports" ->
              attribute_report.(current, 1, 1, 7)
              attribute_report.(current, 2, 2, 8)
            "credit_overflow" ->
              for sequence <- 1..65, do: attribute_report.(current, sequence, sequence, 7)
            "event" -> event_report.(current)
            "null" -> null_report.(current)
            "terminal" ->
              IO.puts(~s({"version":1,"event":"subscription_error","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":1,"error":{"code":"subscription_failed"}}))
              IO.puts(~s({"version":1,"event":"stream_retired","session_generation":"#{session_generation}","subscription_id":"#{current}","generation":1,"last_report_sequence":0}))
            _ -> :ok
          end
          loop.(loop, current)

        String.contains?(line, ~s("operation":"unsubscribe")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          last = if mode == "reports", do: 2, else: if(mode in ["event", "null"], do: 1, else: 0)
          IO.puts(~s({"version":1,"event":"stream_retired","session_generation":"#{session_generation}","subscription_id":"#{subscription_id}","generation":1,"last_report_sequence":#{last}}))
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":null}))
          loop.(loop, subscription_id)

        String.contains?(line, ~s("operation":"close")) ->
          [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)
          IO.puts(~s({"version":1,"id":"#{id}","ok":true,"result":null}))

        true ->
          System.halt(1)
      end
    end

    loop.(loop, nil)
    '''

    File.write!(path, script)
    File.chmod!(path, 0o700)

    wrapper = temporary_path("subscription-wrapper")

    File.write!(
      wrapper,
      "#!/bin/sh\nWOTEX_MATTER_TEST_AUDIT=#{audit} WOTEX_MATTER_TEST_MODE=#{mode} exec #{path}\n"
    )

    File.chmod!(wrapper, 0o700)

    on_exit(fn ->
      File.rm(path)
      File.rm(wrapper)
      File.rm(audit)
    end)

    wrapper
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p05-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
