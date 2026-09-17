defmodule Wotex.OPCUA.NativeLifecycleInteropTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.Host
  @moduletag :interop

  setup do
    fixture = System.fetch_env!("WOTEX_OPCUA_INTEROP_CONFIG") |> Path.dirname()
    peer = System.fetch_env!("WOTEX_OPCUA_PAGED_PEER")
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port_number}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)

    port =
      Port.open({:spawn_executable, peer}, [
        :binary,
        :exit_status,
        {:line, 4096},
        {:args, [Integer.to_string(port_number), fixture]}
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    await_ready(port, System.monotonic_time(:millisecond) + 5000)

    open =
      fixture
      |> Path.join("native-open.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("endpoint", "opc.tcp://127.0.0.1:#{port_number}")

    %{peer: port, open: open}
  end

  test "WOP-S02 close deletes the server Session before its timeout", context do
    host = start_host()
    open = Map.put(context.open, "session_timeout_ms", 60_000)
    assert {:ok, _} = Host.request(host, "open", open, 5000)
    assert %{sessions: 1, channels: 1} = counters(context.peer)
    monitor = Process.monitor(host)
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000

    assert eventually(fn -> match?(%{sessions: 0, channels: 0}, counters(context.peer)) end, 500)
    assert %{timeouts: 0} = counters(context.peer)
  end

  test "WOP-V05 owner death during each open phase releases the native process and channel",
       context do
    open = Map.put(context.open, "session_timeout_ms", 1000)
    measured = start_host()
    began = System.monotonic_time(:millisecond)
    assert {:ok, _} = Host.request(measured, "open", open, 5000)
    duration = System.monotonic_time(:millisecond) - began
    assert {:ok, nil} = Host.request(measured, "close", %{}, 5000)
    assert eventually(fn -> match?(%{sessions: 0, channels: 0}, counters(context.peer)) end, 500)
    before = counters(context.peer)

    # Fractions of one measured activation cover channel, CreateSession,
    # ActivateSession and NamespaceArray phases; :active kills after success.
    delays = Enum.map([0, 1, 2, 4, 6, 7, 8], &if(&1 == 8, do: :active, else: div(duration * &1, 8)))

    for delay <- delays do
      parent = self()

      owner =
        spawn(fn ->
          {:ok, host, _} = start_host_link()
          {:os_pid, guardian} = Port.info(:sys.get_state(host).port, :os_pid)
          send(parent, {:started, host, guardian})
          send(parent, {:opened, Host.request(host, "open", open, 5000)})
        end)

      assert_receive {:started, host, guardian}, 5000

      if delay == :active,
        do: assert_receive({:opened, {:ok, _}}, 5000),
        else: Process.sleep(delay)

      monitor = Process.monitor(host)
      killed = System.monotonic_time(:millisecond)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 1000
      assert eventually(fn -> not os_alive?(guardian) end, 1000)
      assert System.monotonic_time(:millisecond) - killed <= 1000

      # Local release closes the channel; a Session that was already created
      # is removed by cooperative close or by the server after its timeout.
      assert eventually(fn -> match?(%{channels: 0}, counters(context.peer)) end, 1000)
      assert eventually(fn -> match?(%{sessions: 0}, counters(context.peer)) end, 5000)
    end

    after_kills = counters(context.peer)
    assert after_kills.cumulated > before.cumulated
    assert after_kills.timeouts + after_kills.aborts <= after_kills.cumulated
  end

  test "WOP-X04 an active Session survives an idle request timeout and closes cleanly", context do
    host = start_host()
    open = Map.put(context.open, "session_timeout_ms", 60_000)
    assert {:ok, %{"namespace_array" => namespaces}} = Host.request(host, "open", open, 5000)
    namespace = Enum.find_index(namespaces, &(&1 == "urn:wotex:fixture"))
    node = "ns=#{namespace};s=child1"

    assert {:ok, %{"value" => %{"type" => "Int32", "value" => 1}}} =
             Host.request(host, "read", %{"node_id" => node, "index_range" => nil}, 5000)

    assert {:error, %Error{code: :invalid_value}} =
             Host.request(host, "read", %{"node_id" => "ns=99;s=x", "index_range" => nil}, 5000)

    assert {:ok, %{"value" => %{"value" => 1}}} =
             Host.request(host, "health", %{"node_id" => node, "index_range" => nil}, 5000)

    assert %{sessions: 1} = counters(context.peer)
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
    assert eventually(fn -> match?(%{sessions: 0, channels: 0}, counters(context.peer)) end, 500)
  end

  test "WOP-S04 a same-stack queue overflow reaches report metadata", context do
    host = start_host()

    assert {:ok, %{"namespace_array" => namespaces}} =
             Host.request(host, "open", context.open, 5000)

    namespace = Enum.find_index(namespaces, &(&1 == "urn:wotex:fixture"))

    parameters = %{
      "node_id" => "ns=#{namespace};s=burst",
      "publishing_interval_ms" => 500,
      "sampling_interval_ms" => 0,
      "queue_size" => 2,
      "discard_oldest" => true,
      "keepalive_count" => 10,
      "lifetime_count" => 30
    }

    assert {:ok, subscription} = Host.subscribe(host, parameters, self(), 1000, 5000)
    reference = subscription.reference
    assert_receive {:wotex_opcua, ^reference, {:ok, _, %{"overflow" => false}}}, 5000
    true = Port.command(context.peer, "b")
    port = context.peer
    assert_receive {^port, {:data, {:eol, "BURST 5.0 Good"}}}, 2000

    assert_receive {:wotex_opcua, ^reference,
                    {:ok, %{"value" => %{"value" => 4.0}, "status" => 0x480},
                     %{"overflow" => true, "sequence" => sequence, "client_handle" => handle}}},
                   5000

    assert_receive {:wotex_opcua, ^reference,
                    {:ok, %{"value" => %{"value" => 5.0}, "status" => 0},
                     %{"overflow" => false, "sequence" => ^sequence, "client_handle" => ^handle}}},
                   5000

    refute_receive {:wotex_opcua, ^reference, _}, 700
    assert :ok = Host.unsubscribe(host, subscription, 5000)
    assert {:ok, nil} = Host.request(host, "close", %{}, 5000)
    assert eventually(fn -> match?(%{sessions: 0, channels: 0}, counters(context.peer)) end, 500)
  end

  defp start_host do
    {:ok, host, _} = start_host_link()
    host
  end

  defp start_host_link do
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    Host.start_link(
      executable: executable,
      executable_digest: digest(executable),
      guardian: guardian,
      guardian_digest: digest(guardian),
      timeout: 5000
    )
  end

  defp counters(port) do
    true = Port.command(port, "s")

    receive do
      {^port, {:data, {:eol, "COUNTERS " <> values}}} ->
        [sessions, cumulated, timeouts, aborts, channels] =
          Enum.map(String.split(values), &String.to_integer/1)

        %{
          sessions: sessions,
          cumulated: cumulated,
          timeouts: timeouts,
          aborts: aborts,
          channels: channels
        }
    after
      2000 -> flunk("peer counters unavailable")
    end
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

  defp await_ready(port, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, {:eol, "READY " <> _}}} -> :ok
      {^port, {:data, _}} -> await_ready(port, deadline)
      {^port, {:exit_status, status}} -> flunk("peer exited before READY: #{status}")
    after
      timeout -> flunk("peer did not become ready")
    end
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
