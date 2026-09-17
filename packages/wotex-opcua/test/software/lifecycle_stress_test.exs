defmodule Wotex.OPCUA.LifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session}
  alias Wotex.OPCUA.Native.Host
  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 600_000

  setup_all do
    config = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG")
    peer = Jason.decode!(File.read!(config))
    directory = Path.dirname(config)
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    options = [
      client: Open62541,
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      endpoint: peer["endpoint"],
      security_policy: :basic256sha256,
      security_mode: :sign_and_encrypt,
      client_uri: peer["client_uri"],
      server_uri: peer["server_uri"],
      certificate: peer["certificate"],
      private_key: Path.join(directory, "client.key.der"),
      server_certificate: peer["server_certificate"],
      trust_certificate: Path.join(directory, "ca.der"),
      crl: peer["crl"],
      authentication: %{type: :anonymous}
    ]

    %{peer: peer, options: options, directory: directory, guardian: guardian}
  end

  test "WOP-C09 2000 sequential operations and 32 concurrent callers keep bounded resources",
       context do
    %{peer: peer, options: options} = context
    assert {:ok, session} = Wotex.OPCUA.connect(options)
    %Session{handle: %{host: host}} = session
    processes = native_processes(host)
    read = %{type: :read, node_id: peer["node_id"]}
    assert {:ok, _} = Wotex.OPCUA.send(session, read)
    initial = footprint(host, processes)

    # The first 1000 operations warm allocator caches; the second 1000 must not
    # grow the native process or host heap beyond a fixed allowance.
    batch = fn ->
      for index <- 1..1000 do
        message =
          if rem(index, 10) == 0,
            do: call(peer, index * 1.0, 0.5),
            else: read

        assert {:ok, _} = Wotex.OPCUA.send(session, message)
      end
    end

    batch.()
    before = footprint(host, processes)
    batch.()

    parent = self()

    tasks =
      for caller <- 1..32 do
        Task.async(fn ->
          for round <- 1..16 do
            left = caller * 1000.0
            right = round * 1.0
            expected = left + right

            assert {:ok, %{"outputs" => [%{"value" => ^expected}]}} =
                     Wotex.OPCUA.send(session, call(peer, left, right))
          end

          send(parent, {:caller_done, caller})
        end)
      end

    Task.await_many(tasks, 120_000)
    for caller <- 1..32, do: assert_received({:caller_done, ^caller})

    # Forced deadlines are request-scoped; the Session keeps serving later work.
    forced = %Session{session | timeout: 1}
    deadlines = for _ <- 1..50, do: Wotex.OPCUA.send(forced, read)

    assert Enum.all?(
             deadlines,
             fn
               {:ok, _} -> true
               {:error, %Error{code: code}} -> code in [:deadline_exceeded, :busy]
               _ -> false
             end
           )

    assert eventually(
             fn ->
               state = :sys.get_state(host)
               map_size(state.pending) == 0 and map_size(state.controls) == 0
             end,
             5000
           )

    assert {:ok, _} = Wotex.OPCUA.send(session, read)

    after_work = footprint(host, processes)
    assert after_work.host_memory - before.host_memory < 1_048_576
    assert after_work.native_rss_kb - before.native_rss_kb < 16_384
    assert map_size(:sys.get_state(host).controls) == 0

    monitor = Process.monitor(host)
    assert :ok = Wotex.OPCUA.disconnect(session)
    assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
    assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)

    :io.format(
      "~ts~n",
      [
        "stress operations: host memory #{initial.host_memory}/#{before.host_memory}->" <>
          "#{after_work.host_memory} bytes, native rss #{initial.native_rss_kb}/" <>
          "#{before.native_rss_kb}->#{after_work.native_rss_kb} KiB, " <>
          "deadline or busy errors #{Enum.count(deadlines, &match?({:error, _}, &1))}/50"
      ]
    )
  end

  test "WOP-C09 100 open/close cycles release every native process", context do
    ports = length(Port.list())
    processes = length(Process.list())

    for _ <- 1..100 do
      assert {:ok, session} = Wotex.OPCUA.connect(context.options)
      %Session{handle: %{host: host}} = session
      native = native_processes(host)
      assert {:ok, _} = Wotex.OPCUA.send(session, %{type: :read, node_id: context.peer["node_id"]})
      monitor = Process.monitor(host)
      assert :ok = Wotex.OPCUA.disconnect(session)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
      assert eventually(fn -> not Enum.any?(native, &os_alive?/1) end, 1000)
    end

    assert eventually(fn -> length(Port.list()) <= ports end, 1000)
    assert eventually(fn -> length(Process.list()) <= processes + 5 end, 1000)
    assert {0, 0} = resources(context)
  end

  test "WOP-C09 100 receiver-death cycles return peer subscriptions to zero", context do
    %{peer: peer, options: options} = context
    assert {:ok, session} = Wotex.OPCUA.connect(options)
    %Session{handle: %{host: host}} = session

    for _ <- 1..100 do
      receiver = spawn(fn -> Process.sleep(:infinity) end)
      request = %{node_id: peer["node_id"], receiver: receiver, publishing_interval_ms: 50}
      assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
      Process.exit(receiver, :kill)

      assert eventually(
               fn ->
                 not Map.has_key?(:sys.get_state(host).subscriptions, subscription.reference)
               end,
               2000
             )
    end

    assert eventually(fn -> map_size(:sys.get_state(host).controls) == 0 end, 2000)
    assert {0, 0} = resources(context)
    assert {:ok, _} = Wotex.OPCUA.send(session, %{type: :read, node_id: peer["node_id"]})
    assert :ok = Wotex.OPCUA.disconnect(session)
  end

  test "WOP-C09 100 malformed native replies end each generation once", context do
    directory = Path.join(context.directory, "stress-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    compiler = System.find_executable("cc") || flunk("the stress lane requires a C11 compiler")
    probe = Path.join(directory, "probe")
    root = Path.expand("../..", __DIR__)

    {diagnostic, status} =
      System.cmd(
        compiler,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Werror",
          Path.join(root, "test/native/host_probe.c"),
          "-o",
          probe
        ],
        stderr_to_stdout: true,
        env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
      )

    assert status == 0, diagnostic
    assert {_, 40} = System.cmd(probe, ["--warm"], env: [{"LC_ALL", "C"}])

    for cycle <- 1..100 do
      cycle_directory = Path.join(directory, "cycle-#{cycle}")
      File.mkdir!(cycle_directory)
      executable = Path.join(cycle_directory, "session_unsolicited_response")
      File.ln!(probe, executable)

      assert {:ok, host, _} =
               Host.start_link(
                 executable: executable,
                 executable_digest: digest(executable),
                 guardian: context.guardian,
                 guardian_digest: digest(context.guardian),
                 timeout: 5000
               )

      monitor = Process.monitor(host)
      result = Host.request(host, "open", open(), 5000)

      assert match?({:ok, _}, result) or
               match?({:error, %Error{code: :invalid_native_frame}}, result)

      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000

      assert_receive {:wotex_opcua_native, ^host, {:error, %Error{code: :invalid_native_frame}}},
                     1000

      refute_received {:wotex_opcua_native, ^host, _}
      [pid, parent] = String.split(File.read!(Path.join(cycle_directory, "host.pid")))

      assert eventually(
               fn ->
                 not os_alive?(String.to_integer(pid)) and not os_alive?(String.to_integer(parent))
               end,
               1000
             )
    end
  end

  defp open do
    bytes = %{"type" => "bytes", "base64" => "AQ=="}

    %{
      "endpoint" => "opc.tcp://127.0.0.1:4840",
      "security_policy" => "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
      "security_mode" => "SignAndEncrypt",
      "client_uri" => "urn:client",
      "server_uri" => "urn:server",
      "certificate" => bytes,
      "private_key" => bytes,
      "server_certificate" => bytes,
      "trust_certificate" => bytes,
      "crl" => bytes,
      "authentication" => %{"type" => "anonymous"},
      "session_timeout_ms" => 60_000
    }
  end

  defp call(peer, left, right),
    do: %{
      type: :call,
      node_id: peer["method_id"],
      value: %{
        object_id: peer["object_id"],
        arguments: [%{type: "Double", value: left}, %{type: "Double", value: right}]
      }
    }

  defp resources(context) do
    {:ok, session} = Wotex.OPCUA.connect(context.options)

    {:ok, %{"outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
      Wotex.OPCUA.send(session, %{
        type: :call,
        node_id: context.peer["resources_method_id"],
        value: %{object_id: context.peer["object_id"], arguments: []}
      })

    :ok = Wotex.OPCUA.disconnect(session)
    {subscriptions, items}
  end

  defp footprint(host, processes) do
    :erlang.garbage_collect(host)
    {:memory, memory} = Process.info(host, :memory)
    %{host_memory: memory, native_rss_kb: Enum.sum(Enum.map(processes, &rss/1))}
  end

  defp rss(pid) do
    case System.cmd("/bin/ps", ["-o", "rss=", "-p", Integer.to_string(pid)],
           stderr_to_stdout: true,
           env: [{"LC_ALL", "C"}]
         ) do
      {output, 0} -> String.to_integer(String.trim(output))
      _ -> 0
    end
  end

  defp native_processes(host) do
    %{port: port} = :sys.get_state(host)
    {:os_pid, guardian} = Port.info(port, :os_pid)

    {children, 0} =
      System.cmd("/usr/bin/pgrep", ["-P", Integer.to_string(guardian)], env: [{"LC_ALL", "C"}])

    [guardian | Enum.map(String.split(children), &String.to_integer/1)]
  end

  defp os_alive?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )

    status == 0
  end

  defp eventually(check, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    poll(check, deadline)
  end

  defp poll(check, deadline) do
    cond do
      check.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        poll(check, deadline)
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
