Code.require_file("../support/libcoap_peer.ex", __DIR__)

defmodule Wotex.CoAP.LifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Error, Message, NativeBackend, Security, Subscription}
  alias Wotex.CoAP.Test.LibcoapPeer

  @moduletag :interop
  @moduletag :software
  @moduletag :capture_log
  @moduletag timeout: 900_000

  @cleanup_ms 1_000
  @recipients 400

  setup_all do
    peer = LibcoapPeer.verify!()

    backend = %{
      executable: System.fetch_env!("WOTEX_COAP_NATIVE_WORKER"),
      manifest: System.fetch_env!("WOTEX_COAP_NATIVE_MANIFEST")
    }

    assert {:ok, _} = NativeBackend.verify(backend)
    %{executable: peer, backend: backend}
  end

  setup context do
    root = Path.join(System.tmp_dir!(), "wotex-coap-stress-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root = File.cd!(root, &File.cwd!/0)
    on_exit(fn -> File.rm_rf!(root) end)

    Map.merge(context, %{
      root: root,
      secret: :crypto.strong_rand_bytes(16),
      sender: :counters.new(1, [])
    })
  end

  for transport <- [:udp, :dtls_psk, :dtls_pki, :oscore] do
    @transport transport

    test "WCO-C09 WCO-V15 #{transport} sequential, concurrent and lifecycle stress returns owned resources",
         context do
      context = Map.put(context, :transport, @transport)
      peer = start_peer(context)
      context = Map.put(context, :peer, peer)
      {:ok, writer} = CoAP.connect(host: "127.0.0.1", port: plain_port(peer), timeout: 5_000)

      try do
        warm = connect!(context)
        assert {:ok, %Message{code: 69}} = CoAP.get(warm, "/")
        close!(warm)
        baseline = settled!(snapshot(), snapshot())

        sequential(context, baseline)
        concurrent(context, writer, baseline)
        admission(context, baseline)
        open_close(context, baseline)
        observe_cancel(context, writer, baseline)
        receiver_death(context, writer, baseline)
        receiver_overflow(context, writer, baseline)
      after
        CoAP.disconnect(writer)
        if Process.alive?(peer), do: assert(:ok = LibcoapPeer.close(peer))
      end
    end
  end

  for transport <- [:udp, :dtls_psk, :dtls_pki, :oscore] do
    @transport transport

    test "WCO-C09 WCO-V02 WCO-V15 #{transport} forced deadline, malformed response and peer close release resources",
         context do
      context = Map.put(context, :transport, @transport)
      peer = start_peer(context)
      context = Map.put(context, :peer, peer)
      warm = connect!(context)
      assert {:ok, %Message{code: 69}} = CoAP.get(warm, "/")
      close!(warm)
      baseline = settled!(snapshot(), snapshot())

      deadline(context, baseline)
      malformed(context, baseline)
      peer_close(context, baseline)
      report(context, "forced_failures", [])
    end
  end

  defp deadline(context, baseline) do
    session = connect!(context, timeout: 1_500)
    helper = helper(session)
    started = System.monotonic_time(:millisecond)

    assert {:error, %Error{code: :timeout, effect: :none}} = CoAP.get(session, "/async?3")
    assert System.monotonic_time(:millisecond) - started < 2_500
    assert :ok = CoAP.disconnect(session)
    settled!(baseline)
    if helper, do: refute(os_process_alive?(helper))
  end

  defp malformed(context, baseline) do
    {:ok, fault} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, fault_port}} = :inet.sockname(fault)
    context = Map.put(context, :fault_port, fault_port)
    started = System.monotonic_time(:millisecond)

    try do
      case context.transport do
        transport when transport in [:dtls_psk, :dtls_pki] ->
          # Every handshake record is answered with bytes that are not DTLS.
          caller = Task.async(fn -> CoAP.connect(connect_options(context, 1_000)) end)
          reply_malformed(fault, :garbage)

          assert {:error, %Error{effect: :none}} = Task.await(caller, 5_000)

        _ ->
          session = connect!(context, timeout: 1_000)
          helper = helper(session)
          caller = Task.async(fn -> CoAP.get(session, "/") end)
          reply_malformed(fault, :truncated_option)

          assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(caller, 5_000)
          assert :ok = CoAP.disconnect(session)
          if helper, do: refute(os_process_alive?(helper))
      end
    after
      :gen_udp.close(fault)
    end

    assert System.monotonic_time(:millisecond) - started < 3_000
    settled!(baseline)
  end

  defp peer_close(context, baseline) do
    session = connect!(context, timeout: 1_000)
    helper = helper(session)
    assert {:ok, %Message{code: 69}} = CoAP.get(session, "/")
    assert :ok = LibcoapPeer.close(context.peer)

    assert {:error, %Error{code: code, effect: :none}} = CoAP.get(session, "/")
    assert code in [:timeout, :connection_closed]
    assert :ok = CoAP.disconnect(session)
    settled!(baseline)
    if helper, do: refute(os_process_alive?(helper))
  end

  # Answers each client datagram until the socket closes. A truncated option
  # keeps the request's MID and token so correlation alone cannot complete it.
  defp reply_malformed(fault, mode) do
    receive do
      {:udp, ^fault, address, port, <<_::4, token_length::4, _, mid::16, rest::binary>>} ->
        token = binary_part(rest, 0, min(token_length, byte_size(rest)))

        reply =
          case mode do
            :garbage ->
              :crypto.strong_rand_bytes(24)

            :truncated_option ->
              <<1::2, 2::2, byte_size(token)::4, 69, mid::16, token::binary, 0xD5, 0x01>>
          end

        :ok = :gen_udp.send(fault, address, port, reply)
        reply_malformed(fault, mode)

      {:udp, ^fault, address, port, _} ->
        :ok = :gen_udp.send(fault, address, port, :crypto.strong_rand_bytes(24))
        reply_malformed(fault, mode)
    after
      1_500 -> :ok
    end
  end

  defp sequential(context, baseline) do
    session = connect!(context)
    path = "/stress-sequence"
    assert {:ok, %Message{code: 65}} = CoAP.put(session, path, "0", content_format: :text)

    samples =
      for operation <- 1..1_000, reduce: [] do
        samples ->
          if rem(operation, 2) == 0 do
            payload = Integer.to_string(operation)

            assert {:ok, %Message{code: 68}} =
                     CoAP.put(session, path, payload, content_format: :text)
          else
            expected = Integer.to_string(max(operation - 1, 0))
            assert {:ok, %Message{code: 69, payload: ^expected}} = CoAP.get(session, path)
          end

          if rem(operation, 100) == 0,
            do: [sample(context, session, operation) | samples],
            else: samples
      end

    report(context, "sequential", Enum.reverse(samples))
    close!(session)
    settled!(baseline)
  end

  defp concurrent(context, writer, baseline) do
    session = connect!(context)

    paths =
      for index <- 1..32 do
        path = "/stress-caller-#{index}"
        payload = "caller-#{index}-" <> Base.encode16(:crypto.strong_rand_bytes(8))
        assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, payload, content_format: :text)
        {path, payload}
      end

    results =
      paths
      |> Task.async_stream(fn {path, payload} -> {payload, CoAP.get(session, path)} end,
        max_concurrency: 32,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert length(results) == 32

    for {payload, result} <- results,
        do: assert({:ok, %Message{code: 69, payload: ^payload}} = result)

    close!(session)
    settled!(baseline)
  end

  defp admission(context, baseline) do
    session = connect!(context, timeout: 30_000)
    :ok = :sys.suspend(session.pid)
    parent = self()

    callers =
      for _ <- 1..96 do
        spawn(fn -> send(parent, {:admitted, self(), CoAP.get(session, "/")}) end)
      end

    # Native sessions reserve capacity before the owner mailbox and return busy
    # at once; datagram sessions admit when the owner reads each call. Resume
    # only after every caller is either answered or waiting in the mailbox.
    assert eventually(fn ->
             {:message_queue_len, queued} = Process.info(session.pid, :message_queue_len)
             {:messages, answered} = Process.info(self(), :messages)
             queued + Enum.count(answered, &match?({:admitted, _, _}, &1)) == 96
           end)

    :ok = :sys.resume(session.pid)

    results =
      for _ <- 1..96 do
        assert_receive {:admitted, caller, result}, 30_000
        {caller, result}
      end

    assert Enum.sort(Enum.map(results, &elem(&1, 0))) == Enum.sort(callers)

    assert Enum.count(results, &match?({_, {:error, %Error{code: :busy, effect: :none}}}, &1)) ==
             32

    assert Enum.count(results, &match?({_, {:ok, %Message{code: 69}}}, &1)) == 64
    assert {:ok, %Message{code: 69}} = CoAP.get(session, "/")
    close!(session)
    settled!(baseline)
  end

  defp open_close(context, baseline) do
    for _ <- 1..100 do
      session = connect!(context)
      helper = helper(session)
      assert {:ok, %Message{code: 69}} = CoAP.get(session, "/")
      close!(session)
      settled!(baseline)
      if helper, do: refute(os_process_alive?(helper))
    end
  end

  defp observe_cancel(context, writer, baseline) do
    path = "/stress-observe"
    assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "0", content_format: :text)
    before = LibcoapPeer.subscriptions(context.peer)

    for cycle <- 1..100 do
      session = connect!(context)
      assert {:ok, %Subscription{reference: reference} = handle} = CoAP.subscribe(session, path)
      previous = Integer.to_string(cycle - 1)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: ^previous}, _}}, 5_000
      payload = Integer.to_string(cycle)
      assert {:ok, %Message{code: 68}} = CoAP.put(writer, path, payload, content_format: :text)
      assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: ^payload}, _}}, 5_000
      assert :ok = CoAP.unsubscribe(session, handle)
      settled!(baseline)
      refute_received {:wotex_coap, ^reference, _}

      assert_subscriptions(context.peer, %{
        created: before.created + cycle,
        removed: before.removed + cycle
      })
    end
  end

  defp receiver_death(context, writer, baseline) do
    path = "/stress-receiver"
    assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "0", content_format: :text)
    before = LibcoapPeer.subscriptions(context.peer)
    parent = self()

    for cycle <- 1..100 do
      session = connect!(context)
      helper = helper(session)

      receiver =
        spawn(fn ->
          receive do
            {:wotex_coap, _, {:ok, _, _}} -> send(parent, {:receiver_ready, self()})
          end

          Process.sleep(:infinity)
        end)

      assert {:ok, %Subscription{}} = CoAP.subscribe(session, %{path: path, receiver: receiver})
      assert_receive {:receiver_ready, ^receiver}, 5_000
      monitor = Process.monitor(session.pid)
      Process.exit(receiver, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
      settled!(baseline)
      if helper, do: refute(os_process_alive?(helper))

      assert_subscriptions(context.peer, %{
        created: before.created + cycle,
        removed: before.removed + cycle
      })
    end
  end

  defp receiver_overflow(context, writer, baseline) do
    path = "/stress-overflow"
    assert {:ok, %Message{code: 65}} = CoAP.put(writer, path, "0", content_format: :text)
    session = connect!(context)
    receiver = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, %Subscription{}} =
             CoAP.subscribe(session, %{path: path, receiver: receiver, max_queue_length: 2})

    monitor = Process.monitor(session.pid)

    outcome =
      Enum.reduce_while(1..200, nil, fn value, _ ->
        assert {:ok, %Message{code: 68}} =
                 CoAP.put(writer, path, Integer.to_string(value), content_format: :text)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> {:halt, :closed}
        after
          10 -> {:cont, nil}
        end
      end)

    if outcome != :closed, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1_100)

    {:messages, messages} = Process.info(receiver, :messages)
    assert Enum.count(messages, &match?({:wotex_coap, _, {:ok, _, _}}, &1)) <= 2

    assert [{:wotex_coap, _, {:error, %Error{code: :receiver_overflow}}}] =
             Enum.filter(messages, &match?({:wotex_coap, _, {:error, _}}, &1))

    Process.exit(receiver, :kill)
    settled!(baseline)
  end

  defp eventually(function, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    cond do
      function.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(5) && eventually(function, deadline)
    end
  end

  defp start_peer(%{transport: transport} = context) do
    options =
      case transport do
        :oscore ->
          {context.executable, :oscore,
           %{
             master_secret: context.secret,
             master_salt: <<>>,
             sender_id: <<>>,
             recipient_ids: Enum.map(1..@recipients, &<<&1::16>>)
           }}

        :dtls_pki ->
          {context.executable, :pki, "server"}

        _ ->
          {context.executable, :psk, "server"}
      end

    start_supervised!(
      Supervisor.child_spec({LibcoapPeer, options}, id: make_ref(), restart: :temporary)
    )
  end

  defp plain_port(peer), do: LibcoapPeer.plain_endpoint(peer)

  defp connect!(context, overrides \\ []) do
    assert {:ok, session} =
             CoAP.connect(connect_options(context, Keyword.get(overrides, :timeout, 5_000)))

    session
  end

  defp connect_options(context, timeout) do
    peer = context.peer
    fault_port = Map.get(context, :fault_port)

    options =
      case context.transport do
        :udp ->
          [host: "127.0.0.1", port: plain_port(peer), timeout: timeout]

        :dtls_psk ->
          [
            host: "127.0.0.1",
            port: LibcoapPeer.endpoint(peer),
            scheme: :coaps,
            security: LibcoapPeer.security(:psk),
            timeout: timeout
          ]

        :dtls_pki ->
          [
            host: "127.0.0.1",
            port: LibcoapPeer.endpoint(peer),
            scheme: :coaps,
            security: LibcoapPeer.pki_security(),
            timeout: timeout
          ]

        :oscore ->
          sender = :counters.get(context.sender, 1) + 1
          :counters.add(context.sender, 1, 1)
          assert sender <= @recipients
          store = Path.join(context.root, "store-#{sender}")
          File.mkdir!(store)
          File.chmod!(store, 0o700)

          {:ok, security} =
            Security.new(
              mode: :oscore,
              master_secret: context.secret,
              master_salt: <<>>,
              sender_id: <<sender::16>>,
              recipient_id: <<>>,
              context_store: store
            )

          [
            host: "127.0.0.1",
            port: plain_port(peer),
            security: security,
            native_backend: context.backend,
            timeout: timeout
          ]
      end

    if fault_port, do: Keyword.put(options, :port, fault_port), else: options
  end

  defp close!(session) do
    monitor = Process.monitor(session.pid)
    assert :ok = CoAP.disconnect(session)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
  end

  defp helper(session) do
    case :sys.get_state(session.pid) do
      %{os_pid: os_pid} when is_integer(os_pid) -> os_pid
      _ -> nil
    end
  end

  defp snapshot, do: %{ports: MapSet.new(Port.list()), processes: MapSet.new(Process.list())}

  defp settled!(baseline), do: settled!(baseline, nil)

  defp settled!(baseline, _) do
    deadline = System.monotonic_time(:millisecond) + @cleanup_ms
    await_settled(baseline, deadline)
  end

  defp await_settled(baseline, deadline) do
    current = snapshot()
    ports = MapSet.difference(current.ports, baseline.ports)

    processes =
      current.processes
      |> MapSet.difference(baseline.processes)
      |> Enum.reject(&(&1 == self()))

    cond do
      MapSet.size(ports) == 0 and processes == [] ->
        current

      System.monotonic_time(:millisecond) >= deadline ->
        flunk(
          "owned resources did not return to baseline: #{MapSet.size(ports)} ports, " <>
            "#{length(processes)} processes"
        )

      true ->
        Process.sleep(10)
        await_settled(baseline, deadline)
    end
  end

  defp assert_subscriptions(peer, expected) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    await_subscriptions(peer, expected, deadline)
  end

  defp await_subscriptions(peer, expected, deadline) do
    actual = LibcoapPeer.subscriptions(peer)

    cond do
      actual == expected ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        assert actual == expected

      true ->
        Process.sleep(10)
        await_subscriptions(peer, expected, deadline)
    end
  end

  defp sample(context, session, operation) do
    %{
      "operation" => operation,
      "beam_total_bytes" => :erlang.memory(:total),
      "helper_rss_kib" => helper_rss(context, session)
    }
  end

  defp helper_rss(%{transport: :oscore}, session) do
    os_pid = helper(session)

    case System.cmd("/bin/ps", ["-o", "rss=", "-p", Integer.to_string(os_pid)],
           stderr_to_stdout: true,
           env: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
         ) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.to_integer()

      _ ->
        nil
    end
  end

  defp helper_rss(_, _), do: nil

  defp report(context, phase, samples) do
    Mix.shell().info(
      "WCO-C09 resource trend " <>
        Jason.encode!(%{
          "transport" => context.transport,
          "phase" => phase,
          "samples" => samples
        })
    )
  end

  defp os_process_alive?(os_pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(os_pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
      )

    status == 0
  end
end
