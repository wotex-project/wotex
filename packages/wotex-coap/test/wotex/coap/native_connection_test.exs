defmodule Wotex.CoAP.NativeConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.{Error, Message, Security, Subscription}
  alias Wotex.CoAP.Native.{Admission, Connection}

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-native-connection-#{System.unique_integer([:positive])}"
      )

    store = Path.join(root, "context")
    executable = Path.join(root, "wotex-coap-oscore")
    manifest = Path.join(root, "native-manifest.json")
    File.mkdir_p!(store)
    File.write!(executable, helper_source())
    File.chmod!(executable, 0o700)
    File.write!(manifest, manifest(digest(executable)))

    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      store: store,
      executable: executable,
      manifest: manifest,
      options: options(executable, manifest, store)
    }
  end

  test "WCO-N02 launches the verified custody entry and completes exact ready/open/close",
       context do
    File.write!(Path.join(context.store, "mode"), "valid")

    assert {:ok, pid} = Connection.start(context.options)
    assert Process.alive?(pid)
    assert File.read!(Path.join(context.store, "arguments")) == "--custody\n#{context.store}"

    open =
      context.store
      |> Path.join("open.json")
      |> File.read!()
      |> Jason.decode!()

    assert open["version"] == 1
    assert open["id"] == "1"
    assert open["operation"] == "open"
    assert open["timeout_ms"] in 1..3_000
    assert open["parameters"]["host"] == "127.0.0.1"
    assert open["parameters"]["port"] == 5683
    assert open["parameters"]["generation"] in 1..0xFFFFFFFFFFFFFFFF
    assert open["parameters"]["security"]["mode"] == "oscore"
    assert open["parameters"]["security"]["master_secret"] == bytes(<<0::128>>)

    %{admission: admission, generation: generation} = :sys.get_state(pid)
    assert generation == open["parameters"]["generation"]
    assert :ets.info(admission, :owner) == pid

    assert {{:dictionary, :wotex_coap_owner}, {Connection, ^generation, ^admission}} =
             :erlang.process_info(pid, {:dictionary, :wotex_coap_owner})

    refute inspect(:sys.get_state(pid)) =~ Base.encode64(secret_canary())
    refute inspect(:sys.get_status(pid)) =~ Base.encode64(secret_canary())

    assert :ok = Connection.close(pid)
    refute Process.alive?(pid)
    assert :ets.info(admission) == :undefined
    assert :ok = Connection.close(pid)

    close =
      context.store
      |> Path.join("close.json")
      |> File.read!()
      |> Jason.decode!()

    assert close == %{
             "id" => "2",
             "operation" => "close",
             "parameters" => %{},
             "timeout_ms" => 350,
             "version" => 1
           }
  end

  test "WCO-N02 public connect and send dispatch an absent body through the native owner",
       context do
    File.write!(Path.join(context.store, "mode"), "request")

    assert {:ok, %{pid: pid, timeout: 3_000} = session} =
             Wotex.CoAP.connect([scheme: :coap] ++ context.options)

    assert map_size(session) == 2
    assert Process.alive?(pid)

    assert {:ok, %Message{code: 69, payload: "ok"}} =
             Wotex.CoAP.send(session, %{
               method: :get,
               path: "/sensors/room%201?unit=c",
               confirmable: false,
               accept: :json
             })

    assert %{
             "id" => "2",
             "operation" => "request",
             "parameters" => parameters,
             "timeout_ms" => timeout,
             "version" => 1
           } = read_json(context.store, "request-1.json")

    assert timeout in 1..3_000

    assert parameters == %{
             "method" => "GET",
             "path" => "/sensors/room%201?unit=c",
             "confirmable" => false,
             "accept" => 50
           }

    refute File.exists?(Path.join(context.store, "body-begin.json"))
    assert :ok = Wotex.CoAP.disconnect(session)
    assert :ok = Wotex.CoAP.disconnect(session)
  end

  test "WCO-D02 public native helpers preserve an explicit empty body and normalized formats",
       context do
    File.write!(Path.join(context.store, "mode"), "request_upload_empty")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)

    assert {:ok, %Message{code: 69, payload: "ok"}} =
             Wotex.CoAP.post(session, "/write", <<>>,
               confirmable: false,
               content_format: :json,
               accept: 0
             )

    assert %{
             "id" => "2",
             "operation" => "body_begin",
             "parameters" => %{
               "body_id" => "body-1",
               "length" => 0,
               "sha256" => hash
             }
           } = read_json(context.store, "body-begin.json")

    assert hash == Base.encode16(:crypto.hash(:sha256, <<>>), case: :lower)

    assert %{
             "id" => "3",
             "operation" => "body_end",
             "parameters" => %{"body_id" => "body-1"}
           } = read_json(context.store, "body-end.json")

    assert %{
             "id" => "4",
             "operation" => "request",
             "parameters" => %{
               "method" => "POST",
               "path" => "/write",
               "confirmable" => false,
               "content_format" => 50,
               "accept" => 0,
               "body_id" => "body-1"
             }
           } = read_json(context.store, "request-1.json")

    assert :ok = Wotex.CoAP.disconnect(session)
  end

  test "WCO-D03 public native discovery preserves the query and parses bounded links", context do
    File.write!(Path.join(context.store, "mode"), "request_discovery")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)

    assert {:ok, links} =
             Wotex.CoAP.discover(session, %{query: "rt=temperature%2Dc&empty="})

    assert length(links) == 64
    assert Enum.all?(links, &(&1.href == "/"))

    assert %{
             "id" => "2",
             "operation" => "request",
             "parameters" => %{
               "method" => "GET",
               "path" => "/.well-known/core?rt=temperature%2Dc&empty=",
               "confirmable" => true,
               "accept" => 40
             }
           } = read_json(context.store, "request-1.json")

    refute File.exists?(Path.join(context.store, "body-begin.json"))
    assert :ok = Wotex.CoAP.disconnect(session)
  end

  test "WCO-D03 native discovery refuses an oversized declared body before allocation", context do
    File.write!(Path.join(context.store, "mode"), "request_discovery_oversize")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    monitor = Process.monitor(session.pid)

    assert {:error, %Error{code: :body_limit, effect: :none}} =
             Wotex.CoAP.discover(session, %{})

    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
    assert :ok = Wotex.CoAP.disconnect(session)
  end

  test "WCO-D04 public native Observe opens credit, delivers reports and cancels exactly",
       context do
    File.write!(Path.join(context.store, "mode"), "observe")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)

    assert {:ok, handle} =
             Wotex.CoAP.subscribe(session, %{
               path: "/temperature",
               receiver: self(),
               renew: false,
               max_queue_length: 1000
             })

    reference = handle.reference

    assert_receive {:wotex_coap, ^reference,
                    {:ok, %Message{payload: "20"}, %{observe: 10, content_format: 0}}},
                   1_000

    assert_receive {:wotex_coap, ^reference,
                    {:ok, %Message{payload: "21"}, %{observe: 11, content_format: 0}}},
                   1_000

    assert %{
             "id" => "2",
             "operation" => "observe",
             "parameters" => %{
               "path" => "/temperature",
               "confirmable" => true,
               "observation_kind" => "property",
               "renew" => false
             }
           } = read_json(context.store, "observe.json")

    for {name, id, acknowledged} <- [
          {"credit-0.json", "3", 0},
          {"credit-1.json", "4", 1},
          {"credit-2.json", "5", 2}
        ] do
      assert %{
               "id" => ^id,
               "operation" => "credit",
               "parameters" => %{"ack_seq" => ^acknowledged, "generation" => generation}
             } = read_json(context.store, name)

      assert generation in 1..0xFFFFFFFFFFFFFFFF
    end

    assert {:error, %Error{code: :observation_active}} =
             Wotex.CoAP.get(session, "/other")

    assert {:error, %Error{code: :observation_active}} =
             Wotex.CoAP.subscribe(session, "/other")

    {:ok, foreign} = Subscription.new(session.pid, make_ref(), handle.generation)

    assert {:error, %Error{code: :invalid_subscription}} =
             Wotex.CoAP.unsubscribe(session, foreign)

    assert eventually(fn ->
             match?(%{operation: :credit, ack_seq: 2}, :sys.get_state(session.pid).active)
           end)

    first_cancel = Task.async(fn -> Wotex.CoAP.unsubscribe(session, handle) end)
    second_cancel = Task.async(fn -> Wotex.CoAP.unsubscribe(session, handle) end)
    assert :ok = Task.await(first_cancel, 1_000)
    assert :ok = Task.await(second_cancel, 1_000)
    refute Process.alive?(session.pid)

    assert %{
             "id" => "6",
             "operation" => "cancel",
             "parameters" => %{"subscription_id" => "2", "generation" => generation}
           } = read_json(context.store, "cancel.json")

    assert generation in 1..0xFFFFFFFFFFFFFFFF
    assert :ok = Wotex.CoAP.unsubscribe(session, handle)
    assert :ok = Wotex.CoAP.disconnect(session)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-D04 native Observe rejects invalid admission before Port traffic", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    receiver = spawn(fn -> :ok end)
    monitor = Process.monitor(receiver)
    assert_receive {:DOWN, ^monitor, :process, ^receiver, _}

    for {path, target, options} <- [
          {123, self(), []},
          {"/value", receiver, []},
          {"/value", self(), [renew: 1]},
          {"/value", self(), [max_queue_length: 0]},
          {"/value", self(), [renew: true, renew: false]},
          {"/value", self(), [unknown: true]}
        ] do
      assert {:error, %Error{code: :invalid_observation_options}} =
               Connection.observe(pid, path, target, options, 1_000)
    end

    refute File.exists?(Path.join(context.store, "observe.json"))
    assert :sys.get_state(pid).observation == nil
    assert :ok = Connection.close(pid)
  end

  test "WCO-D04 receiver death releases an established native generation", context do
    File.write!(Path.join(context.store, "mode"), "observe")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    receiver = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, _} =
             Wotex.CoAP.subscribe(session, %{
               path: "/temperature",
               receiver: receiver,
               renew: false
             })

    connection_monitor = Process.monitor(session.pid)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^connection_monitor, :process, _, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
    assert :ok = Wotex.CoAP.disconnect(session)
  end

  test "WCO-D04 native Observe assembles one streamed report under cumulative credit",
       context do
    File.write!(Path.join(context.store, "mode"), "observe_stream")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)

    assert {:ok, handle} =
             Wotex.CoAP.subscribe(session, %{
               path: "/stream",
               receiver: self(),
               renew: false
             })

    reference = handle.reference

    assert_receive {:wotex_coap, ^reference,
                    {:ok, %Message{payload: payload}, %{observe: 10, content_format: 0}}},
                   1_000

    assert payload == :binary.copy("S", 32_769)

    for {name, id, acknowledged} <- [
          {"credit-0.json", "3", 0},
          {"credit-stream-1.json", "4", 1},
          {"credit-stream-5.json", "5", 5}
        ] do
      assert %{
               "id" => ^id,
               "operation" => "credit",
               "parameters" => %{"ack_seq" => ^acknowledged}
             } = read_json(context.store, name)
    end

    assert eventually(fn ->
             match?(%{operation: :credit, ack_seq: 5}, :sys.get_state(session.pid).active)
           end)

    assert :ok = Wotex.CoAP.unsubscribe(session, handle)
    refute Process.alive?(session.pid)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-D04 native Observe returns bounded establishment failures", context do
    for {mode, code} <- [
          {"observe_open_error", :busy},
          {"observe_credit_error", :busy},
          {"observe_bad_establishment", :native_protocol_error},
          {"observe_bad_frame", :native_protocol_error},
          {"observe_invalid_wire", :native_protocol_error},
          {"observe_invalid_json", :native_protocol_error},
          {"observe_early_report", :native_protocol_error},
          {"observe_body_bad", :native_protocol_error},
          {"observe_terminal_bad", :native_protocol_error},
          {"observe_report_error", :observation_failed},
          {"observe_report_bad", :native_protocol_error}
        ] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, session} = Wotex.CoAP.connect(context.options)

      assert {:error, %Error{code: ^code}} =
               Wotex.CoAP.subscribe(session, %{path: "/fault", renew: false})

      assert eventually(fn -> not Process.alive?(session.pid) end)
      assert_helper_stopped(context.store, 1_000)
    end
  end

  test "WCO-D04 native Observe bounds initial report registration", context do
    File.write!(Path.join(context.store, "mode"), "observe_register_timeout")
    assert {:ok, pid} = Connection.start(context.options)

    assert {:error, %Error{code: :timeout}} =
             Connection.observe(pid, "/slow", self(), [renew: false], 100)

    assert eventually(fn -> not Process.alive?(pid) end)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native cancellation returns the helper error and closes", context do
    File.write!(Path.join(context.store, "mode"), "observe_cancel_error")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    assert {:ok, handle} = Wotex.CoAP.subscribe(session, %{path: "/cancel", renew: false})
    reference = handle.reference

    assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "20"}, _}}, 1_000
    assert eventually(fn -> :sys.get_state(session.pid).active == nil end)

    assert {:error, %Error{code: :invalid_cancellation_response}} =
             Wotex.CoAP.unsubscribe(session, handle)

    assert_receive {:wotex_coap, ^reference,
                    {:error, %Error{code: :invalid_cancellation_response}}},
                   1_000

    assert eventually(fn -> not Process.alive?(session.pid) end)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 established native terminal reports exactly once", context do
    File.write!(Path.join(context.store, "mode"), "observe_terminal")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    assert {:ok, handle} = Wotex.CoAP.subscribe(session, %{path: "/terminal", renew: false})
    reference = handle.reference

    assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "20"}, _}}, 1_000
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :observation_stale}}}, 1_000
    refute_received {:wotex_coap, ^reference, _}
    assert eventually(fn -> not Process.alive?(session.pid) end)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native Observe enforces receiver capacity before first delivery", context do
    File.write!(Path.join(context.store, "mode"), "observe")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    receiver = spawn(fn -> receive do: (:release -> :ok) end)
    send(receiver, :occupied)

    assert {:error, %Error{code: :receiver_overflow}} =
             Connection.observe(
               session.pid,
               "/overflow",
               receiver,
               [renew: false, max_queue_length: 1],
               1_000
             )

    assert eventually(fn -> not Process.alive?(session.pid) end)
    Process.exit(receiver, :kill)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 opening caller death releases the native generation", context do
    File.write!(Path.join(context.store, "mode"), "observe_register_timeout")
    assert {:ok, session} = Wotex.CoAP.connect(context.options)
    parent = self()

    caller =
      spawn(fn ->
        send(parent, :observe_started)
        Wotex.CoAP.subscribe(session, %{path: "/abandoned", renew: false})
      end)

    assert_receive :observe_started
    assert eventually(fn -> :sys.get_state(session.pid).observation != nil end)
    connection_monitor = Process.monitor(session.pid)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^connection_monitor, :process, _, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native Observe rejects invalid public call shapes without traffic", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    dead = spawn(fn -> :ok end)
    dead_monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^dead_monitor, :process, ^dead, _}
    {:ok, handle} = Subscription.new(pid, make_ref(), make_ref())

    assert {:error, %Error{code: :invalid_timeout}} =
             Connection.observe(pid, "/value", self(), [], 0)

    assert {:error, %Error{code: :invalid_observation_options}} =
             Connection.observe(pid, "/value", self(), :invalid, 100)

    assert {:error, %Error{code: :invalid_session}} =
             Connection.observe(:invalid, "/value", self(), [], 100)

    assert {:error, %Error{code: :connection_closed}} =
             Connection.observe(dead, "/value", self(), [], 100)

    assert {:error, %Error{code: :invalid_timeout}} = Connection.unobserve(pid, handle, 0)
    assert {:error, %Error{code: :invalid_subscription}} = Connection.unobserve(pid, :bad, 100)
    {:ok, foreign_session} = Subscription.new(self(), make_ref(), make_ref())

    assert {:error, %Error{code: :invalid_session}} =
             Connection.unobserve(self(), foreign_session, 100)

    refute File.exists?(Path.join(context.store, "observe.json"))
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "observe_open_error")
    assert {:ok, options_pid} = Connection.start(context.options)

    assert {:error, %Error{code: :busy}} =
             Connection.observe(
               options_pid,
               "/event",
               self(),
               [
                 renew: false,
                 confirmable: false,
                 observation_kind: :event,
                 max_queue_length: 2,
                 accept: 0
               ],
               1_000
             )

    assert eventually(fn -> not Process.alive?(options_pid) end)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native Observe enforces generation, activity and deadline admission", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    state = :sys.get_state(pid)

    config = %{
      parameters: %{
        path: "/value",
        confirmable: true,
        observation_kind: :property,
        renew: false
      },
      receiver: self(),
      max_queue_length: 1
    }

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(
               pid,
               {:observe, state.generation + 1, config, System.monotonic_time(:millisecond) + 100}
             )

    :sys.replace_state(pid, fn current -> %{current | active: %{operation: :close}} end)

    assert {:error, %Error{code: :busy}} =
             GenServer.call(
               pid,
               {:observe, state.generation, config, System.monotonic_time(:millisecond) + 100}
             )

    :sys.replace_state(pid, fn current -> %{current | active: nil} end)

    assert {:error, %Error{code: :timeout}} =
             GenServer.call(
               pid,
               {:observe, state.generation, config, System.monotonic_time(:millisecond) - 1}
             )

    assert {:error, %Error{code: :invalid_observation_options}} =
             GenServer.call(
               pid,
               {:observe, state.generation, %{config | parameters: %{}},
                System.monotonic_time(:millisecond) + 100}
             )

    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, exhausted} = Connection.start(context.options)
    state = :sys.get_state(exhausted)

    :sys.replace_state(exhausted, fn current ->
      %{current | command: %{current.command | next_id: :exhausted}}
    end)

    assert {:error, %Error{code: :sequence_exhausted}} =
             GenServer.call(
               exhausted,
               {:observe, state.generation, config, System.monotonic_time(:millisecond) + 100}
             )

    assert eventually(fn -> not Process.alive?(exhausted) end)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native cancellation validates generation, phase and active control", context do
    File.write!(Path.join(context.store, "mode"), "observe_wait_control")
    assert {:ok, pid} = Connection.start(context.options)

    caller =
      Task.async(fn -> Connection.observe(pid, "/pending", self(), [renew: false], 2_000) end)

    assert eventually(fn ->
             match?(%{phase: :registering}, :sys.get_state(pid).observation)
           end)

    state = :sys.get_state(pid)
    handle = state.observation.handle

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(
               pid,
               {:unobserve, state.generation + 1, handle, System.monotonic_time(:millisecond) + 100}
             )

    :sys.replace_state(pid, fn current -> %{current | active: %{operation: :close}} end)

    assert {:error, %Error{code: :busy}} =
             GenServer.call(
               pid,
               {:unobserve, state.generation, handle, System.monotonic_time(:millisecond) + 100}
             )

    :sys.replace_state(pid, fn current -> %{current | active: nil} end)

    assert {:error, %Error{code: :observation_active}} =
             GenServer.call(
               pid,
               {:unobserve, state.generation, handle, System.monotonic_time(:millisecond) + 100}
             )

    :sys.replace_state(pid, fn current ->
      %{current | observation: %{current.observation | phase: :active}}
    end)

    assert {:error, %Error{code: :timeout}} =
             GenServer.call(
               pid,
               {:unobserve, state.generation, handle, System.monotonic_time(:millisecond) - 1}
             )

    assert :ok = Connection.close(pid)
    assert {:error, %Error{code: :connection_closed}} = Task.await(caller, 1_000)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-D04 native cancellation fails closed on control exhaustion and Port loss", context do
    for fault <- [:exhausted, :closed_port] do
      File.write!(Path.join(context.store, "mode"), "observe_cancel_error")
      assert {:ok, session} = Wotex.CoAP.connect(context.options)
      assert {:ok, handle} = Wotex.CoAP.subscribe(session, %{path: "/cancel", renew: false})
      assert eventually(fn -> :sys.get_state(session.pid).active == nil end)

      case fault do
        :exhausted ->
          :sys.replace_state(session.pid, fn state ->
            %{state | command: %{state.command | next_id: :exhausted}}
          end)

          assert {:error, %Error{code: :sequence_exhausted}} =
                   Wotex.CoAP.unsubscribe(session, handle)

        :closed_port ->
          closed = Port.open({:spawn_executable, ~c"/usr/bin/true"}, [:exit_status])
          Port.close(closed)
          :sys.replace_state(session.pid, fn state -> %{state | port: closed} end)

          assert {:error, %Error{code: :native_unavailable}} =
                   Wotex.CoAP.unsubscribe(session, handle)
      end

      assert eventually(fn -> not Process.alive?(session.pid) end)
      assert_helper_stopped(context.store, 1_000)
    end
  end

  test "WCO-D04 canceling observations validate terminal and body frames", context do
    for {mode, code} <- [
          {"observe_cancel_terminal", :observation_stale},
          {"observe_cancel_bad_body", :native_protocol_error}
        ] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, session} = Wotex.CoAP.connect(context.options)
      assert {:ok, handle} = Wotex.CoAP.subscribe(session, %{path: "/cancel", renew: false})
      reference = handle.reference
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{}, _}}, 1_000
      assert eventually(fn -> :sys.get_state(session.pid).active == nil end)

      assert {:error, %Error{code: ^code}} = Wotex.CoAP.unsubscribe(session, handle)
      assert_receive {:wotex_coap, ^reference, {:error, %Error{code: ^code}}}, 1_000
      assert eventually(fn -> not Process.alive?(session.pid) end)
      assert_helper_stopped(context.store, 1_000)
    end
  end

  test "WCO-D04 report credit failures close after initial delivery", context do
    for {fault, code} <- [
          {:timeout, :timeout},
          {:exhausted, :sequence_exhausted},
          {:invalid_command, :native_protocol_error},
          {:dead_receiver, :connection_closed}
        ] do
      File.rm(Path.join(context.store, "release"))
      File.rm(Path.join(context.store, "waiting-release"))
      File.rm(Path.join(context.store, "released-report"))
      File.write!(Path.join(context.store, "mode"), "observe_release_report")
      assert {:ok, pid} = Connection.start(context.options)
      parent = self()

      caller =
        Task.async(fn -> Connection.observe(pid, "/credit", parent, [renew: false], 3_000) end)

      assert eventually(fn ->
               match?(%{phase: :registering}, :sys.get_state(pid).observation)
             end)

      wait_for_file(
        Path.join(context.store, "waiting-release"),
        System.monotonic_time(:millisecond) + 1_000
      )

      assert File.exists?(Path.join(context.store, "waiting-release"))

      case fault do
        :timeout ->
          :sys.replace_state(pid, fn state -> %{state | timeout: -1} end)

        :exhausted ->
          :sys.replace_state(pid, fn state ->
            %{state | command: %{state.command | next_id: :exhausted}}
          end)

        :invalid_command ->
          :sys.replace_state(pid, fn state -> %{state | command: :invalid} end)

        :dead_receiver ->
          receiver = spawn(fn -> :ok end)
          receiver_monitor = Process.monitor(receiver)
          assert_receive {:DOWN, ^receiver_monitor, :process, ^receiver, _}

          :sys.replace_state(pid, fn state ->
            %{state | observation: %{state.observation | receiver: receiver}}
          end)
      end

      File.write!(Path.join(context.store, "release"), "go")

      wait_for_file(
        Path.join(context.store, "released-report"),
        System.monotonic_time(:millisecond) + 1_000
      )

      assert File.exists?(Path.join(context.store, "released-report"))

      result = Task.await(caller, 3_500)

      if fault == :dead_receiver do
        assert {:error, %Error{code: ^code}} = result
      else
        assert {:ok, handle} = result
        reference = handle.reference
        assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "20"}, _}}, 1_000
        assert_receive {:wotex_coap, ^reference, {:error, %Error{code: ^code}}}, 1_000
      end

      assert eventually(fn -> not Process.alive?(pid) end)
      assert_helper_stopped(context.store, 1_000)
    end
  end

  test "WCO-D04 native Observe calls bound suspended and terminated owners", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, opening} = Connection.start(context.options)
    :sys.suspend(opening)

    assert {:error, %Error{code: :timeout}} =
             Connection.observe(opening, "/suspended", self(), [renew: false], 10)

    :sys.resume(opening)
    Process.exit(opening, :kill)
    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "observe_idle_exit")
    assert {:ok, canceling} = Connection.start(context.options)

    assert {:ok, handle} =
             Connection.observe(canceling, "/cancel", self(), [renew: false], 1_000)

    assert_receive {:wotex_coap, _, {:ok, %Message{}, _}}, 1_000
    assert eventually(fn -> :sys.get_state(canceling).active == nil end)
    :sys.suspend(canceling)
    assert {:error, %Error{code: :timeout}} = Connection.unobserve(canceling, handle, 10)
    :sys.resume(canceling)
    Process.exit(canceling, :kill)
    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "observe_register_exit")
    assert {:ok, terminated} = Connection.start(context.options)

    caller =
      Task.async(fn ->
        Connection.observe(terminated, "/terminated", self(), [renew: false], 2_000)
      end)

    assert eventually(fn -> :sys.get_state(terminated).observation != nil end)
    Process.exit(terminated, :kill)

    assert {:error, %Error{code: :connection_closed}} = Task.await(caller, 1_000)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 public selection rejects mismatched and incomplete native configuration",
       context do
    for {options, code} <- [
          {[scheme: :coaps] ++ context.options, :unsupported_security},
          {Keyword.delete(context.options, :native_backend), :unsupported_native_backend},
          {Keyword.delete(context.options, :security), :invalid_options},
          {[scheme: :coap, scheme: :coap] ++ context.options, :invalid_options}
        ] do
      assert {:error, %Error{code: ^code}} = Wotex.CoAP.connect(options)
    end

    refute File.exists?(Path.join(context.store, "helper.pid"))
  end

  test "WCO-N02 rejects malformed options and identity before acquiring a process", context do
    invalid = [
      Keyword.put(context.options, :host, "localhost"),
      Keyword.put(context.options, :host, <<255>>),
      Keyword.put(context.options, :host, nil),
      Keyword.put(context.options, :port, 0),
      Keyword.put(context.options, :timeout, :infinity),
      Keyword.put(context.options, :owner, :owner),
      Keyword.put(context.options, :security, nil),
      Keyword.put(context.options, :native_backend, %{}),
      [{:timeout, 1} | context.options],
      [{:unknown, true} | context.options]
    ]

    for options <- invalid do
      assert {:error, %Error{}} = Connection.start(options)
    end

    refute File.exists?(Path.join(context.store, "helper.pid"))
    assert {:error, %Error{code: :invalid_session}} = Connection.close(self())
  end

  test "WCO-N02 closes malformed ready and wrong or duplicate open responses", context do
    for {mode, expected} <- [
          {"wrong_ready", :native_protocol_error},
          {"duplicate_ready_key", :native_protocol_error},
          {"extra_ready", :native_protocol_error},
          {"wrong_open_id", :native_protocol_error},
          {"truncated", :native_protocol_error},
          {"oversize", :native_protocol_error},
          {"open_error", :context_store_locked}
        ] do
      File.write!(Path.join(context.store, "mode"), mode)
      File.rm(Path.join(context.store, "helper.pid"))

      assert {:error, %Error{code: ^expected}} = Connection.start(context.options), mode
      assert_helper_stopped(context.store, 1_000)
    end

    File.write!(Path.join(context.store, "mode"), "duplicate")
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 accepts split frames and closes on native close errors", context do
    File.write!(Path.join(context.store, "mode"), "split")
    assert {:ok, pid} = Connection.start(context.options)
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_error")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :busy}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_malformed")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_partial_exit")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_extra")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
  end

  test "WCO-N02 reserves close control and releases pending callers during termination", context do
    File.write!(Path.join(context.store, "mode"), "close_silent")
    assert {:ok, pid} = Connection.start(context.options)
    closing = Task.async(fn -> Connection.close(pid) end)

    close_path = Path.join(context.store, "close.json")
    wait_for_file(close_path, System.monotonic_time(:millisecond) + 1_000)
    %{generation: generation} = :sys.get_state(pid)

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(
               pid,
               {:close_control, generation, System.monotonic_time(:millisecond) + 1_000, make_ref()}
             )

    assert {:error, %Error{code: :invalid_session}} = GenServer.call(pid, :close)
    waiting = Task.async(fn -> Connection.close(pid) end)
    assert {:error, %Error{code: :timeout}} = Task.await(closing, 1_000)
    assert :ok = Task.await(waiting, 1_000)
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "close_silent")
    File.rm(close_path)
    assert {:ok, pid} = Connection.start(context.options)
    closing = Task.async(fn -> Connection.close(pid) end)
    wait_for_file(close_path, System.monotonic_time(:millisecond) + 1_000)
    assert :ok = GenServer.stop(pid, :shutdown, 1_000)
    assert {:error, %Error{code: :connection_closed}} = Task.await(closing, 1_000)
  end

  test "WCO-N02 owner consumes singular close control outside ordinary capacity", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission, generation: generation} = :sys.get_state(pid)
    deadline = System.monotonic_time(:millisecond) + 5_000

    leases =
      for _ <- 1..64 do
        assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)
        lease
      end

    assert {:error, :busy} = Admission.acquire(admission, pid, generation, deadline)
    assert :ok = Connection.close(pid)
    assert :ets.info(admission) == :undefined
    assert length(leases) == 64
  end

  test "WCO-N02 abandoned close control terminates its generation", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission, generation: generation} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    parent = self()

    caller =
      spawn(fn ->
        result =
          Admission.begin_close(
            admission,
            pid,
            generation,
            System.monotonic_time(:millisecond) + 5_000
          )

        send(parent, {:abandoned_close, self(), result})
      end)

    assert_receive {:abandoned_close, ^caller, {:first, _}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert :ets.info(admission) == :undefined
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 WCO-N03 executes one admitted inline native request", context do
    File.write!(Path.join(context.store, "mode"), "request")
    assert {:ok, pid} = Connection.start(context.options)

    parameters = %{method: :get, path: "/value", confirmable: true, accept: 50}

    assert {:ok,
            %Wotex.CoAP.Message{
              type: :ack,
              code: 69,
              message_id: 321,
              token: <<1>>,
              options: [{12, <<50>>}],
              payload: "ok"
            }} = Connection.request(pid, parameters, 1_000)

    request =
      context.store
      |> Path.join("request-1.json")
      |> File.read!()
      |> Jason.decode!()

    assert request["version"] == 1
    assert request["id"] == "2"
    assert request["operation"] == "request"
    assert request["timeout_ms"] in 1..1_000

    assert request["parameters"] == %{
             "method" => "GET",
             "path" => "/value",
             "confirmable" => true,
             "accept" => 50
           }

    assert :ok = Connection.close(pid)
    assert %{"id" => "3", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N02 WCO-N03 assembles one correlated streamed response body", context do
    File.write!(Path.join(context.store, "mode"), "request_stream")
    assert {:ok, pid} = Connection.start(context.options)

    assert {:ok, %Wotex.CoAP.Message{payload: payload}} =
             Connection.request(
               pid,
               %{method: :get, path: "/large", confirmable: true},
               1_000
             )

    assert payload == :binary.copy("A", 32_769)
    assert :ok = Connection.close(pid)
    assert %{"id" => "3", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N02 WCO-N03 closes failed or wrongly correlated body streams", context do
    for mode <- ["request_stream_bad_hash", "request_stream_wrong_id"] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, pid} = Connection.start(context.options)
      monitor = Process.monitor(pid)

      assert {:error, %Error{code: :native_protocol_error}} =
               Connection.request(
                 pid,
                 %{method: :get, path: "/large", confirmable: true},
                 1_000
               )

      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert_helper_stopped(context.store, 1_000)
      File.rm(Path.join(context.store, "request-1.json"))
    end
  end

  test "WCO-N02 WCO-N03 rejects an unconsumed completed response body", context do
    File.write!(Path.join(context.store, "mode"), "request_stream_inline")
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)

    assert {:error, %Error{code: :native_protocol_error}} =
             Connection.request(
               pid,
               %{method: :get, path: "/large", confirmable: true},
               1_000
             )

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 WCO-N03 uploads a bounded body before native request submission", context do
    File.write!(Path.join(context.store, "mode"), "request_upload")
    assert {:ok, pid} = Connection.start(context.options)
    payload = :binary.copy("B", 32_769)

    assert {:ok, %Wotex.CoAP.Message{payload: "ok"}} =
             Connection.request(
               pid,
               %{
                 method: :post,
                 path: "/large",
                 confirmable: true,
                 content_format: 42,
                 payload: payload
               },
               2_000
             )

    begin_command = read_json(context.store, "body-begin.json")
    first_chunk = read_json(context.store, "body-chunk-1.json")
    last_chunk = read_json(context.store, "body-chunk-2.json")
    end_command = read_json(context.store, "body-end.json")
    request = read_json(context.store, "request-1.json")

    assert %{
             "id" => "2",
             "operation" => "body_begin",
             "parameters" => %{
               "body_id" => "body-1",
               "length" => 32_769,
               "sha256" => hash
             }
           } = begin_command

    assert hash == Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
    assert command_bytes(first_chunk) == binary_part(payload, 0, 32_768)
    assert command_bytes(last_chunk) == binary_part(payload, 32_768, 1)

    assert %{
             "id" => "3",
             "operation" => "body_chunk",
             "parameters" => %{"body_id" => "body-1", "offset" => 0}
           } = first_chunk

    assert %{
             "id" => "4",
             "operation" => "body_chunk",
             "parameters" => %{"body_id" => "body-1", "offset" => 32_768}
           } = last_chunk

    assert %{
             "id" => "5",
             "operation" => "body_end",
             "parameters" => %{"body_id" => "body-1"}
           } = end_command

    assert %{
             "id" => "6",
             "operation" => "request",
             "parameters" => %{
               "method" => "POST",
               "path" => "/large",
               "confirmable" => true,
               "content_format" => 42,
               "body_id" => "body-1"
             }
           } = request

    assert Enum.all?(
             [begin_command, first_chunk, last_chunk, end_command, request],
             &(&1["timeout_ms"] in 1..2_000)
           )

    assert :ok = Connection.close(pid)
    assert %{"id" => "7", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N03 preserves explicit empty and absent outbound bodies", context do
    File.write!(Path.join(context.store, "mode"), "request_upload_empty")
    assert {:ok, pid} = Connection.start(context.options)

    assert {:ok, %Wotex.CoAP.Message{}} =
             Connection.request(
               pid,
               %{method: :post, path: "/empty", confirmable: true, payload: <<>>},
               1_000
             )

    assert %{
             "id" => "2",
             "parameters" => %{"length" => 0, "body_id" => "body-1"}
           } = read_json(context.store, "body-begin.json")

    refute File.exists?(Path.join(context.store, "body-chunk-1.json"))
    assert %{"id" => "3", "operation" => "body_end"} = read_json(context.store, "body-end.json")

    assert %{"id" => "4", "parameters" => %{"body_id" => "body-1"}} =
             read_json(context.store, "request-1.json")

    assert :ok = Connection.close(pid)
    assert %{"id" => "5", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N02 WCO-N03 upload failure closes before mutation submission", context do
    for {mode, timeout, code} <- [
          {"request_upload_error", 1_000, :busy},
          {"request_upload_silent", 100, :timeout}
        ] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, pid} = Connection.start(context.options)
      monitor = Process.monitor(pid)

      assert {:error, %Error{code: ^code, effect: :none}} =
               Connection.request(
                 pid,
                 %{method: :put, path: "/value", confirmable: true, payload: "value"},
                 timeout
               )

      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert_helper_stopped(context.store, 1_000)
      File.rm(Path.join(context.store, "helper.pid"))
      File.rm(Path.join(context.store, "body-begin.json"))
    end
  end

  test "WCO-N02 closes on upload command exhaustion and rejected Port writes", context do
    for {command, code} <- [
          {:invalid, :native_protocol_error},
          {%{next_id: :exhausted}, :sequence_exhausted}
        ] do
      File.write!(Path.join(context.store, "mode"), "valid")
      assert {:ok, pid} = Connection.start(context.options)

      :sys.replace_state(pid, fn state ->
        command = if is_map(command), do: Map.merge(state.command, command), else: command
        %{state | command: command}
      end)

      assert {:error, %Error{code: ^code, effect: :none}} =
               Connection.request(
                 pid,
                 %{method: :put, path: "/value", confirmable: true, payload: "value"},
                 1_000
               )

      assert_helper_stopped(context.store, 1_000)
      File.rm(Path.join(context.store, "helper.pid"))
    end

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    closed = Port.open({:spawn_executable, ~c"/bin/cat"}, [:binary, :use_stdio])
    Port.close(closed)
    :sys.replace_state(pid, fn state -> %{state | port: closed} end)

    assert {:error, %Error{code: :native_unavailable, effect: :none}} =
             Connection.request(
               pid,
               %{method: :put, path: "/value", confirmable: true, payload: "value"},
               1_000
             )

    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 cancelled upload does not submit its mutation", context do
    File.write!(Path.join(context.store, "mode"), "request_upload_cancelled")
    assert {:ok, pid} = Connection.start(context.options)

    request =
      Task.async(fn ->
        Connection.request(
          pid,
          %{method: :post, path: "/value", confirmable: true, payload: "value"},
          5_000
        )
      end)

    wait_for_file(
      Path.join(context.store, "upload-held"),
      System.monotonic_time(:millisecond) + 1_000
    )

    %{calls: calls} = :sys.get_state(pid)
    [lease] = Map.keys(calls)
    assert :cancelled = Admission.cancel_unsubmitted(lease)
    File.write!(Path.join(context.store, "release"), "ok")

    assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(request, 1_000)
    refute File.exists?(Path.join(context.store, "request-1.json"))
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 close interrupts body upload before mutation submission", context do
    File.write!(Path.join(context.store, "mode"), "request_upload_silent")
    assert {:ok, pid} = Connection.start(context.options)

    request =
      Task.async(fn ->
        Connection.request(
          pid,
          %{method: :post, path: "/value", confirmable: true, payload: "value"},
          5_000
        )
      end)

    wait_for_file(
      Path.join(context.store, "body-begin.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    assert :ok = Connection.close(pid)
    assert {:error, %Error{code: :connection_closed, effect: :none}} = Task.await(request, 1_000)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 serializes admitted calls and spends queue time from each deadline", context do
    File.write!(Path.join(context.store, "mode"), "request_two")
    assert {:ok, pid} = Connection.start(context.options)

    first =
      Task.async(fn ->
        Connection.request(pid, %{method: :get, path: "/first", confirmable: true}, 2_000)
      end)

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    second =
      Task.async(fn ->
        Connection.request(pid, %{method: :get, path: "/second", confirmable: false}, 2_000)
      end)

    assert eventually(fn -> map_size(:sys.get_state(pid).calls) == 2 end)
    File.write!(Path.join(context.store, "release"), "ok")
    assert {:ok, %Wotex.CoAP.Message{payload: "ok"}} = Task.await(first, 2_000)
    assert {:ok, %Wotex.CoAP.Message{payload: "ok"}} = Task.await(second, 2_000)

    assert %{"id" => "2", "parameters" => %{"path" => "/first"}} =
             read_json(context.store, "request-1.json")

    assert %{"id" => "3", "parameters" => %{"path" => "/second"}} =
             read_json(context.store, "request-2.json")

    assert :ok = Connection.close(pid)
    assert %{"id" => "4", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N02 queued timeout cancels before native submission", context do
    File.write!(Path.join(context.store, "mode"), "request_hold")
    assert {:ok, pid} = Connection.start(context.options)

    active =
      Task.async(fn ->
        Connection.request(pid, %{method: :get, path: "/active", confirmable: true}, 1_000)
      end)

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    assert {:error, %Error{code: :timeout, effect: :none}} =
             Connection.request(
               pid,
               %{method: :post, path: "/queued", confirmable: true},
               50
             )

    File.write!(Path.join(context.store, "release"), "ok")
    assert {:ok, %Wotex.CoAP.Message{}} = Task.await(active, 1_000)
    assert :ok = Connection.close(pid)
    assert %{"id" => "3", "operation" => "close"} = read_json(context.store, "close.json")
  end

  test "WCO-N02 active mutation timeout closes with unknown effect", context do
    File.write!(Path.join(context.store, "mode"), "request_silent")
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)

    assert {:error, %Error{code: :timeout, effect: :unknown, retryable: false}} =
             Connection.request(
               pid,
               %{method: :put, path: "/value", confirmable: true},
               100
             )

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 invalid requests fail before ordinary admission", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission} = :sys.get_state(pid)

    assert {:error, %Error{code: :invalid_request}} =
             Connection.request(
               pid,
               %{method: :get, path: "/value", confirmable: true, unknown: true},
               1_000
             )

    assert Admission.reservations(admission) == []
    refute File.exists?(Path.join(context.store, "request-1.json"))

    for invalid <- [
          %{method: :post, path: "/value", confirmable: true, body_id: "foreign"},
          %{
            method: :post,
            path: "/value",
            confirmable: true,
            payload: :binary.copy("x", 1_048_577)
          }
        ] do
      assert {:error, %Error{code: :invalid_request}} = Connection.request(pid, invalid, 1_000)
    end

    for invalid_options <- [
          nil,
          [max_body_size: 32_767],
          [max_body_size: 1_048_577],
          [max_body_size: 65_536, max_body_size: 65_536],
          [unknown: 65_536]
        ] do
      assert {:error, %Error{code: :invalid_request}} =
               Connection.request(
                 pid,
                 %{method: :get, path: "/value", confirmable: true},
                 1_000,
                 invalid_options
               )
    end

    assert Admission.reservations(admission) == []
    assert :ok = Connection.close(pid)
  end

  test "WCO-N02 request entry rejects invalid and closed session values", context do
    assert {:error, %Error{code: :invalid_timeout}} = Connection.request(self(), %{}, :infinity)
    assert {:error, %Error{code: :invalid_request}} = Connection.request(self(), [], 1_000)
    assert {:error, %Error{code: :invalid_session}} = Connection.request(self(), %{}, 1_000)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    assert :ok = Connection.close(pid)

    assert {:error, %Error{code: :connection_closed}} =
             Connection.request(pid, %{method: :get, path: "/", confirmable: true}, 1_000)
  end

  test "WCO-N02 retains valid native errors and closes malformed response generations", context do
    File.write!(Path.join(context.store, "mode"), "request_error")
    assert {:ok, pid} = Connection.start(context.options)

    assert {:error, %Error{code: :busy, effect: :none}} =
             Connection.request(pid, %{method: :get, path: "/value", confirmable: true}, 1_000)

    assert Process.alive?(pid)
    assert :ok = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "request_malformed")
    File.rm(Path.join(context.store, "request-1.json"))
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)

    assert {:error, %Error{code: :native_protocol_error}} =
             Connection.request(pid, %{method: :get, path: "/value", confirmable: true}, 1_000)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 rejects coalesced output after a unary response", context do
    File.write!(Path.join(context.store, "mode"), "request_extra")
    assert {:ok, pid} = Connection.start(context.options)
    monitor = Process.monitor(pid)

    assert {:error, %Error{code: :native_protocol_error}} =
             Connection.request(pid, %{method: :get, path: "/value", confirmable: true}, 1_000)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 close interrupts an active mutation and releases queued reads", context do
    File.write!(Path.join(context.store, "mode"), "request_silent")
    assert {:ok, pid} = Connection.start(context.options)

    active =
      Task.async(fn ->
        Connection.request(pid, %{method: :post, path: "/active", confirmable: true}, 5_000)
      end)

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    queued =
      Task.async(fn ->
        Connection.request(pid, %{method: :get, path: "/queued", confirmable: true}, 5_000)
      end)

    assert eventually(fn -> map_size(:sys.get_state(pid).calls) == 2 end)
    assert :ok = Connection.close(pid)

    assert {:error, %Error{code: :connection_closed, effect: :unknown}} =
             Task.await(active, 1_000)

    assert {:error, %Error{code: :connection_closed, effect: :none}} =
             Task.await(queued, 1_000)

    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 active caller death closes the native generation", context do
    File.write!(Path.join(context.store, "mode"), "request_silent")
    assert {:ok, pid} = Connection.start(context.options)
    parent = self()

    caller =
      spawn(fn ->
        send(parent, {:request_caller, self()})
        Connection.request(pid, %{method: :get, path: "/active", confirmable: true}, 5_000)
      end)

    assert_receive {:request_caller, ^caller}

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    monitor = Process.monitor(pid)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 queued caller death is removed before native submission", context do
    File.write!(Path.join(context.store, "mode"), "request_hold")
    assert {:ok, pid} = Connection.start(context.options)

    active =
      Task.async(fn ->
        Connection.request(pid, %{method: :get, path: "/active", confirmable: true}, 2_000)
      end)

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    caller =
      spawn(fn ->
        Connection.request(pid, %{method: :get, path: "/queued", confirmable: true}, 2_000)
      end)

    assert eventually(fn -> map_size(:sys.get_state(pid).calls) == 2 end)
    Process.exit(caller, :kill)
    assert eventually(fn -> map_size(:sys.get_state(pid).calls) == 1 end)
    File.write!(Path.join(context.store, "release"), "ok")
    assert {:ok, %Wotex.CoAP.Message{}} = Task.await(active, 2_000)
    assert :ok = Connection.close(pid)
    refute File.exists?(Path.join(context.store, "request-2.json"))
  end

  test "WCO-N02 rejects forged bounded calls and reaps abandoned leases", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission, generation: generation} = :sys.get_state(pid)
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(pid, {:bounded, generation + 1, %{}, deadline, lease})

    assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)

    assert {:error, %Error{code: :invalid_request}} =
             GenServer.call(pid, {:bounded, generation, :invalid, deadline, lease})

    parent = self()

    caller =
      spawn(fn ->
        result = Admission.acquire(admission, pid, generation, deadline)
        send(parent, {:abandoned_lease, self(), result})
      end)

    assert_receive {:abandoned_lease, ^caller, {:ok, abandoned}}
    assert eventually(fn -> not Admission.owned?(admission, abandoned, caller, deadline) end)
    send(pid, {:reap_admission, make_ref()})
    assert Process.alive?(pid)
    assert :ok = Connection.close(pid)
  end

  test "WCO-N02 applies capacity before the mailbox and honors cancelled submission", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission, generation: generation} = :sys.get_state(pid)
    deadline = System.monotonic_time(:millisecond) + 5_000

    leases =
      for _ <- 1..64 do
        assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)
        lease
      end

    assert {:error, %Error{code: :busy}} =
             Connection.request(pid, %{method: :get, path: "/busy", confirmable: true}, 1_000)

    Enum.each(leases, &Admission.release(admission, &1))
    send(pid, :drain_calls)
    assert eventually(fn -> :sys.get_state(pid).drain_scheduled == false end)
    parent = self()

    caller =
      spawn(fn ->
        {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)
        send(parent, {:cancel_lease, self(), lease})

        receive do
          :submit ->
            parameters = %{method: :get, path: "/cancelled", confirmable: true}
            result = GenServer.call(pid, {:bounded, generation, parameters, deadline, lease})
            send(parent, {:cancelled_submission, self(), result})
        end
      end)

    assert_receive {:cancel_lease, ^caller, lease}
    assert :cancelled = Admission.cancel_unsubmitted(lease)
    send(caller, :submit)
    assert_receive {:cancelled_submission, ^caller, {:error, %Error{code: :timeout}}}
    assert :ok = Connection.close(pid)
  end

  test "WCO-N02 rejects expired, released and malformed bounded capabilities", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission, generation: generation} = :sys.get_state(pid)

    expired = System.monotonic_time(:millisecond) - 1
    assert {:ok, lease} = Admission.acquire(admission, pid, generation, expired)

    assert {:error, %Error{code: :timeout}} =
             GenServer.call(pid, {:bounded, generation, %{}, expired, lease})

    assert {:ok, lease} = Admission.acquire(admission, pid, generation, expired)
    Admission.release(admission, lease)

    assert {:error, %Error{code: :timeout}} =
             GenServer.call(pid, {:bounded, generation, %{}, expired, lease})

    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(pid, {:bounded, generation, %{}, deadline, :invalid})

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(pid, {:close_control, generation, :invalid, make_ref()})

    assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)
    Admission.release(admission, lease)

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(pid, {:bounded, generation, %{}, deadline, lease})

    assert {:ok, lease} = Admission.acquire(admission, pid, generation, deadline)

    assert {:error, %Error{code: :invalid_request}} =
             GenServer.call(pid, {:bounded, generation, %{}, deadline, lease})

    assert :ok = Connection.close(pid)
  end

  test "WCO-N02 request exhaustion and rejected Port writes close the generation", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)

    :sys.replace_state(pid, fn state ->
      %{state | command: %{state.command | next_id: :exhausted}}
    end)

    assert {:error, %Error{code: :sequence_exhausted, effect: :none}} =
             Connection.request(pid, %{method: :get, path: "/value", confirmable: true}, 1_000)

    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    closed = Port.open({:spawn_executable, ~c"/bin/cat"}, [:binary, :use_stdio])
    Port.close(closed)
    :sys.replace_state(pid, fn state -> %{state | port: closed} end)

    assert {:error, %Error{code: :native_unavailable, effect: :none}} =
             Connection.request(pid, %{method: :get, path: "/value", confirmable: true}, 1_000)

    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    :sys.replace_state(pid, fn state -> %{state | next_body_id: :exhausted} end)

    assert {:error, %Error{code: :sequence_exhausted, effect: :none}} =
             Connection.request(
               pid,
               %{method: :put, path: "/value", confirmable: true, payload: "value"},
               1_000
             )

    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 caller timeout cancels a call while the owner mailbox is suspended", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{admission: admission} = :sys.get_state(pid)
    :sys.suspend(pid)

    caller =
      Task.async(fn ->
        Connection.request(pid, %{method: :post, path: "/queued", confirmable: true}, 50)
      end)

    assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(caller, 1_000)
    :sys.resume(pid)
    assert eventually(fn -> Admission.reservations(admission) == [] end)
    assert :ok = Connection.close(pid)
  end

  test "WCO-N02 abrupt owner loss preserves submitted mutation uncertainty", context do
    File.write!(Path.join(context.store, "mode"), "request_silent")
    assert {:ok, pid} = Connection.start(context.options)

    caller =
      Task.async(fn ->
        Connection.request(pid, %{method: :delete, path: "/value", confirmable: true}, 5_000)
      end)

    wait_for_file(
      Path.join(context.store, "request-1.json"),
      System.monotonic_time(:millisecond) + 1_000
    )

    Process.exit(pid, :kill)

    assert {:error, %Error{code: :connection_closed, effect: :unknown}} =
             Task.await(caller, 1_000)

    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-N02 forces an exact helper that ignores graceful termination", context do
    File.write!(context.executable, stubborn_helper_source())
    File.chmod!(context.executable, 0o700)
    File.write!(context.manifest, manifest(digest(context.executable)))

    assert {:ok, pid} = Connection.start(context.options)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-N02 bounds cleanup when the BEAM owner is suspended", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    :sys.suspend(pid)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :cleanup_timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_100
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 closes idle generations on unsolicited output or helper exit", context do
    for mode <- ["unsolicited", "exit_after_open"] do
      File.write!(Path.join(context.store, "mode"), mode)
      assert {:ok, pid} = Connection.start(context.options)
      monitor = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert_helper_stopped(context.store, 1_000)
    end

    File.write!(Path.join(context.store, "mode"), "close_exit")
    assert {:ok, pid} = Connection.start(context.options)
    assert :ok = Connection.close(pid)
    assert :ok = Connection.close(pid)
    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "close_crash")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-C04 a clean helper exit ends active requests as a closed connection",
       context do
    for {method, effect} <- [get: :none, put: :unknown] do
      File.write!(Path.join(context.store, "mode"), "request_exit")
      assert {:ok, pid} = Connection.start(context.options)
      monitor = Process.monitor(pid)

      assert {:error, %Error{code: :connection_closed, effect: ^effect, retryable: false}} =
               Connection.request(pid, %{method: method, path: "/value", confirmable: true}, 1_000)

      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert :ok = Connection.close(pid)
      assert_helper_stopped(context.store, 1_000)
    end
  end

  test "WCO-N02 monitors distinct configured owners and creators", context do
    configured_owner = spawn(fn -> Process.sleep(:infinity) end)
    options = Keyword.put(context.options, :owner, configured_owner)
    File.write!(Path.join(context.store, "mode"), "valid")
    parent = self()

    creator =
      spawn(fn ->
        send(parent, {:created_native, self(), Connection.start(options)})
      end)

    assert_receive {:created_native, ^creator, {:ok, pid}}, 5_000
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)
    Process.exit(configured_owner, :kill)

    configured_owner = spawn(fn -> Process.sleep(:infinity) end)
    options = Keyword.put(context.options, :owner, configured_owner)
    File.write!(Path.join(context.store, "mode"), "silent")
    File.rm(Path.join(context.store, "helper.pid"))

    starter =
      spawn(fn ->
        send(parent, {:opening_native, Connection.start(options)})
      end)

    wait_for_file(
      Path.join(context.store, "helper.pid"),
      System.monotonic_time(:millisecond) + 1_000
    )

    Process.exit(configured_owner, :kill)
    assert_receive {:opening_native, {:error, %Error{code: :connection_closed}}}, 1_000
    assert_helper_stopped(context.store, 1_000)
    refute Process.alive?(starter)

    File.write!(Path.join(context.store, "mode"), "silent")
    File.rm(Path.join(context.store, "helper.pid"))
    creator = spawn(fn -> Connection.start(Keyword.put(context.options, :owner, parent)) end)
    creator_monitor = Process.monitor(creator)

    wait_for_file(
      Path.join(context.store, "helper.pid"),
      System.monotonic_time(:millisecond) + 1_000
    )

    Process.exit(creator, :kill)
    assert_receive {:DOWN, ^creator_monitor, :process, ^creator, :killed}
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 rejects direct messages, foreign identities and exhausted close IDs", context do
    parent = self()

    foreign =
      spawn(fn ->
        Process.put(:wotex_coap_owner, :foreign)
        send(parent, {:foreign_ready, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:foreign_ready, ^foreign}
    assert {:error, %Error{code: :invalid_session}} = Connection.close(foreign)
    Process.exit(foreign, :kill)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    assert {:error, %Error{code: :invalid_session}} = GenServer.call(pid, :foreign)
    %{generation: generation} = :sys.get_state(pid)

    assert {:error, %Error{code: :invalid_session}} =
             GenServer.call(
               pid,
               {:close_control, generation, System.monotonic_time(:millisecond) + 1_000, make_ref()}
             )

    send(pid, :foreign)
    assert Process.alive?(pid)

    :sys.replace_state(pid, fn state ->
      %{state | command: %{state.command | next_id: :exhausted}}
    end)

    assert {:error, %Error{code: :sequence_exhausted}} = Connection.close(pid)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    :sys.replace_state(pid, fn state -> %{state | command: :invalid} end)
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
  end

  test "WCO-N02 closes on exact Port exit and rejected nonblocking writes", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    %{port: port} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    send(pid, {:EXIT, port, :fault})
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    assert_helper_stopped(context.store, 1_000)

    File.write!(Path.join(context.store, "mode"), "valid")
    assert {:ok, pid} = Connection.start(context.options)
    closed = Port.open({:spawn_executable, ~c"/bin/cat"}, [:binary, :use_stdio])
    Port.close(closed)
    :sys.replace_state(pid, fn state -> %{state | port: closed} end)
    assert {:error, %Error{code: :native_unavailable}} = Connection.close(pid)
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-N02 bounds ready and close waits by the caller and local cleanup budgets", context do
    File.write!(Path.join(context.store, "mode"), "silent")
    started = System.monotonic_time(:millisecond)

    assert {:error, %Error{code: :timeout}} =
             Connection.start(Keyword.put(context.options, :timeout, 500))

    assert System.monotonic_time(:millisecond) - started < 1_500
    assert_started_helper_stopped(context.store, 1_000)

    File.rm(Path.join(context.store, "helper.pid"))

    assert {:error, %Error{code: :timeout}} =
             Connection.start(Keyword.put(context.options, :timeout, 1))

    File.write!(Path.join(context.store, "mode"), "close_silent")
    assert {:ok, pid} = Connection.start(context.options)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :timeout}} = Connection.close(pid)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  test "WCO-C03 WCO-N02 owner death releases the exact helper within 1000 ms", context do
    File.write!(Path.join(context.store, "mode"), "valid")
    parent = self()

    owner =
      spawn(fn ->
        result = Connection.start(context.options)
        send(parent, {:native_started, self(), result})
        Process.sleep(:infinity)
      end)

    assert_receive {:native_started, ^owner, {:ok, connection}}, 5_000
    monitor = Process.monitor(connection)
    started = System.monotonic_time(:millisecond)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^connection, _}, 1_000
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_helper_stopped(context.store, 1_000)
  end

  defp options(executable, manifest, store) do
    [
      host: "127.0.0.1",
      port: 5683,
      timeout: 3_000,
      security: security(store),
      native_backend: %{executable: executable, manifest: manifest}
    ]
  end

  defp security(store) do
    {:ok, security} =
      Security.new(%{
        mode: :oscore,
        master_secret: secret_canary(),
        master_salt: <<>>,
        sender_id: <<>>,
        recipient_id: <<1>>,
        context_store: store
      })

    security
  end

  defp secret_canary, do: <<0::128>>
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp assert_helper_stopped(store, timeout) do
    path = Path.join(store, "helper.pid")
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_file(path, deadline)

    os_pid =
      path
      |> File.read!()
      |> String.trim()

    wait_for_exit(os_pid, deadline)
    refute process_alive?(os_pid)
  end

  defp assert_started_helper_stopped(store, timeout) do
    path = Path.join(store, "helper.pid")
    wait_for_file(path, System.monotonic_time(:millisecond) + 100)
    if File.exists?(path), do: assert_helper_stopped(store, timeout)
  end

  defp wait_for_file(path, deadline) do
    if not File.exists?(path) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(5)
      wait_for_file(path, deadline)
    end
  end

  defp wait_for_exit(os_pid, deadline) do
    if process_alive?(os_pid) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(5)
      wait_for_exit(os_pid, deadline)
    end
  end

  defp process_alive?(os_pid) do
    case System.cmd("/bin/kill", ["-0", os_pid],
           stderr_to_stdout: true,
           env: cleared_environment()
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp cleared_environment,
    do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp read_json(directory, name) do
    path = Path.join(directory, name)

    # The helper records each command after reading it from its Port, which can
    # race a test that observes a later owner effect; wait for the whole line.
    assert eventually(
             fn ->
               match?(
                 {:ok, <<_, _::binary>> = line}
                 when binary_part(line, byte_size(line) - 1, 1) == "\n",
                 File.read(path)
               )
             end,
             200
           ),
           "native helper did not record #{name}"

    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp command_bytes(%{
         "parameters" => %{"data" => %{"type" => "bytes", "base64" => encoded}}
       }),
       do: Base.decode64!(encoded)

  defp eventually(function, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(5)
      eventually(function, attempts - 1)
    end
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp manifest(hash) do
    Jason.encode!(%{
      "schema" => "wotex.coap.native@1",
      "backend" => %{"name" => "libcoap", "version" => "4.3.5", "revision" => @revision},
      "executables" => %{"wotex-coap-oscore" => %{"sha256" => hash}}
    })
  end

  defp helper_source do
    """
    #!/usr/bin/env elixir
    :logger.remove_handler(:default)
    # Like the custody helper, exit at once on SIGTERM instead of a graceful VM stop.
    {:ok, _} = System.trap_signal(:sigterm, fn -> System.halt(0) end)
    revision = "#{@revision}"
    ["--custody", directory] = System.argv()
    File.write!(Path.join(directory, "arguments"), Enum.join(System.argv(), "\\n"))
    File.write!(Path.join(directory, "helper.pid"), System.pid())
    mode = directory |> Path.join("mode") |> File.read!() |> String.trim()

    raw = fn bytes ->
      {:ok, output} = :file.open(~c"/dev/fd/1", [:raw, :write, :binary])
      :ok = :file.write(output, bytes)
      :ok = :file.close(output)
    end

    ready_line = ~s({"version":1,"event":"ready","backend":"libcoap","revision":"\#{revision}"}\\n)

    ready = fn ->
      case mode do
        "split" ->
          {left, right} = String.split_at(ready_line, 32)
          raw.(left)
          Process.sleep(50)
          raw.(right)

        "extra_ready" ->
          raw.(ready_line <> ready_line)

        _ ->
          IO.write(ready_line)
      end
    end

    id = fn line ->
      [_, value] = Regex.run(~r/"id":"([^"]+)"/, line)
      value
    end

    read_command = fn name ->
      line = IO.read(:stdio, :line)
      File.write!(Path.join(directory, name), line)
      line
    end

    response = fn request_id ->
      ~s({"version":1,"id":"\#{request_id}","ok":true,"result":null}\\n)
    end

    reply = fn request_id -> IO.write(response.(request_id)) end

    request_line = fn request_id ->
      ~s({"version":1,"id":"\#{request_id}","ok":true,"result":{"type":"ack","code":69,"message_id":321,"token":{"type":"bytes","base64":"AQ=="},"options":[{"number":12,"value":{"type":"bytes","base64":"Mg=="}}],"payload":{"type":"bytes","base64":"b2s="}}}\\n)
    end

    request_reply = fn request_id -> IO.write(request_line.(request_id)) end

    discovery_reply = fn request_id ->
      segment = "</>;x=" <> String.duplicate("a", 1024)
      prefix = Enum.join(List.duplicate(segment, 63), ",") <> ",</>;x="
      body = prefix <> String.duplicate("b", 65_536 - byte_size(prefix))
      first = binary_part(body, 0, 32_768)
      last = binary_part(body, 32_768, 32_768)
      hash = Base.encode16(:crypto.hash(:sha256, body), case: :lower)

      frames =
        ~s({"version":1,"id":"\#{request_id}","event":"body_begin","body_id":"discovery","length":65536,"sha256":"\#{hash}"}\\n) <>
          ~s({"version":1,"id":"\#{request_id}","event":"body_chunk","body_id":"discovery","offset":0,"data":{"type":"bytes","base64":"\#{Base.encode64(first)}"}}\\n) <>
          ~s({"version":1,"id":"\#{request_id}","event":"body_chunk","body_id":"discovery","offset":32768,"data":{"type":"bytes","base64":"\#{Base.encode64(last)}"}}\\n) <>
          ~s({"version":1,"id":"\#{request_id}","event":"body_end","body_id":"discovery"}\\n) <>
          ~s({"version":1,"id":"\#{request_id}","ok":true,"result":{"type":"ack","code":69,"message_id":322,"token":{"type":"bytes","base64":"Ag=="},"options":[{"number":12,"value":{"type":"bytes","base64":"KA=="}}],"body_id":"discovery"}}\\n)

      raw.(frames)
    end

    observe_report = fn subscription_id, generation, sequence, observe, payload ->
      observe_bytes = Base.encode64(:binary.encode_unsigned(observe))
      payload_bytes = Base.encode64(payload)

      ~s({"version":1,"subscription_id":"\#{subscription_id}","generation":\#{generation},"report_seq":\#{sequence},"event":"report","value":{"type":"ack","code":69,"message_id":\#{400 + sequence},"token":{"type":"bytes","base64":"Aw=="},"options":[{"number":6,"value":{"type":"bytes","base64":"\#{observe_bytes}"}},{"number":12,"value":{"type":"bytes","base64":""}}],"payload":{"type":"bytes","base64":"\#{payload_bytes}"}},"metadata":{"code":69,"observe":\#{observe},"etag":null,"content_format":0,"max_age":60}}\\n)
    end

    observe_stream = fn subscription_id, generation ->
      body = :binary.copy("S", 32_769)
      first = binary_part(body, 0, 32_768)
      last = binary_part(body, 32_768, 1)
      hash = Base.encode16(:crypto.hash(:sha256, body), case: :lower)
      observe_bytes = Base.encode64(:binary.encode_unsigned(10))

      ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":1,"event":"body_begin","body_id":"report-body","length":32769,"sha256":"\#{hash}"}\\n) <>
        ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":2,"event":"body_chunk","body_id":"report-body","offset":0,"data":{"type":"bytes","base64":"\#{Base.encode64(first)}"}}\\n) <>
        ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":3,"event":"body_chunk","body_id":"report-body","offset":32768,"data":{"type":"bytes","base64":"\#{Base.encode64(last)}"}}\\n) <>
        ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":4,"event":"body_end","body_id":"report-body"}\\n) <>
        ~s({"version":1,"subscription_id":"\#{subscription_id}","generation":\#{generation},"report_seq":5,"event":"report","value":{"type":"ack","code":69,"message_id":405,"token":{"type":"bytes","base64":"Aw=="},"options":[{"number":6,"value":{"type":"bytes","base64":"\#{observe_bytes}"}},{"number":12,"value":{"type":"bytes","base64":""}}],"body_id":"report-body"},"metadata":{"code":69,"observe":10,"etag":null,"content_format":0,"max_age":60}}\\n)
    end

    canceling_stream = fn subscription_id, generation ->
      body = "Z"
      hash = Base.encode16(:crypto.hash(:sha256, body), case: :lower)
      observe_bytes = Base.encode64(:binary.encode_unsigned(11))

      ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":6,"event":"body_begin","body_id":"late-body","length":1,"sha256":"\#{hash}"}\\n) <>
        ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":7,"event":"body_chunk","body_id":"late-body","offset":0,"data":{"type":"bytes","base64":"Wg=="}}\\n) <>
        ~s({"version":1,"id":"\#{subscription_id}","generation":\#{generation},"report_seq":8,"event":"body_end","body_id":"late-body"}\\n) <>
        ~s({"version":1,"subscription_id":"\#{subscription_id}","generation":\#{generation},"report_seq":9,"event":"report","value":{"type":"ack","code":69,"message_id":409,"token":{"type":"bytes","base64":"Aw=="},"options":[{"number":6,"value":{"type":"bytes","base64":"\#{observe_bytes}"}},{"number":12,"value":{"type":"bytes","base64":""}}],"body_id":"late-body"},"metadata":{"code":69,"observe":11,"etag":null,"content_format":0,"max_age":60}}\\n)
    end

    establish_observe = fn open ->
      [_, generation] = Regex.run(~r/"generation":([0-9]+)/, open)
      generation = String.to_integer(generation)
      observe = read_command.("observe.json")
      subscription_id = id.(observe)

      IO.write(
        ~s({"version":1,"id":"\#{subscription_id}","ok":true,"result":{"subscription_id":"\#{subscription_id}","generation":\#{generation}}}\\n)
      )

      {subscription_id, generation}
    end

    terminal_report = fn subscription_id, generation, code ->
      ~s({"version":1,"subscription_id":"\#{subscription_id}","generation":\#{generation},"event":"error","value":{"code":"\#{code}"},"metadata":{}}\\n)
    end

    stream_reply = fn request_id, event_id, expected_hash, result_kind ->
      body = :binary.copy("A", 32_769)
      first = binary_part(body, 0, 32_768)
      last = binary_part(body, 32_768, 1)

      hash =
        if expected_hash == :valid,
          do: Base.encode16(:crypto.hash(:sha256, body), case: :lower),
          else: expected_hash

      frames =
        ~s({"version":1,"id":"\#{event_id}","event":"body_begin","body_id":"b1","length":32769,"sha256":"\#{hash}"}\\n) <>
          ~s({"version":1,"id":"\#{event_id}","event":"body_chunk","body_id":"b1","offset":0,"data":{"type":"bytes","base64":"\#{Base.encode64(first)}"}}\\n) <>
          ~s({"version":1,"id":"\#{event_id}","event":"body_chunk","body_id":"b1","offset":32768,"data":{"type":"bytes","base64":"\#{Base.encode64(last)}"}}\\n) <>
          ~s({"version":1,"id":"\#{event_id}","event":"body_end","body_id":"b1"}\\n)

      result =
        case result_kind do
          :body ->
            ~s({"version":1,"id":"\#{request_id}","ok":true,"result":{"type":"ack","code":69,"message_id":321,"token":{"type":"bytes","base64":"AQ=="},"options":[],"body_id":"b1"}}\\n)

          :inline ->
            ~s({"version":1,"id":"\#{request_id}","ok":true,"result":{"type":"ack","code":69,"message_id":321,"token":{"type":"bytes","base64":"AQ=="},"options":[],"payload":{"type":"bytes","base64":"b2s="}}}\\n)
        end

      raw.(frames <> result)
    end

    wait_release = fn wait_release ->
      if File.exists?(Path.join(directory, "release")) do
        :ok
      else
        Process.sleep(5)
        wait_release.(wait_release)
      end
    end

    case mode do
      "silent" ->
        Process.sleep(:infinity)

      "wrong_ready" ->
        IO.write(~s({"version":1,"event":"ready","backend":"other","revision":"\#{revision}"}\\n))
        Process.sleep(:infinity)

      "duplicate_ready_key" ->
        IO.write(~s({"version":1,"version":1,"event":"ready","backend":"libcoap","revision":"\#{revision}"}\\n))
        Process.sleep(:infinity)

      "truncated" ->
        IO.write(~s({"version":1,"padding":") <> String.duplicate("x", 65_536))
        Process.sleep(50)

      "oversize" ->
        IO.write(String.duplicate("x", 131_072) <> "\\n")
        Process.sleep(:infinity)

      _ ->
        ready.()
        open = IO.read(:stdio, :line)
        File.write!(Path.join(directory, "open.json"), open)
        open_id = id.(open)

        case mode do
          "wrong_open_id" ->
            reply.("wrong")
            Process.sleep(:infinity)

          "open_error" ->
            IO.write(~s({"version":1,"id":"\#{open_id}","ok":false,"error":{"code":"context_store_locked"}}\\n))
            Process.sleep(:infinity)

          "duplicate" ->
            reply.(open_id)
            Process.sleep(50)
            reply.(open_id)
            Process.sleep(:infinity)

          "unsolicited" ->
            reply.(open_id)
            Process.sleep(50)
            IO.write("{}\\n")
            Process.sleep(:infinity)

          "exit_after_open" ->
            reply.(open_id)
            Process.sleep(50)

          _ ->
            reply.(open_id)

            close =
              case mode do
                "request" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  request_reply.(id.(request))
                  IO.read(:stdio, :line)

                "request_stream" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  request_id = id.(request)
                  stream_reply.(request_id, request_id, :valid, :body)
                  IO.read(:stdio, :line)

                "request_stream_bad_hash" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  request_id = id.(request)
                  stream_reply.(request_id, request_id, String.duplicate("0", 64), :body)
                  IO.read(:stdio, :line)

                "request_stream_wrong_id" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  stream_reply.(id.(request), "wrong", :valid, :body)
                  IO.read(:stdio, :line)

                "request_stream_inline" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  request_id = id.(request)
                  stream_reply.(request_id, request_id, :valid, :inline)
                  IO.read(:stdio, :line)

                "request_discovery" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  discovery_reply.(id.(request))
                  IO.read(:stdio, :line)

                "request_discovery_oversize" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(request)}","event":"body_begin","body_id":"discovery","length":65537,"sha256":"\#{String.duplicate("0", 64)}"}\\n)
                  )

                  Process.sleep(:infinity)

                "observe" ->
                  [_, generation] = Regex.run(~r/"generation":([0-9]+)/, open)
                  generation = String.to_integer(generation)
                  observe = read_command.("observe.json")
                  subscription_id = id.(observe)

                  IO.write(
                    ~s({"version":1,"id":"\#{subscription_id}","ok":true,"result":{"subscription_id":"\#{subscription_id}","generation":\#{generation}}}\\n)
                  )

                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  credit1 = read_command.("credit-1.json")
                  reply.(id.(credit1))
                  IO.write(observe_report.(subscription_id, generation, 2, 11, "21"))
                  credit2 = read_command.("credit-2.json")
                  cancel = read_command.("cancel.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(credit2)}","ok":false,"error":{"code":"busy"}}\\n)
                  )

                  IO.write(observe_report.(subscription_id, generation, 3, 12, "22"))
                  reply.(id.(cancel))
                  Process.sleep(:infinity)

                "observe_stream" ->
                  [_, generation] = Regex.run(~r/"generation":([0-9]+)/, open)
                  generation = String.to_integer(generation)
                  observe = read_command.("observe.json")
                  subscription_id = id.(observe)

                  IO.write(
                    ~s({"version":1,"id":"\#{subscription_id}","ok":true,"result":{"subscription_id":"\#{subscription_id}","generation":\#{generation}}}\\n)
                  )

                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  raw.(observe_stream.(subscription_id, generation))
                  credit1 = read_command.("credit-stream-1.json")
                  reply.(id.(credit1))
                  credit5 = read_command.("credit-stream-5.json")
                  cancel = read_command.("cancel.json")
                  raw.(canceling_stream.(subscription_id, generation))
                  reply.(id.(credit5))
                  reply.(id.(cancel))
                  Process.sleep(:infinity)

                "observe_open_error" ->
                  observe = read_command.("observe.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(observe)}","ok":false,"error":{"code":"busy"}}\\n)
                  )

                  Process.sleep(:infinity)

                "observe_credit_error" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(credit0)}","ok":false,"error":{"code":"busy"}}\\n)
                  )

                  Process.sleep(:infinity)

                "observe_bad_establishment" ->
                  [_, generation] = Regex.run(~r/"generation":([0-9]+)/, open)
                  observe = read_command.("observe.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(observe)}","ok":true,"result":{"subscription_id":"different","generation":\#{generation}}}\\n)
                  )

                  Process.sleep(:infinity)

                "observe_bad_frame" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write("{}\\n")
                  Process.sleep(:infinity)

                "observe_invalid_wire" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write("\\r\\n")
                  Process.sleep(:infinity)

                "observe_invalid_json" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write("{\\n")
                  Process.sleep(:infinity)

                "observe_early_report" ->
                  {subscription_id, generation} = establish_observe.(open)
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  Process.sleep(:infinity)

                "observe_body_bad" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(~s({"version":1,"event":"body_begin"}\\n))
                  Process.sleep(:infinity)

                "observe_terminal_bad" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(~s({"version":1,"event":"error"}\\n))
                  Process.sleep(:infinity)

                "observe_report_error" ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(terminal_report.(subscription_id, generation, "observation_failed"))
                  Process.sleep(:infinity)

                "observe_report_bad" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(~s({"version":1,"event":"report"}\\n))
                  Process.sleep(:infinity)

                "observe_register_timeout" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write("{")
                  Process.sleep(:infinity)

                "observe_register_exit" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.read(:stdio, :line)

                "observe_release_report" ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  File.write!(Path.join(directory, "waiting-release"), "waiting")
                  wait_release.(wait_release)
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  File.write!(Path.join(directory, "released-report"), "released")
                  Process.sleep(:infinity)

                "observe_wait_control" ->
                  establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  close = read_command.("close.json")
                  reply.(id.(close))
                  Process.sleep(:infinity)

                "observe_cancel_error" ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  credit1 = read_command.("credit-1.json")
                  reply.(id.(credit1))
                  cancel = read_command.("cancel.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(cancel)}","ok":false,"error":{"code":"invalid_cancellation_response"}}\\n)
                  )

                  Process.sleep(:infinity)

                "observe_idle_exit" ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  credit1 = read_command.("credit-1.json")
                  reply.(id.(credit1))
                  IO.read(:stdio, :line)

                "observe_terminal" ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  credit1 = read_command.("credit-1.json")
                  reply.(id.(credit1))
                  IO.write(terminal_report.(subscription_id, generation, "observation_stale"))
                  Process.sleep(:infinity)

                mode when mode in ["observe_cancel_terminal", "observe_cancel_bad_body"] ->
                  {subscription_id, generation} = establish_observe.(open)
                  credit0 = read_command.("credit-0.json")
                  reply.(id.(credit0))
                  IO.write(observe_report.(subscription_id, generation, 1, 10, "20"))
                  credit1 = read_command.("credit-1.json")
                  reply.(id.(credit1))
                  read_command.("cancel.json")

                  case mode do
                    "observe_cancel_terminal" ->
                      IO.write(
                        terminal_report.(subscription_id, generation, "observation_stale")
                      )

                    "observe_cancel_bad_body" ->
                      IO.write(~s({"version":1,"event":"body_begin"}\\n))
                  end

                  Process.sleep(:infinity)

                "request_upload" ->
                  begin_command = read_command.("body-begin.json")
                  reply.(id.(begin_command))
                  first_chunk = read_command.("body-chunk-1.json")
                  reply.(id.(first_chunk))
                  last_chunk = read_command.("body-chunk-2.json")
                  reply.(id.(last_chunk))
                  end_command = read_command.("body-end.json")
                  reply.(id.(end_command))
                  request = read_command.("request-1.json")
                  request_reply.(id.(request))
                  IO.read(:stdio, :line)

                "request_upload_empty" ->
                  begin_command = read_command.("body-begin.json")
                  reply.(id.(begin_command))
                  end_command = read_command.("body-end.json")
                  reply.(id.(end_command))
                  request = read_command.("request-1.json")
                  request_reply.(id.(request))
                  IO.read(:stdio, :line)

                "request_upload_error" ->
                  begin_command = read_command.("body-begin.json")

                  IO.write(
                    ~s({"version":1,"id":"\#{id.(begin_command)}","ok":false,"error":{"code":"busy"}}\\n)
                  )

                  IO.read(:stdio, :line)

                "request_upload_silent" ->
                  read_command.("body-begin.json")
                  IO.read(:stdio, :line)

                "request_upload_cancelled" ->
                  begin_command = read_command.("body-begin.json")
                  File.write!(Path.join(directory, "upload-held"), "ok")
                  wait_release.(wait_release)
                  reply.(id.(begin_command))
                  chunk = read_command.("body-chunk-1.json")
                  reply.(id.(chunk))
                  end_command = read_command.("body-end.json")
                  reply.(id.(end_command))
                  IO.read(:stdio, :line)

                "request_hold" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  wait_release.(wait_release)
                  request_reply.(id.(request))
                  IO.read(:stdio, :line)

                "request_two" ->
                  first = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), first)
                  wait_release.(wait_release)
                  request_reply.(id.(first))
                  second = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-2.json"), second)
                  request_reply.(id.(second))
                  IO.read(:stdio, :line)

                "request_silent" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  IO.read(:stdio, :line)

                "request_exit" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  System.halt(0)

                "request_error" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  IO.write(~s({"version":1,"id":"\#{id.(request)}","ok":false,"error":{"code":"busy"}}\\n))
                  IO.read(:stdio, :line)

                "request_malformed" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  IO.write("not-json\\n")
                  Process.sleep(:infinity)

                "request_extra" ->
                  request = IO.read(:stdio, :line)
                  File.write!(Path.join(directory, "request-1.json"), request)
                  line = request_line.(id.(request))
                  raw.(line <> line)
                  Process.sleep(:infinity)

                _ ->
                  IO.read(:stdio, :line)
              end

            if is_binary(close) do
              File.write!(Path.join(directory, "close.json"), close)

              case mode do
                "close_silent" ->
                  Process.sleep(:infinity)

                "close_error" ->
                  IO.write(~s({"version":1,"id":"\#{id.(close)}","ok":false,"error":{"code":"busy"}}\\n))
                  Process.sleep(:infinity)

                "close_malformed" ->
                  IO.write("{}\\n")
                  Process.sleep(:infinity)

                "close_partial_exit" ->
                  raw.(String.duplicate("x", 65_536))
                  Process.sleep(50)

                "close_extra" ->
                  line = response.(id.(close))
                  raw.(line <> line)
                  Process.sleep(:infinity)

                "close_exit" ->
                  :ok

                "close_crash" ->
                  System.halt(70)

                "split" ->
                  line = response.(id.(close))
                  {left, right} = String.split_at(line, 24)
                  raw.(left)
                  Process.sleep(50)
                  raw.(right)

                _ ->
                  reply.(id.(close))
              end
            end
        end
    end
    """
  end

  defp stubborn_helper_source do
    """
    #!/bin/sh
    trap '' TERM
    directory="$2"
    printf '%s' "$$" > "$directory/helper.pid"
    printf '%s\\n' '{"version":1,"event":"ready","backend":"libcoap","revision":"#{@revision}"}'
    IFS= read -r open
    printf '%s\\n' '{"version":1,"id":"1","ok":true,"result":null}'
    IFS= read -r close
    while :; do :; done
    """
  end
end
