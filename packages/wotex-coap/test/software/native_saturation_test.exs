Code.require_file("../support/oscore.ex", __DIR__)
Code.require_file("../support/oscore_peer.ex", __DIR__)

defmodule Wotex.CoAP.NativeSaturationTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Message, NativeBackend, Security, Subscription}
  alias Wotex.CoAP.Test.OSCOREPeer

  @moduletag :interop
  @moduletag :software
  @moduletag :capture_log

  @window 8
  @frame_bytes 131_072
  @cleanup_ms 1_100

  setup_all do
    backend = %{
      executable: System.fetch_env!("WOTEX_COAP_NATIVE_WORKER"),
      manifest: System.fetch_env!("WOTEX_COAP_NATIVE_MANIFEST")
    }

    assert {:ok, _} = NativeBackend.verify(backend)
    %{backend: backend}
  end

  setup context do
    root =
      Path.join(System.tmp_dir!(), "wotex-coap-saturation-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root = File.cd!(root, &File.cwd!/0)
    secret = :crypto.strong_rand_bytes(16)
    peer = OSCOREPeer.open(secret, <<1>>, <<0>>)

    on_exit(fn ->
      OSCOREPeer.close(peer)
      File.rm_rf!(root)
    end)

    Map.merge(context, %{root: root, secret: secret, peer: peer})
  end

  test "WCO-C05 WCO-N02 a suspended native owner holds at most eight report frames and still receives its terminal",
       context do
    {session, handle, registration, peer} = subscribe!(context, "property")
    %{port: port} = :sys.get_state(session.pid)
    :ok = :sys.suspend(session.pid)

    peer = produce(peer, registration, 40)
    samples = sample(session.pid, port, 600)
    assert Enum.max_by(samples, & &1.reports).reports == @window
    # At most the one in-flight credit reply accompanies the report frames.
    assert Enum.all?(samples, &(&1.reports <= @window and &1.replies <= 1))
    assert Enum.all?(samples, &(&1.frames == &1.reports + &1.replies))
    assert Enum.all?(samples, &(&1.bytes <= @window * @frame_bytes))
    assert {:queue_size, 0} = :erlang.port_info(port, :queue_size)

    # With the report window full, the terminal still reaches the suspended owner
    # through its reserved control slot.
    produce(peer, registration, 1, code: 132)
    [last | _] = samples = sample(session.pid, port, 600) |> Enum.reverse()
    assert last.terminals == 1 and last.reports == @window
    assert Enum.all?(samples, &(&1.reports <= @window and &1.terminals <= 1))
    :ok = :sys.resume(session.pid)

    reference = handle.reference
    values = receive_values(reference, [])
    assert length(values) <= @window
    assert_receive {:wotex_coap, ^reference, {:error, %Error{}}}, 2_000
    assert_down(session.pid)
  end

  test "WCO-C03 WCO-N02 killing a suspended native owner with a full window cancels and reaps the helper",
       context do
    {session, _, registration, peer} = subscribe!(context, "event")
    %{port: port, os_pid: os_pid} = :sys.get_state(session.pid)
    :ok = :sys.suspend(session.pid)
    peer = produce(peer, registration, 20)
    samples = sample(session.pid, port, 600)
    # Event overlap adds one terminal through the reserved control slot.
    assert Enum.max_by(samples, & &1.reports).reports == @window
    assert Enum.all?(samples, &(&1.reports <= @window and &1.terminals <= 1))

    started = System.monotonic_time(:millisecond)
    Process.exit(session.pid, :kill)
    assert {:ok, cancellation} = OSCOREPeer.receive_request(peer, @cleanup_ms)
    assert Codec.option(cancellation.inner, 6) == [<<1>>]
    assert_reaped(os_pid, started + @cleanup_ms)
  end

  defp subscribe!(context, kind) do
    store = Path.join(context.root, "store")
    File.mkdir!(store)
    File.chmod!(store, 0o700)

    {:ok, security} =
      Security.new(
        mode: :oscore,
        master_secret: context.secret,
        master_salt: <<>>,
        sender_id: <<0>>,
        recipient_id: <<1>>,
        context_store: store
      )

    assert {:ok, session} =
             CoAP.connect(
               host: "127.0.0.1",
               port: context.peer.port,
               timeout: 5_000,
               security: security,
               native_backend: context.backend
             )

    test = self()
    kind = String.to_existing_atom(kind)

    task =
      Task.async(fn ->
        CoAP.subscribe(session, %{path: "/value", receiver: test, observation_kind: kind})
      end)

    assert {:ok, registration} = OSCOREPeer.receive_request(context.peer)

    peer =
      OSCOREPeer.respond(context.peer, registration,
        code: 69,
        observe: true,
        partial_iv: :next,
        payload: "r0"
      )

    assert {:ok, %Subscription{reference: reference} = handle} = Task.await(task, 5_000)
    assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: "r0"}, _}}, 5_000
    {session, handle, registration, peer}
  end

  defp produce(peer, registration, count, fields \\ []) do
    Enum.reduce(1..count, peer, fn index, peer ->
      message_id = rem(registration.outer.message_id + 1_000 + peer.sequence, 65_536)

      peer =
        OSCOREPeer.respond(
          peer,
          registration,
          [
            type: :non,
            message_id: message_id,
            observe: true,
            partial_iv: :next,
            code: 69,
            payload: "r#{peer.sequence}-#{index}"
          ]
          |> Keyword.merge(fields)
        )

      Process.sleep(10)
      peer
    end)
  end

  defp sample(pid, port, duration) do
    deadline = System.monotonic_time(:millisecond) + duration

    Stream.repeatedly(fn ->
      {:messages, messages} = Process.info(pid, :messages)
      data = for {^port, {:data, bytes}} <- messages, into: <<>>, do: bytes
      lines = :binary.split(data, "\n", [:global]) |> Enum.drop(-1)
      Process.sleep(10)

      %{
        frames: length(lines),
        reports: Enum.count(lines, &String.contains?(&1, ~s("event":"report"))),
        terminals: Enum.count(lines, &String.contains?(&1, ~s("event":"error"))),
        replies: Enum.count(lines, &String.starts_with?(&1, ~s({"version":1,"id":))),
        bytes: byte_size(data)
      }
    end)
    |> Enum.take_while(fn _ -> System.monotonic_time(:millisecond) < deadline end)
  end

  defp receive_values(reference, values) do
    receive do
      {:wotex_coap, ^reference, {:ok, %Message{} = message, _}} ->
        receive_values(reference, [message | values])
    after
      0 -> Enum.reverse(values)
    end
  end

  defp assert_down(pid) do
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, @cleanup_ms
  end

  defp assert_reaped(os_pid, deadline) do
    cond do
      not os_process_alive?(os_pid) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("native helper #{os_pid} outlived the cleanup bound")

      true ->
        Process.sleep(20)
        assert_reaped(os_pid, deadline)
    end
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
