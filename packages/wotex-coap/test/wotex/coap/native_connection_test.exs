defmodule Wotex.CoAP.NativeConnectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.{Error, Security}
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
    assert {:error, %Error{code: :native_protocol_error}} = Connection.close(pid)
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
    directory
    |> Path.join(name)
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
