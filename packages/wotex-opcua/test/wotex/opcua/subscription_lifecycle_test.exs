defmodule Wotex.OPCUA.SubscriptionLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{Error, Open62541, Session}
  alias Wotex.OPCUA.Native.Host
  @moduletag :interop

  setup do
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

    %{peer: peer, options: options, directory: directory}
  end

  test "WOP-C03 owner death with live subscriptions releases local and peer resources",
       context do
    %{peer: peer, options: options} = context
    parent = self()

    owner =
      spawn(fn ->
        {:ok, session} = Wotex.OPCUA.connect(options)

        subscriptions =
          for node <- [peer["node_id"], peer["byte_node_id"]] do
            request = %{node_id: node, receiver: parent, publishing_interval_ms: 50}
            {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
            subscription
          end

        send(parent, {:ready, session, subscriptions})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:ready, %Session{handle: %{host: host}}, subscriptions}, 10_000

    for %{reference: reference} <- subscriptions,
        do: assert_receive({:wotex_opcua, ^reference, {:ok, _, _}}, 5000)

    assert {:ok, observer} = Wotex.OPCUA.connect(options)
    assert {2, 2} = resources(observer, peer)
    processes = native_processes(host)
    monitor = Process.monitor(host)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 100
    assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)
    assert eventually(fn -> resources(observer, peer) == {0, 0} end, 1000)

    for %{reference: reference} = subscription <- subscriptions do
      assert_receive {:wotex_opcua, ^reference,
                      {:error, %Error{code: :native_owner_lost, effect: :none}}}

      refute_receive {:wotex_opcua, ^reference, {:error, _}}, 50
      assert :ok = Wotex.OPCUA.Native.Host.unsubscribe(host, subscription, 1000)
    end

    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  test "WOP-S04 a failed server delete closes the Session and ends every subscription once",
       context do
    %{peer: peer, options: options} = context
    assert {:ok, session} = Wotex.OPCUA.connect(options)
    %Session{handle: %{host: host}} = session

    [first, second] =
      for node <- [peer["node_id"], peer["byte_node_id"]] do
        request = %{node_id: node, publishing_interval_ms: 50}
        assert {:ok, subscription} = Wotex.OPCUA.subscribe(session, request)
        reference = subscription.reference
        assert_receive {:wotex_opcua, ^reference, {:ok, _, _}}, 5000
        subscription
      end

    assert {:ok, observer} = Wotex.OPCUA.connect(options)

    assert {:ok, %{"outputs" => [%{"value" => 1}]}} =
             call(observer, peer["delete_method_id"], [uint32(1)])

    monitor = Process.monitor(host)

    assert {:error, %Error{code: :cleanup_failed, effect: :none}} =
             Wotex.OPCUA.unsubscribe(session, first)

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
    reference = second.reference

    assert_receive {:wotex_opcua, ^reference,
                    {:error, %Error{code: :cleanup_failed, effect: :none}}}

    refute_receive {:wotex_opcua, _, {:error, _}}, 100
    assert eventually(fn -> resources(observer, peer) == {0, 0} end, 1000)
    assert :ok = Wotex.OPCUA.unsubscribe(session, first)
    assert :ok = Wotex.OPCUA.unsubscribe(session, second)
    assert :ok = Wotex.OPCUA.disconnect(observer)
  end

  describe "same-stack peer" do
    setup context do
      peer = System.fetch_env!("WOTEX_OPCUA_PAGED_PEER")
      {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
      {:ok, {{127, 0, 0, 1}, port_number}} = :inet.sockname(socket)
      :ok = :gen_tcp.close(socket)

      port =
        Port.open({:spawn_executable, peer}, [
          :binary,
          :exit_status,
          {:line, 4096},
          {:args, [Integer.to_string(port_number), context.directory]}
        ])

      on_exit(fn ->
        try do
          Port.close(port)
        rescue
          ArgumentError -> :ok
        end
      end)

      await_line(port, "READY ", 5000)

      open =
        context.directory
        |> Path.join("native-open.json")
        |> File.read!()
        |> Jason.decode!()
        |> Map.put("endpoint", "opc.tcp://127.0.0.1:#{port_number}")

      %{same_stack: port, open: open}
    end

    test "WOP-C05 peer loss ends each live subscription once", context do
      {host, parameters} = open_burst(context)

      references =
        for _ <- 1..2 do
          assert {:ok, subscription} = Host.subscribe(host, parameters, self(), 1000, 5000)
          reference = subscription.reference
          assert_receive {:wotex_opcua, ^reference, {:ok, _, _}}, 5000
          reference
        end

      processes = native_processes(host)
      monitor = Process.monitor(host)
      Port.close(context.same_stack)
      assert_receive {:DOWN, ^monitor, :process, ^host, _}, 5000
      assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 1000)

      for reference <- references do
        assert_receive {:wotex_opcua, ^reference,
                        {:error, %Error{code: :connection_failed, effect: :none, details: details}}}

        assert Bitwise.band(details.status, 0x8000_0000) != 0
        refute_receive {:wotex_opcua, ^reference, _}, 50
      end
    end

    test "WOP-X04 a suspended owner under continuous reports stays within credit", context do
      {host, parameters} = open_burst(context)
      # Each outstanding Publish can return 64 notifications, so the four
      # answered while the owner is suspended exceed 16 credits plus 64 queued.
      parameters = %{parameters | "publishing_interval_ms" => 1000, "queue_size" => 100}

      references =
        for _ <- 1..4 do
          assert {:ok, subscription} = Host.subscribe(host, parameters, self(), 10_000, 5000)
          reference = subscription.reference
          assert_receive {:wotex_opcua, ^reference, {:ok, _, _}}, 5000
          reference
        end

      processes = native_processes(host)
      :ok = :sys.suspend(host)
      true = Port.command(context.same_stack, "c")
      assert eventually(fn -> not Enum.any?(processes, &os_alive?/1) end, 5000)
      true = Port.command(context.same_stack, "c")
      {:messages, mailbox} = Process.info(host, :messages)
      output = for {_, {:data, bytes}} <- mailbox, into: "", do: bytes
      lines = for line <- String.split(output, "\n", trim: true), do: {line, Jason.decode!(line)}

      {reports, controls} =
        Enum.split_with(lines, fn {_, line} -> is_map_key(line, "subscription_id") end)

      assert length(reports) == 16
      assert Enum.sum(for {line, _} <- reports, do: byte_size(line) + 1) <= 262_144

      assert [{_, %{"event" => "terminal", "error" => %{"code" => "receiver_overflow"}}}] = controls
      assert Enum.any?(mailbox, &match?({_, {:exit_status, _}}, &1))
      monitor = Process.monitor(host)
      :ok = :sys.resume(host)
      assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000
      messages = drain([])
      assert Enum.count(messages, &match?({:wotex_opcua, _, {:ok, _, _}}, &1)) == 16

      for reference <- references do
        assert [%Error{code: :receiver_overflow, effect: :none}] =
                 for({:wotex_opcua, ^reference, {:error, error}} <- messages, do: error)
      end

      assert eventually(fn -> match?(%{sessions: 0}, counters(context.same_stack)) end, 1000)
    end
  end

  defp open_burst(context) do
    executable = System.fetch_env!("WOTEX_OPCUA_NATIVE_EXECUTABLE")
    guardian = System.fetch_env!("WOTEX_OPCUA_NATIVE_GUARDIAN")

    {:ok, host, _} =
      Host.start_link(
        executable: executable,
        executable_digest: digest(executable),
        guardian: guardian,
        guardian_digest: digest(guardian),
        timeout: 5000
      )

    assert {:ok, %{"namespace_array" => namespaces}} =
             Host.request(host, "open", context.open, 5000)

    namespace = Enum.find_index(namespaces, &(&1 == "urn:wotex:fixture"))

    {host,
     %{
       "node_id" => "ns=#{namespace};s=burst",
       "publishing_interval_ms" => 50,
       "sampling_interval_ms" => 0,
       "queue_size" => 10,
       "discard_oldest" => true,
       "keepalive_count" => 10,
       "lifetime_count" => 30
     }}
  end

  defp native_processes(host) do
    %{port: port} = :sys.get_state(host)
    {:os_pid, guardian} = Port.info(port, :os_pid)

    {children, 0} =
      System.cmd("/usr/bin/pgrep", ["-P", Integer.to_string(guardian)], env: [{"LC_ALL", "C"}])

    [guardian | Enum.map(String.split(children), &String.to_integer/1)]
  end

  defp counters(port) do
    true = Port.command(port, "s")

    receive do
      {^port, {:data, {:eol, "COUNTERS " <> values}}} ->
        [sessions, _, _, _, channels] = Enum.map(String.split(values), &String.to_integer/1)
        %{sessions: sessions, channels: channels}
    after
      2000 -> flunk("peer counters unavailable")
    end
  end

  defp resources(session, peer) do
    assert {:ok, %{"outputs" => [%{"value" => subscriptions}, %{"value" => items}]}} =
             call(session, peer["resources_method_id"], [])

    {subscriptions, items}
  end

  defp call(session, method, arguments),
    do:
      Wotex.OPCUA.send(session, %{
        type: :call,
        node_id: method,
        value: %{object_id: "ns=0;i=85", arguments: arguments}
      })

  defp uint32(value), do: %{type: "UInt32", value: value}

  defp drain(messages) do
    receive do
      {:wotex_opcua, _, _} = message -> drain([message | messages])
    after
      300 -> Enum.reverse(messages)
    end
  end

  defp await_line(port, prefix, timeout) do
    receive do
      {^port, {:data, {:eol, ^prefix <> _}}} -> :ok
      {^port, {:data, _}} -> await_line(port, prefix, timeout)
      {^port, {:exit_status, status}} -> flunk("peer exited: #{status}")
    after
      timeout -> flunk("peer did not print #{prefix}")
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

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end
