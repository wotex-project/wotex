defmodule Wotex.OPCUA.PersistentBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.{Error, Open62541, Session, Subscription}
  alias Wotex.OPCUA.Native.Host

  @client_options [
    executable: "/missing/native",
    executable_digest: String.duplicate("a", 64),
    guardian: "/missing/guardian",
    guardian_digest: String.duplicate("b", 64),
    endpoint: "opc.tcp://127.0.0.1:4840/fixture/",
    security_policy: :basic256sha256,
    security_mode: :sign_and_encrypt,
    client_uri: "urn:wotex:test:client",
    server_uri: "urn:wotex:test:server",
    certificate: "/missing/client.der",
    private_key: "/missing/client.key.der",
    server_certificate: "/missing/server.der",
    trust_certificate: "/missing/ca.der",
    crl: "/missing/clean.crl",
    authentication: %{type: :anonymous}
  ]

  @corpus "docs/specs/fixtures/native-contract-v1.json"
  @corpus_sha256 :crypto.hash(:sha256, File.read!(@corpus)) |> Base.encode16(case: :lower)
  @cases @corpus
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("cases")
         |> Map.new(&{&1["id"], &1})
  @yyjson ~w(-DYYJSON_DISABLE_NON_STANDARD=1 -DYYJSON_DISABLE_UTILS=1
    -DYYJSON_DISABLE_INCR_READER=1 -DYYJSON_DISABLE_FAST_FP_CONV=0
    -DYYJSON_DISABLE_UTF8_VALIDATION=0)
  @bytes %{"type" => "bytes", "base64" => "AQ=="}
  @open %{
    "endpoint" => "opc.tcp://127.0.0.1:4840",
    "security_policy" => "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
    "security_mode" => "SignAndEncrypt",
    "client_uri" => "urn:client",
    "server_uri" => "urn:server",
    "certificate" => @bytes,
    "private_key" => @bytes,
    "server_certificate" => @bytes,
    "trust_certificate" => @bytes,
    "crl" => @bytes,
    "authentication" => %{"type" => "anonymous"},
    "session_timeout_ms" => 60_000
  }

  setup_all do
    directory =
      Path.join(System.tmp_dir!(), "wotex-opcua-bridge-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("native bridge tests require a C11 compiler")
    root = Path.expand("../../..", __DIR__)
    native = &Path.join([root, "priv/native", &1])

    for {sources, flags, output} <- [
          {[native.("custody.c")], [], "guardian"},
          {[Path.join(root, "test/native/host_probe.c")], [], "probe"},
          {[Path.join(root, "test/native/owner_fixture.c")] ++
             Enum.map(~w(owner.c output.c ipc.c json_codec.c vendor/yyjson/yyjson.c), native),
           @yyjson, "owner_fixture"}
        ] do
      {diagnostic, status} =
        System.cmd(
          compiler,
          ["-std=c11", "-Wall", "-Wextra", "-Werror"] ++
            flags ++ sources ++ ["-o", Path.join(directory, output)],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0, diagnostic
    end

    # Pay macOS first-launch assessment outside deadline assertions.
    assert {_, 126} =
             System.cmd(Path.join(directory, "guardian"), ["--warm"], env: [{"LC_ALL", "C"}])

    assert {_, 40} = System.cmd(Path.join(directory, "probe"), ["--warm"], env: [{"LC_ALL", "C"}])

    %{directory: directory}
  end

  test "WOP-S02 32 concurrent callers correlate native results by request identity", context do
    {host, directory} = open_fixture(context)

    tasks =
      for value <- 1..32 do
        Task.async(fn ->
          {value, Host.request(host, "read", read("value-#{value}"), 5000)}
        end)
      end

    for {value, result} <- Task.await_many(tasks, 10_000) do
      expected = value * 1.0
      assert {:ok, %{"has_value" => true, "value" => %{"value" => ^expected}}} = result
    end

    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"requests" => 32, "closes" => 1, "cancels" => 0} = counters(directory)
    assert_reaped(directory)
  end

  @tag case: "WOP-X-F20", corpus_sha256: @corpus_sha256
  test "WOP-X-F20 64 unfinished requests bound admission and close uses its reserve", context do
    fixture = Map.fetch!(@cases, "WOP-X-F20")
    %{"requests" => requests, "capacity" => capacity} = fixture["input"]
    expected = fixture["expectation"]["value"]
    {host, directory} = open_fixture(context)

    held =
      for index <- 1..capacity do
        Task.async(fn -> Host.request(host, "read", read("hold-#{index}"), 10_000) end)
      end

    assert eventually(fn -> outstanding(host) == capacity end)

    busy =
      for _ <- (capacity + 1)..requests do
        Host.request(host, "read", read("value-1"), 1000)
      end

    assert Enum.count(busy, &match?({:error, %Error{code: :busy}}, &1)) == expected["busy"]
    assert outstanding(host) == expected["admitted"]
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)

    for result <- Task.await_many(held, 5000) do
      assert {:error, %Error{code: :native_process_terminated, effect: :none}} = result
    end

    counters = counters(directory)
    assert counters["requests"] <= capacity and counters["closes"] == 1
    assert counters["occupied"] == expected["remaining_requests"]
    assert_reaped(directory)
  end

  @tag case: "WOP-X-F19", corpus_sha256: @corpus_sha256
  test "WOP-X-F19 a cancelled transmitted Write reaches Runtime as a permanent unknown effect",
       context do
    expected = Map.fetch!(@cases, "WOP-X-F19")["expectation"]["value"]
    {host, directory} = open_fixture(context)

    assert {:error, %Error{code: :deadline_exceeded, effect: :unknown} = error} =
             Host.request(host, "write", write("hold"), 100)

    classified = Error.classify(error)
    assert eventually(fn -> map_size(:sys.get_state(host).controls) == 0 end)
    refute_receive {:wotex_opcua_native, ^host, _}, 50
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    %{"requests" => requests, "cancels" => 1} = counters(directory)

    # owner_check binds the native late-result suppression; this host path binds
    # the Runtime class and effect of the same transmitted cancellation.
    assert %{
             "write_requests" => requests,
             "effect" => Atom.to_string(classified.effect),
             "class" => Atom.to_string(classified.class)
           } == Map.take(expected, ["write_requests", "effect", "class"])

    refute classified.retryable
    assert_reaped(directory)
  end

  test "WOP-X04 caller timeout retires held work and keeps the Session usable", context do
    {host, directory} = open_fixture(context)

    # The host timer and the translated native deadline expire together; either
    # side may report first, and both retire the held request with protocol Cancel.
    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} =
             Host.request(host, "read", read("hold"), 100)

    assert {:error, %Error{code: :deadline_exceeded, effect: :unknown}} =
             Host.request(host, "write", write("hold"), 100)

    assert {:ok, %{"value" => %{"value" => 7.0}}} =
             Host.request(host, "read", read("value-7"), 1000)

    assert eventually(fn -> map_size(:sys.get_state(host).controls) == 0 end)
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"requests" => 3, "cancels" => 2} = counters(directory)
    assert_reaped(directory)
  end

  test "WOP-X04 timed-out bursts to a stalled native owner stay within its output bound",
       context do
    {host, directory} = open_fixture(context)
    [native, _] = String.split(File.read!(Path.join(directory, "host.pid")))
    assert {_, 0} = System.cmd("/bin/kill", ["-STOP", native], env: [{"LC_ALL", "C"}])

    results =
      try do
        for _ <- 1..100, do: Host.request(host, "read", read("hold"), 5)
      after
        System.cmd("/bin/kill", ["-CONT", native], env: [{"LC_ALL", "C"}])
      end

    assert Enum.all?(results, fn
             {:error, %Error{code: code}} -> code in [:deadline_exceeded, :busy]
             _ -> false
           end)

    assert Enum.any?(results, &match?({:error, %Error{code: :busy}}, &1))
    state = :sys.get_state(host)
    assert map_size(state.pending) + map_size(state.controls) <= 80

    assert eventually(fn ->
             state = :sys.get_state(host)
             map_size(state.pending) == 0 and map_size(state.controls) == 0
           end)

    refute_received {:wotex_opcua_native, ^host, _}

    assert {:ok, %{"value" => %{"value" => 3.0}}} =
             Host.request(host, "read", read("value-3"), 1000)

    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"status" => 0} = counters(directory)
    assert_reaped(directory)
  end

  test "WOP-C03 caller death during blocked work sends one cancellation", context do
    {host, directory} = open_fixture(context)
    caller = spawn(fn -> Host.request(host, "call", call("hold"), 10_000) end)
    assert eventually(fn -> outstanding(host) == 1 end)
    Process.exit(caller, :kill)
    assert eventually(fn -> outstanding(host) == 0 end)
    assert eventually(fn -> map_size(:sys.get_state(host).controls) == 0 end)

    assert {:ok, %{"status" => 0}} = Host.request(host, "write", write("value-1"), 1000)
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"requests" => 2, "cancels" => 1} = counters(directory)
    assert_reaped(directory)
  end

  test "WOP-S01 a Bad service status is request-scoped with its operation effect", context do
    {host, directory} = open_fixture(context)

    assert {:error, %Error{code: :remote_error, effect: :none, details: details}} =
             Host.request(host, "read", read("bad"), 1000)

    assert details == %{phase: :exchange, status: 0x803B0000}

    assert {:error, %Error{code: :remote_error, effect: :unknown}} =
             Host.request(host, "write", write("bad"), 1000)

    assert {:error, %Error{code: :invalid_value, effect: :none}} =
             Host.request(host, "read", %{"node_id" => "ns=2;s=unknown"}, 1000)

    assert {:ok, %{"value" => %{"value" => 5.0}}} =
             Host.request(host, "health", read("value-5"), 1000)

    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"requests" => 3} = counters(directory)
    assert_reaped(directory)
  end

  test "WOP-X04 Session loss fails each unanswered request with its own effect", context do
    {host, directory} = open_fixture(context)
    parent = self()

    for {operation, parameters} <- [{"read", read("hold")}, {"write", write("hold")}] do
      spawn(fn ->
        send(parent, {operation, Host.request(host, operation, parameters, 5000)})
      end)
    end

    assert eventually(fn -> outstanding(host) == 2 end)
    monitor = Process.monitor(host)

    assert {:error, %Error{code: :connection_failed, effect: :none}} =
             Host.request(host, "read", read("lose"), 5000)

    assert_receive {"read", {:error, %Error{code: :connection_failed, effect: :none}}}
    assert_receive {"write", {:error, %Error{code: :connection_failed, effect: :unknown}}}
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    refute_receive {:wotex_opcua_native, ^host, _}
    assert %{"requests" => 3, "status" => 70} = counters(directory)
    assert_reaped(directory)
  end

  @tag case: "WOP-X-F22", corpus_sha256: @corpus_sha256
  test "WOP-X-F22 owner death during Session activation leaves no connected result", context do
    expected = Map.fetch!(@cases, "WOP-X-F22")["expectation"]["value"]
    options = fixture_options(context, "owner_fixture")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, host, _} = Host.start_link(options)
        send(parent, {:host, host})
        open = %{@open | "endpoint" => "opc.tcp://slow-open:4840"}
        send(parent, {:connected, Host.request(host, "open", open, 5000)})
      end)

    assert_receive {:host, host}, 5000
    directory = Path.dirname(options[:executable])
    host_monitor = Process.monitor(host)
    assert eventually(fn -> outstanding(host) == 1 end)
    began = System.monotonic_time(:millisecond)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^host_monitor, :process, ^host, _}, expected["max_cleanup_ms"]
    assert_reaped(directory)
    assert System.monotonic_time(:millisecond) - began <= expected["max_cleanup_ms"]

    connected = if receive_connected(), do: 1, else: 0

    assert connected == expected["connected_results"]
    assert %{"occupied" => active} = counters(directory)
    assert active == expected["active_local_resources"]
  end

  @tag case: "WOP-X-F51", corpus_sha256: @corpus_sha256
  test "WOP-X-F51 a response for another generation is never delivered", context do
    expected = Map.fetch!(@cases, "WOP-X-F51")["expectation"]["value"]
    {host, directory} = open_probe(context, "session_response_foreign")
    monitor = Process.monitor(host)
    result = Host.request(host, "read", read("value-1"), 1000)
    code = String.to_existing_atom(expected["terminal_error"])
    assert {:error, %Error{code: ^code}} = result
    assert Enum.count([result], &match?({:ok, _}, &1)) == expected["delivered_successes"]
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_reaped(directory)
  end

  for id <- ["WOP-X-F56", "WOP-X-F57"] do
    @tag case: id, corpus_sha256: @corpus_sha256
    test "#{id} terminal control assigns per-request effects", context do
      fixture = Map.fetch!(@cases, unquote(id))
      expected = fixture["expectation"]["value"]
      generation = fixture["input"]["frame"]["generation"] - fixture["input"]["owner_generation"]
      mode = if generation == 0, do: "session_terminal_pending", else: "session_terminal_foreign"
      {host, directory} = open_probe(context, mode)
      parent = self()

      for pending <- fixture["input"]["pending_operations"], pending["emitted_to_native"] do
        spawn(fn ->
          send(
            parent,
            {pending["id"],
             Host.request(host, pending["operation"], parameters(pending["operation"]), 5000)}
          )
        end)
      end

      assert eventually(fn -> File.exists?(Path.join(directory, "received")) end)
      monitor = Process.monitor(host)
      :ok = :sys.suspend(host)
      File.write!(Path.join(directory, "trigger"), "go")
      assert eventually(fn -> message_queue(host) >= 1 end)

      for pending <- fixture["input"]["pending_operations"], not pending["emitted_to_native"] do
        spawn(fn ->
          send(
            parent,
            {pending["id"],
             Host.request(host, pending["operation"], parameters(pending["operation"]), 5000)}
          )
        end)
      end

      assert eventually(fn -> message_queue(host) >= 2 end)
      :ok = :sys.resume(host)
      code = String.to_existing_atom(expected["terminal_error"])

      for {request, effect} <- expected["effects"] do
        effect = String.to_existing_atom(effect)
        assert_receive {^request, {:error, %Error{effect: ^effect} = error}}, 2000

        if Enum.find(fixture["input"]["pending_operations"], &(&1["id"] == request))[
             "emitted_to_native"
           ],
           do: assert(error.code == code)
      end

      assert expected["successful_results"] == 0
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      assert_reaped(directory)
    end
  end

  test "WOP-X03 coalesced and byte-split native output lines are correlated", context do
    {host, directory} = open_probe(context, "session_split_responses")

    first = Task.async(fn -> Host.request(host, "read", read("value-1"), 5000) end)
    assert eventually(fn -> outstanding(host) == 1 end)
    second = Task.async(fn -> Host.request(host, "read", read("value-2"), 5000) end)

    assert {:ok, %{"value" => %{"value" => 1.0}}} = Task.await(first)
    assert {:ok, %{"value" => %{"value" => 2.0}}} = Task.await(second)

    assert {:ok, %{"value" => %{"value" => 3.0}}} =
             Host.request(host, "read", read("value-3"), 5000)

    assert Process.alive?(host)
    GenServer.stop(host, :normal)
    assert_reaped(directory)
  end

  test "WOP-X04 unsupported, unencodable and unprivileged requests preserve the Session",
       context do
    {host, directory} = open_fixture(context)

    assert {:error, %Error{code: :unsupported_protocol}} =
             Host.request(host, "subscribe", %{}, 1000)

    assert {:error, %Error{code: :invalid_native_frame}} =
             Host.request(host, "read", %{"node_id" => {:not, :json}}, 1000)

    parent = self()
    spawn(fn -> send(parent, {:foreign_close, Host.request(host, "close", %{}, 1000)}) end)
    assert_receive {:foreign_close, {:error, %Error{code: :invalid_native_handle}}}

    assert {:ok, %{"value" => %{"value" => 2.0}}} =
             Host.request(host, "read", read("value-2"), 1000)

    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert %{"requests" => 1} = counters(directory)
    assert_reaped(directory)
  end

  test "WOP-X04 a suspended owner turns an expired mutation call into unknown effect",
       context do
    {host, directory} = open_fixture(context)
    :ok = :sys.suspend(host)

    assert {:error, %Error{code: :native_process_terminated, effect: :unknown}} =
             Host.request(host, "write", write("value-1"), 50)

    assert {:error, %Error{code: :native_process_terminated, effect: :none}} =
             Host.request(host, "read", read("value-1"), 50)

    assert {:error, %Error{code: :native_process_terminated, effect: :none}} =
             Host.request(host, "close", %{}, 50)

    :ok = :sys.resume(host)
    # The expired queued close is rejected before emission; a fresh close succeeds.
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert_reaped(directory)
    handle = %Wotex.OPCUA.Browse.Continuation{pid: host, reference: make_ref(), generation: 1}

    assert {:error, %Error{code: :native_process_terminated, effect: :none}} =
             Host.browse_page(host, %{}, %{max_pages: 1, max_references: 1}, 100)

    assert {:error, %Error{code: :native_process_terminated}} =
             Host.browse_next(host, handle, 100)

    assert {:error, %Error{code: :invalid_continuation}} = Host.browse_next(host, :bad, 100)
  end

  test "WOP-X04 an expired Session activation ends the generation without owner noise",
       context do
    options = fixture_options(context, "owner_fixture")
    assert {:ok, host, _} = Host.start_link(options)
    monitor = Process.monitor(host)
    open = %{@open | "endpoint" => "opc.tcp://slow-open:4840"}

    assert {:error, %Error{code: :deadline_exceeded}} = Host.request(host, "open", open, 100)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    refute_receive {:wotex_opcua_native, ^host, _}
    assert_reaped(Path.dirname(options[:executable]))
  end

  for {mode, code} <- [
        {"session_oversized_line", :invalid_native_frame},
        {"session_unsolicited_response", :invalid_native_frame}
      ] do
    test "WOP-X03 #{mode} ends an idle generation with one owner error", context do
      {host, directory} = open_probe(context, unquote(mode))
      monitor = Process.monitor(host)
      code = unquote(code)
      assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: ^code}}}, 1000
      # The probe writes at once, so the linked host may exit before the monitor
      # exists; an abnormal exit would have ended this linked test process.
      assert_receive {:DOWN, ^monitor, :process, ^host, reason}, 1000
      assert reason in [:normal, :noproc]
      refute_receive {:wotex_opcua_native, ^host, _}
      assert_reaped(directory)
    end
  end

  test "WOP-X04 terminal or failed close answers only the close caller", context do
    for {mode, code} <- [
          {"session_terminal_close", :cleanup_failed},
          {"session_close_failure", :cleanup_failed}
        ] do
      {host, directory} = open_probe(context, mode)
      monitor = Process.monitor(host)
      assert {:error, %Error{code: ^code}} = Host.request(host, "close", %{}, 1000)
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      refute_receive {:wotex_opcua_native, ^host, _}
      assert_reaped(directory)
    end
  end

  test "WOP-X04 a cancel acknowledgement for another target ends the generation", context do
    {host, directory} = open_probe(context, "session_foreign_cancel")
    monitor = Process.monitor(host)

    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} =
             Host.request(host, "read", read("hold"), 50)

    assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: :invalid_native_frame}}},
                   1000

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_reaped(directory)
  end

  test "WOP-N03 a failed Browse page clears its chain for the next page request", context do
    {host, directory} = open_probe(context, "session_browse_failure")
    limits = %{max_pages: 1, max_references: 1}

    parameters = %{
      "node_id" => "ns=0;i=85",
      "reference_type_id" => "ns=0;i=33",
      "direction" => "forward",
      "include_subtypes" => true,
      "node_class_mask" => 0,
      "page_size" => 1
    }

    assert {:error, %Error{code: :remote_error, details: %{status: 0x80340000}}} =
             Host.browse_page(host, parameters, limits, 1000)

    assert {:ok, %{"references" => [], "continuation" => nil}} =
             Host.browse_page(host, parameters, limits, 1000)

    monitor = Process.monitor(host)
    assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_reaped(directory)
  end

  test "WOP-N03 an unowned raw Browse continuation closes the Session", context do
    {host, directory} = open_probe(context, "session_continuation")
    monitor = Process.monitor(host)

    parameters = %{
      "node_id" => "ns=0;i=85",
      "reference_type_id" => "ns=0;i=33",
      "direction" => "forward",
      "include_subtypes" => true,
      "node_class_mask" => 0,
      "page_size" => 1
    }

    assert {:error, %Error{code: :response_limit}} =
             Host.request(host, "browse", parameters, 1000)

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    assert_reaped(directory)
  end

  describe "subscriptions" do
    setup do
      handler = "wotex-opcua-bridge-#{System.unique_integer([:positive])}"
      test = self()

      :telemetry.attach_many(
        handler,
        [
          [:wotex, :opcua, :subscription, :open],
          [:wotex, :opcua, :subscription, :deliver],
          [:wotex, :opcua, :subscription, :close]
        ],
        fn event, measurements, metadata, _ ->
          send(test, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    test "WOP-S04 reports arrive in order and cancellation records the closed handle",
         context do
      {host, directory} = open_fixture(context)

      assert {:ok, %Subscription{} = subscription} =
               Host.subscribe(host, subscribe("stream-3"), self(), 1000, 1000)

      reference = subscription.reference

      for value <- 1..3 do
        expected = value * 1.0

        assert_receive {:wotex_opcua, ^reference,
                        {:ok, %{"value" => %{"value" => ^expected}},
                         %{"sequence" => ^value, "client_handle" => 1, "overflow" => false}}}

        assert_receive {:telemetry, [:wotex, :opcua, :subscription, :deliver], %{count: 1},
                        %{result: :ok}}
      end

      assert :ok = Host.unsubscribe(host, subscription, 1000)

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :close], %{count: 1},
                      %{result: :unsubscribed}}

      assert :ok = Host.unsubscribe(host, subscription, 1000)

      assert {:error, %Error{code: :invalid_subscription}} =
               Host.unsubscribe(
                 host,
                 %{subscription | generation: subscription.generation + 1},
                 1000
               )

      assert {:error, %Error{code: :invalid_subscription}} =
               Host.unsubscribe(host, %{subscription | reference: make_ref()}, 1000)

      assert {:error, %Error{code: :invalid_subscription}} = Host.unsubscribe(host, :handle, 1000)
      assert {:error, %Error{code: :invalid_value}} = Host.subscribe(host, %{}, self(), 0, 1000)

      assert {:error, %Error{code: :invalid_value}} =
               Host.subscribe(host, subscribe("unknown"), self(), 10, 1000)

      refute_receive {:wotex_opcua, ^reference, _}, 50
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert %{"subscribes" => 1, "unsubscribes" => 1, "reports" => 3} = counters(directory)
      assert_reaped(directory)
      assert :ok = Host.unsubscribe(host, subscription, 1000)
    end

    test "WOP-C05 one terminal report ends delivery and closes the handle", context do
      {host, directory} = open_fixture(context)
      assert {:ok, subscription} = Host.subscribe(host, subscribe("error-2"), self(), 1000, 1000)
      reference = subscription.reference
      assert_receive {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 1}}}
      assert_receive {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 2}}}

      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :sequence_gap, effect: :none}}}

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :close], _, %{result: :terminal}}
      assert :ok = Host.unsubscribe(host, subscription, 1000)
      refute_receive {:wotex_opcua, ^reference, _}, 50
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert %{"unsubscribes" => 0, "reports" => 3} = counters(directory)
      assert_reaped(directory)
    end

    test "WOP-C05 a full receiver queue and receiver death cancel natively", context do
      {host, directory} = open_fixture(context)

      stalled =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert {:ok, overflowed} = Host.subscribe(host, subscribe("stream-5"), stalled, 1, 1000)
      reference = overflowed.reference

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :deliver], _,
                      %{result: :overflow}}

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :close], _,
                      %{result: :receiver_overflow}}

      {:messages, messages} = Process.info(stalled, :messages)

      assert [
               {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 1}}},
               {:wotex_opcua, ^reference, {:error, %Error{code: :receiver_overflow}}}
             ] = messages

      receiver = spawn(fn -> Process.sleep(:infinity) end)
      assert {:ok, lost} = Host.subscribe(host, subscribe("stream-0"), receiver, 10, 1000)
      Process.exit(receiver, :kill)

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :close], _,
                      %{result: :receiver_down}}

      assert :ok = Host.unsubscribe(host, lost, 1000)
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert %{"subscribes" => 2, "unsubscribes" => 2} = counters(directory)
      assert_reaped(directory)
    end

    test "WOP-X04 Session loss ends each live subscription once without noise", context do
      {host, directory} = open_fixture(context)
      assert {:ok, subscription} = Host.subscribe(host, subscribe("stream-0"), self(), 10, 1000)
      reference = subscription.reference
      monitor = Process.monitor(host)

      assert {:error, %Error{code: :connection_failed}} =
               Host.request(host, "read", read("lose"), 5000)

      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000

      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :connection_failed, effect: :none}}}

      refute_receive {:wotex_opcua, ^reference, _}, 50
      assert :ok = Host.unsubscribe(host, subscription, 1000)
      refute_receive {:wotex_opcua_native, ^host, _}
      assert_reaped(directory)
    end

    test "WOP-C05 a subscription completed after its caller stopped waiting is cancelled",
         context do
      {host, directory} = open_probe(context, "session_subscription_race")

      assert {:error, %Error{code: :deadline_exceeded}} =
               Host.subscribe(host, subscribe("stream-1"), self(), 10, 50)

      assert eventually(fn -> File.exists?(Path.join(directory, "unsubscribed")) end)
      assert eventually(fn -> :sys.get_state(host).discarding == MapSet.new() end)
      refute_receive {:wotex_opcua, _, _}, 50
      refute_receive {:telemetry, [:wotex, :opcua, :subscription, :deliver], _, _}
      monitor = Process.monitor(host)
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      assert_reaped(directory)
    end

    test "WOP-X04 output and terminal control written before native exit are handled in order",
         context do
      {host, directory} = open_probe(context, "session_terminal_exit")
      assert {:ok, subscription} = Host.subscribe(host, subscribe("stream-1"), self(), 10, 1000)
      reference = subscription.reference
      monitor = Process.monitor(host)
      :ok = :sys.suspend(host)
      File.write!(Path.join(directory, "trigger"), "go")
      assert_reaped(directory)
      assert eventually(fn -> message_queue(host) >= 3 end)
      :ok = :sys.resume(host)
      assert_receive {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 1}}}, 1000

      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :receiver_overflow, effect: :none}}},
                     1000

      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      refute_receive {:wotex_opcua, ^reference, _}, 50
      refute_receive {:wotex_opcua_native, ^host, _}
    end

    test "WOP-C03 owner death ends live subscriptions and unanswered callers once", context do
      options = fixture_options(context, "owner_fixture")
      parent = self()

      owner =
        spawn(fn ->
          {:ok, host, _} = Host.start_link(options)
          {:ok, _} = Host.request(host, "open", @open, 5000)
          send(parent, {:host, host})
          Process.sleep(:infinity)
        end)

      assert_receive {:host, host}, 5000
      directory = Path.dirname(options[:executable])
      assert {:ok, subscription} = Host.subscribe(host, subscribe("stream-0"), self(), 10, 1000)
      reference = subscription.reference
      spawn(fn -> send(parent, {:write, Host.request(host, "write", write("hold"), 5000)}) end)
      assert eventually(fn -> outstanding(host) == 1 end)
      monitor = Process.monitor(host)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000

      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :native_owner_lost, effect: :none}}}

      assert_receive {:write, {:error, %Error{code: :native_owner_lost, effect: :unknown}}}
      refute_receive {:wotex_opcua, ^reference, _}, 50
      assert :ok = Host.unsubscribe(host, subscription, 1000)
      assert_reaped(directory)
    end

    test "WOP-C05 a report for an unknown subscription ends the generation", context do
      {host, directory} = open_probe(context, "session_unknown_report")
      monitor = Process.monitor(host)

      assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: :invalid_native_frame}}},
                     1000

      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      assert_reaped(directory)
    end

    test "WOP-S04 concurrent cancellation waits for the one native unsubscribe", context do
      {host, directory} = open_fixture(context)
      assert {:ok, subscription} = Host.subscribe(host, subscribe("stream-0"), self(), 10, 1000)
      :ok = :sys.suspend(host)
      tasks = for _ <- 1..2, do: Task.async(fn -> Host.unsubscribe(host, subscription, 1000) end)
      assert eventually(fn -> message_queue(host) >= 2 end)
      :ok = :sys.resume(host)
      assert [:ok, :ok] = Task.await_many(tasks)
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert %{"subscribes" => 1, "unsubscribes" => 1} = counters(directory)
      assert_reaped(directory)
    end

    test "WOP-S04 persistent facade subscribes through the owner and cancels", context do
      {host, directory} = open_fixture(context)
      assert {:ok, config} = Wotex.OPCUA.Native.Config.new(@client_options)

      handle = %{
        owner: self(),
        config: %{config | lifecycle: :persistent},
        host: host,
        namespace_array: ["http://opcfoundation.org/UA/", "urn:fixture"]
      }

      session = %Session{client: Open62541, handle: handle, timeout: 1000}

      assert {:ok, %Subscription{pid: ^host} = subscription} =
               Wotex.OPCUA.subscribe(session, %{
                 node_id: "ns=1;s=stream-1",
                 publishing_interval_ms: 25.5,
                 max_queue_length: 4
               })

      reference = subscription.reference
      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :open], _, %{result: :ok}}
      assert_receive {:wotex_opcua, ^reference, {:ok, _, %{"sequence" => 1}}}

      assert {:error, %Error{code: :invalid_node_id}} =
               Open62541.subscribe(handle, facade_request("bad"), self(), 1000)

      assert :ok = Wotex.OPCUA.unsubscribe(session, subscription)
      assert {:ok, nil} = Host.request(host, "close", %{}, 1000)
      assert %{"subscribes" => 1, "unsubscribes" => 1} = counters(directory)
      assert_reaped(directory)
    end

    test "WOP-S04 facade validates requests and one-shot handles acquire nothing" do
      assert {:ok, config} = Wotex.OPCUA.Native.Config.new(@client_options)
      oneshot = %{owner: self(), config: %{config | lifecycle: :oneshot}, host: nil}
      session = %Session{client: Wotex.OPCUA.Open62541, handle: oneshot, timeout: 1000}

      for request <- [
            %{node_id: "ns=1;s=x", queue_size: 0},
            %{node_id: "ns=1;s=x", publishing_interval_ms: 9},
            %{node_id: "ns=1;s=x", sampling_interval_ms: 60_000.5},
            %{node_id: "ns=1;s=x", keepalive_count: 10, lifetime_count: 29},
            %{node_id: "ns=1;s=x", discard_oldest: :yes},
            %{node_id: "ns=1;s=x", receiver: :self},
            %{node_id: "ns=1;s=x", max_queue_length: 10_001},
            %{node_id: "ns=1;s=x", other: 1},
            %{node_id: "bad"},
            %{},
            :request
          ] do
        assert {:error, %Error{code: :invalid_value}} = Wotex.OPCUA.subscribe(session, request)
      end

      assert {:error, %Error{code: :persistent_session_required}} =
               Wotex.OPCUA.subscribe(session, %{node_id: "ns=1;s=x", publishing_interval_ms: 25.5})

      assert_receive {:telemetry, [:wotex, :opcua, :subscription, :open], _, %{result: :error}}
      handle = %Subscription{pid: self(), reference: make_ref(), generation: 1}

      assert {:error, %Error{code: :persistent_session_required}} =
               Wotex.OPCUA.unsubscribe(session, handle)

      assert {:error, %Error{code: :invalid_subscription}} =
               Wotex.OPCUA.unsubscribe(session, :handle)

      assert {:error, %Error{code: :invalid_native_handle}} =
               Open62541.subscribe(%{}, %{}, self(), 10)

      assert {:error, %Error{code: :invalid_subscription}} = Open62541.unsubscribe(%{}, handle, 10)
      assert :not_supported = Wotex.OPCUA.subscribe(:session, %{})
      assert :not_supported = Wotex.OPCUA.unsubscribe(:session, handle)
    end
  end

  defp facade_request(node),
    do: %{
      node_id: node,
      publishing_interval_ms: 500,
      sampling_interval_ms: 250,
      queue_size: 10,
      discard_oldest: true,
      keepalive_count: 10,
      lifetime_count: 30,
      max_queue_length: 4
    }

  defp subscribe(name),
    do: %{
      "node_id" => "ns=1;s=#{name}",
      "publishing_interval_ms" => 500,
      "sampling_interval_ms" => 250,
      "queue_size" => 10,
      "discard_oldest" => true,
      "keepalive_count" => 10,
      "lifetime_count" => 30
    }

  defp receive_connected do
    receive do
      {:connected, {:ok, _}} -> true
    after
      50 -> false
    end
  end

  defp parameters("read"), do: read("hold")
  defp parameters("write"), do: write("hold")

  defp read(name), do: %{"node_id" => "ns=1;s=#{name}", "index_range" => nil}

  defp write(name),
    do: %{
      "node_id" => "ns=1;s=#{name}",
      "index_range" => nil,
      "value" => %{"type" => "Double", "array" => false, "value" => 1.0}
    }

  defp call(name),
    do: %{"object_id" => "ns=1;s=#{name}", "method_id" => "ns=1;s=method", "arguments" => []}

  defp open_fixture(context) do
    options = fixture_options(context, "owner_fixture")
    assert {:ok, host, _} = Host.start_link(options)
    assert {:ok, %{"namespace_array" => [_, _]}} = Host.request(host, "open", @open, 5000)
    {host, Path.dirname(options[:executable])}
  end

  defp open_probe(context, mode) do
    options = fixture_options(context, "probe", mode)
    assert {:ok, host, _} = Host.start_link(options)
    assert {:ok, _} = Host.request(host, "open", @open, 5000)
    {host, Path.dirname(options[:executable])}
  end

  defp fixture_options(context, source, name \\ nil) do
    name = name || source
    directory = Path.join(context.directory, "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir!(directory)
    executable = Path.join(directory, name)
    File.ln!(Path.join(context.directory, source), executable)
    guardian = Path.join(context.directory, "guardian")

    [
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      timeout: 5000
    ]
  end

  defp outstanding(host),
    do: Enum.count(:sys.get_state(host).pending, fn {_, entry} -> not entry.replied end)

  defp message_queue(host) do
    {:message_queue_len, length} = Process.info(host, :message_queue_len)
    length
  end

  defp counters(directory) do
    path = Path.join(directory, "owner-fixture.json")
    assert eventually(fn -> File.exists?(path) end)
    Jason.decode!(File.read!(path))
  end

  defp assert_reaped(directory) do
    file = Path.join(directory, "host.pid")
    assert File.regular?(file)
    pids = String.split(File.read!(file))

    assert eventually(fn ->
             Enum.all?(pids, fn pid ->
               {_, status} =
                 System.cmd("/bin/kill", ["-0", pid],
                   stderr_to_stdout: true,
                   env: [{"LC_ALL", "C"}]
                 )

               status != 0
             end)
           end)
  end

  defp eventually(check, attempts \\ 400)
  defp eventually(_, 0), do: false

  defp eventually(check, attempts) do
    if check.() do
      true
    else
      Process.sleep(5)
      eventually(check, attempts - 1)
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
