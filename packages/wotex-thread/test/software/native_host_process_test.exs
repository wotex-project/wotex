defmodule Wotex.Thread.NativeHostProcessTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :software
  @moduletag requirements: ["WTH-S03", "WTH-C03", "WTH-C07", "WTH-B03"], vectors: ["WTH-V04"]
  @revision "5c8c318627954c99cd1a957a290bbd4b1027d04b"
  @generation "0123456789abcdef0123456789abcdef"

  setup do
    assert match?({:unix, :linux}, :os.type())
    host = System.fetch_env!("WOTEX_THREAD_HOST")
    rcp = System.fetch_env!("WOTEX_THREAD_RCP")
    assert Path.type(host) == :absolute and File.regular?(host)
    assert Path.type(rcp) == :absolute and File.regular?(rcp)

    root =
      Path.join(
        System.tmp_dir!(),
        "wth-process-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{host: host, rcp: rcp, root: root, node: :counters.new(1, [])}
  end

  test "WTH-S03 WTH-V04 real SDK store is private, preserved across close and reopened", context do
    config = config(context)
    host = start(context)
    assert %{"ok" => true, "result" => state} = call(host, "open", config)

    assert state == %{
             "role" => "disabled",
             "network_name" => "OpenThread",
             "rloc16" => nil,
             "ipv6_enabled" => false,
             "thread_enabled" => false,
             "generation" => 1
           }

    assert length(descendants(host.os_pid)) >= 2
    assert %{"ok" => true, "result" => ^state} = call(host, "inspect")
    assert %{"ok" => true, "result" => version} = call(host, "version")
    assert version =~ @revision
    store = config["storage_path"]
    before = store_contents(store)
    assert Map.has_key?(before, "settings.data")

    for entry <- File.ls!(store),
        do: assert(File.stat!(Path.join(store, entry)).mode |> Bitwise.band(0o777) == 0o600)

    assert %{"ok" => true, "result" => nil} = call(host, "close")
    assert finish(host) == 0
    refute interface?(config["interface"])
    assert store_contents(store) == before
    reopened = start(context)
    assert %{"ok" => true} = call(reopened, "open", %{config | "storage_mode" => "open_existing"})
    assert %{"ok" => true, "result" => nil} = call(reopened, "close")
    assert finish(reopened) == 0
  end

  test "WTH-S03 WTH-V04 competing store and interface owners fail without disturbing the first",
       context do
    config = config(context)
    first = start(context)
    assert %{"ok" => true, "result" => state} = call(first, "open", config)

    for {changes, code} <- [
          {%{"interface" => "wthother", "storage_mode" => "open_existing"}, "storage_unavailable"},
          {%{"storage_path" => Path.join(context.root, "other")}, "interface_in_use"}
        ] do
      other = start(context)

      assert %{"ok" => false, "error" => %{"code" => ^code}} =
               call(other, "open", Map.merge(config, changes))

      assert descendants(other.os_pid) |> length() == 1
      assert close_input(other)
      assert %{"ok" => true, "result" => ^state} = call(first, "inspect")
    end

    assert close_input(first)
    refute interface?(config["interface"])
  end

  test "WTH-C07 invalid configuration acquires no store and unopened operations fail typed",
       context do
    host = start(context)

    for changes <- [
          %{"radio_url" => "spinel+hdlc+forkpty:///?forkpty-arg=1"},
          %{"radio_url" => "spinel+hdlc+uart:///tmp/radio#fragment"},
          %{"interface" => "bad/name"},
          %{"storage_path" => "/"},
          %{"storage_path" => "/tmp/secret\nvalue"},
          %{"allow_network_creation" => 1},
          %{"storage_mode" => "default"},
          %{"extra" => "canary"}
        ] do
      assert %{"ok" => false, "error" => %{"code" => "invalid_request"}} =
               call(host, "open", Map.merge(config(context), changes))
    end

    assert File.ls!(context.root) == []
    assert %{"ok" => false, "error" => %{"code" => "not_open"}} = call(host, "inspect")
    assert %{"ok" => false, "error" => %{"code" => "not_supported"}} = call(host, "unrecognized")
    assert close_input(host)
  end

  test "WTH-S03 linked, shared, permissive or directory settings entries are refused unchanged",
       context do
    for filename <- ["settings.data", "settings.Swap"],
        kind <- [:symlink, :hardlink, :permissions, :directory] do
      config = %{config(context) | "storage_mode" => "open_existing"}
      store = config["storage_path"]
      File.mkdir!(store)
      File.chmod!(store, 0o700)
      outside = Path.join(context.root, "outside-#{filename}-#{kind}")
      File.write!(outside, "canary")
      File.chmod!(outside, 0o600)
      entry = Path.join(store, filename)

      case kind do
        :symlink ->
          File.ln_s!(outside, entry)

        :hardlink ->
          File.ln!(outside, entry)

        :permissions ->
          File.write!(entry, "canary")
          File.chmod!(entry, 0o644)

        :directory ->
          File.mkdir!(entry)
      end

      host = start(context)

      assert %{"ok" => false, "error" => %{"code" => "storage_unavailable"}} =
               call(host, "open", config)

      assert File.read!(outside) == "canary"
      assert length(descendants(host.os_pid)) == 1
      assert close_input(host)
    end
  end

  test "WTH-B03 WTH-C07 every request split, coalesced frames and stderr noise keep exact replies",
       context do
    host = start(context)
    request = frame("split", "inspect", %{})

    for offset <- 1..(byte_size(request) - 1) do
      id = "split-#{offset}"
      bytes = frame(id, "inspect", %{})
      split = min(offset, byte_size(bytes) - 1)
      <<head::binary-size(split), tail::binary>> = bytes
      assert Port.command(host.port, head)
      refute_receive {_, {:data, _}}, 1
      assert Port.command(host.port, tail)
      assert %{"id" => ^id, "ok" => false, "error" => %{"code" => "not_open"}} = receive_frame(host)
    end

    assert Port.command(
             host.port,
             frame("first", "inspect", %{}) <> frame("second", "version", %{})
           )

    assert %{"id" => "first", "ok" => false} = receive_frame(host)
    assert %{"id" => "second", "ok" => false} = receive_frame(host)

    noisy = config(context, stubborn_radio(context), "noisy")
    assert Port.command(host.port, frame("noisy", "open", noisy))
    eventually(fn -> length(descendants(host.os_pid)) >= 2 end)
    # The radio writes 300000 canary bytes to its own standard error; none reach the frame channel.
    refute_receive {_, {:data, _}}, 200
    pids = [host.os_pid | descendants(host.os_pid)]
    Port.close(host.port)
    eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end, 1_500)
  end

  test "WTH-C07 truncated EOF, duplicate keys and oversized lines terminate the owned process",
       context do
    host = start(context)
    assert Port.command(host.port, ~s({"version":))
    Process.sleep(20)
    assert close_input(host)

    for payload <- [
          ~s({"version":1,"version":1}\n),
          :binary.copy("x", 131_073) <> "\n",
          frame("before-flow", "inspect", %{})
        ] do
      host = start(context, flow: false)
      unless payload =~ "before-flow", do: send_flow(host)
      assert Port.command(host.port, payload)
      assert finish(host) != 0
    end
  end

  test "WTH-S03 WTH-V04 worker or radio death releases the interface, descendants and store lock",
       context do
    for target <- [:worker, :radio] do
      config = config(context)
      host = start(context)
      assert %{"ok" => true} = call(host, "open", config)
      [worker | _] = children(host.os_pid)
      [radio | _] = descendants(worker)
      pids = [host.os_pid, worker, radio]

      System.cmd("/bin/kill", [
        "-KILL",
        Integer.to_string(if(target == :worker, do: worker, else: radio))
      ])

      assert finish(host) != 0
      eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end)
      refute interface?(config["interface"])
      assert_store_released(context, config)
    end
  end

  test "WTH-C07 blocked SDK startup is reaped after owner EOF or SIGTERM", context do
    radio = stubborn_radio(context)

    for method <- [:eof, :term] do
      config = config(context, radio)
      host = start(context)
      assert Port.command(host.port, frame("blocked", "open", config))
      eventually(fn -> length(descendants(host.os_pid)) >= 2 end)
      pids = [host.os_pid | descendants(host.os_pid)]

      case method do
        :eof ->
          Port.close(host.port)

        :term ->
          System.cmd("/bin/kill", ["-TERM", Integer.to_string(host.os_pid)])
          assert_receive {port, {:exit_status, _}} when port == host.port, 2_000
      end

      eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end, 1_500)
      assert_store_released(context, config)
    end
  end

  test "WTH-C07 a full input pipe during blocked startup cannot hide owner EOF", context do
    host = start(context)

    assert Port.command(
             host.port,
             frame("blocked", "open", config(context, stubborn_radio(context), "noisy"))
           )

    eventually(fn -> length(descendants(host.os_pid)) >= 2 end)
    pids = [host.os_pid | descendants(host.os_pid)]
    queued = frame("queued", "inspect", %{})
    # Port.command queues without blocking this process; the host must not need to drain it.
    for _ <- 1..4_000, do: Port.command(host.port, queued, [:nosuspend])
    Port.close(host.port)
    eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end, 1_500)
  end

  # Each sanitizer-host cycle acquires a real SDK and RCP; the bound covers 100 cycles.
  @tag timeout: 300_000
  test "WTH-S03 WTH-V04 one hundred owned SDK cycles restore processes and interfaces", context do
    original = interfaces()

    for cycle <- 1..100 do
      config = config(context)
      host = start(context)
      assert %{"ok" => true} = call(host, "open", config), "cycle #{cycle}"
      pids = [host.os_pid | descendants(host.os_pid)]
      assert %{"ok" => true, "result" => nil} = call(host, "close")
      assert finish(host) == 0
      eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end)
    end

    assert interfaces() == original
  end

  defp start(context, options \\ []) do
    port =
      Port.open({:spawn_executable, context.host}, [
        :binary,
        :exit_status,
        args: [],
        env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    host = %{port: port, os_pid: os_pid, buffer: make_ref()}
    Process.put(host.buffer, <<>>)

    assert receive_frame(host) == %{
             "version" => 1,
             "event" => "ready",
             "backend" => "openthread",
             "revision" => @revision
           }

    if Keyword.get(options, :flow, true), do: send_flow(host)
    host
  end

  defp send_flow(host) do
    assert Port.command(
             host.port,
             Jason.encode!(%{version: 1, event: "flow_open", session_generation: @generation}) <>
               "\n"
           )
  end

  defp frame(id, operation, parameters) do
    Jason.encode!(%{
      version: 1,
      id: id,
      operation: operation,
      parameters: parameters,
      timeout_ms: 5000
    }) <>
      "\n"
  end

  defp call(host, operation, parameters \\ %{}) do
    id = "request-#{System.unique_integer([:positive])}"
    assert Port.command(host.port, frame(id, operation, parameters))
    assert %{"id" => ^id} = response = receive_frame(host)
    response
  end

  defp receive_frame(host) do
    buffer = Process.get(host.buffer)

    case :binary.split(buffer, "\n") do
      [line, rest] ->
        Process.put(host.buffer, rest)
        Jason.decode!(line)

      [_] ->
        port = host.port

        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 131_072 ->
            Process.put(host.buffer, buffer <> bytes)
            receive_frame(host)
        after
          10_000 -> flunk("native host did not complete a frame")
        end
    end
  end

  defp finish(host) do
    port = host.port

    receive do
      {^port, {:exit_status, status}} -> status
    after
      2_000 ->
        Port.close(port)
        flunk("native host did not exit")
    end
  end

  defp close_input(host) do
    pids = [host.os_pid | descendants(host.os_pid)]
    Port.close(host.port)
    eventually(fn -> Enum.all?(pids, &(not alive?(&1))) end)
    true
  end

  defp config(context, radio \\ nil, argument \\ nil) do
    :counters.add(context.node, 1, 1)
    node = :counters.get(context.node, 1)
    radio = radio || context.rcp
    argument = argument || Integer.to_string(rem(node, 30) + 1)

    %{
      "radio_url" => "spinel+hdlc+forkpty://#{radio}?forkpty-arg=#{argument}",
      "interface" => "wthp#{node}",
      "storage_path" => Path.join(context.root, "store#{node}"),
      "storage_mode" => "create_new",
      "allow_network_creation" => false
    }
  end

  defp stubborn_radio(context) do
    path = Path.join(context.root, "stubborn-radio")

    unless File.exists?(path) do
      source = Path.expand("../fixtures/stubborn_radio.c", __DIR__)

      assert {_, 0} =
               System.cmd("/usr/bin/cc", [
                 "-std=c11",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 source,
                 "-o",
                 path
               ])
    end

    path
  end

  defp assert_store_released(context, config) do
    host = start(context)

    assert %{"ok" => true} =
             call(host, "open", %{
               config
               | "storage_mode" => "open_existing",
                 "radio_url" => radio_url(context)
             })

    assert %{"ok" => true, "result" => nil} = call(host, "close")
    assert finish(host) == 0
  end

  defp radio_url(context), do: "spinel+hdlc+forkpty://#{context.rcp}?forkpty-arg=31"

  defp store_contents(store) do
    for entry <- File.ls!(store),
        entry != ".wotex-lock",
        into: %{},
        do: {entry, File.read!(Path.join(store, entry))}
  end

  defp children(pid) do
    case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, text} -> text |> String.split() |> Enum.map(&String.to_integer/1)
      {:error, _} -> []
    end
  end

  defp descendants(pid) do
    direct = children(pid)
    direct ++ Enum.flat_map(direct, &descendants/1)
  end

  defp alive?(pid), do: File.exists?("/proc/#{pid}")
  defp interfaces, do: File.ls!("/sys/class/net") |> Enum.sort()
  defp interface?(name), do: File.exists?("/sys/class/net/#{name}")

  defp eventually(condition, timeout \\ 1_000),
    do: eventually(condition, System.monotonic_time(:millisecond) + timeout, :loop)

  defp retry(condition, deadline) do
    Process.sleep(5)
    eventually(condition, deadline, :loop)
  end

  defp eventually(condition, deadline, :loop) do
    cond do
      condition.() -> :ok
      System.monotonic_time(:millisecond) < deadline -> retry(condition, deadline)
      true -> flunk("bounded condition did not complete")
    end
  end
end
