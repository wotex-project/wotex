defmodule Wotex.OPCUA.PersistentBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Host

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
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
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
