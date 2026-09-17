defmodule Wotex.CoAP.NativeCorpusTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP.NativeBackend

  @moduletag :interop
  @moduletag :software

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @fixture_path Path.expand("../../docs/specs/fixtures/native-v1.json", __DIR__)
  @external_resource @fixture_path
  @command_cases ~w(WCO-N-F16 WCO-N-F17 WCO-N-F18 WCO-N-F19 WCO-N-F20)

  setup_all do
    backend = %{
      executable: System.fetch_env!("WOTEX_COAP_NATIVE_WORKER"),
      manifest: System.fetch_env!("WOTEX_COAP_NATIVE_MANIFEST")
    }

    assert {:ok, _} = NativeBackend.verify(backend)
    %{executable: backend.executable}
  end

  setup context do
    root = Path.join(System.tmp_dir!(), "wotex-coap-corpus-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    root = File.cd!(root, &File.cwd!/0)
    {:ok, peer} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, peer_port} = :inet.port(peer)

    on_exit(fn ->
      :gen_udp.close(peer)
      File.rm_rf!(root)
    end)

    Map.merge(context, %{
      root: root,
      peer: peer,
      peer_port: peer_port,
      secret: :crypto.strong_rand_bytes(16)
    })
  end

  test "WCO-C07 WCO-N03 an observe command with a Boolean renew reaches the network", context do
    # Positive control for F16-F20: the same command with an admitted renew value
    # transmits the protected registration to the test-owned UDP peer.
    command = put_in(fixture("WCO-N-F16")["input"], ["parameters", "renew"], false)
    port = open_worker(context, "control", 1)
    assert Port.command(port, Jason.encode!(command) <> "\n")
    peer = context.peer
    assert_receive {:udp, ^peer, {127, 0, 0, 1}, _, datagram}, 2_000
    assert byte_size(datagram) > 4
    Port.close(port)
  end

  for id <- @command_cases do
    @id id

    test "WCO-C07 WCO-N03 #{id} rejects the observe command before the network", context do
      corpus = fixture(@id)
      assert corpus["operation"] == "decode_command"
      expected = corpus["expected"]
      port = open_worker(context, @id, 1)

      assert Port.command(port, Jason.encode!(corpus["input"]) <> "\n")

      # The helper closes the generation without answering request 17. The BEAM
      # owner reports a helper that exits with its request unanswered as
      # native_protocol_error.
      assert {<<>>, status} = await_exit(port)
      assert expected["error"] == "native_protocol_error"
      assert expected["generation_closed"] and status != 0
      peer = context.peer
      refute_receive {:udp, ^peer, _, _, _}, 200
      assert expected["network_datagrams"] == 0
    end
  end

  test "WCO-N04 WCO-N-F06 a closed context cannot reopen or reach the network", context do
    corpus = fixture("WCO-N-F06")
    assert corpus["operation"] == "context_reopen_trace"
    expected = corpus["expected"]
    store = store(context.root, "reopen")

    first = start_worker(context.executable, store)
    assert read_ready(first)
    command(first, "1", "open", open_parameters(context, store, 1))
    assert read_json(first) == success("1")
    command(first, "2", "close", %{})
    assert read_json(first) == success("2")
    assert {<<>>, 0} = await_exit(first)
    registry = File.read!(Path.join(store, "contexts.v1"))

    second = start_worker(context.executable, store)
    assert read_ready(second)
    command(second, "1", "open", open_parameters(context, store, 2))
    assert read_json(second) == failure("1", expected["error"])

    # A request on the refused generation closes it unanswered.
    command(second, "2", "request", %{"method" => "GET", "path" => "/", "confirmable" => true})
    assert {<<>>, status} = await_exit(second)
    assert status != 0

    # No sender sequence was reserved, so generation 2 encrypted nothing.
    assert File.read!(Path.join(store, "contexts.v1")) == registry
    assert expected["generation_2_encryptions"] == 0
    peer = context.peer
    refute_receive {:udp, ^peer, _, _, _}, 200
    assert expected["generation_2_network_datagrams"] == 0
  end

  defp fixture(id) do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == id))
  end

  defp open_worker(context, name, generation) do
    store = store(context.root, name)
    port = start_worker(context.executable, store)
    assert read_ready(port)
    command(port, "1", "open", open_parameters(context, store, generation))
    assert read_json(port) == success("1")
    port
  end

  defp store(root, name) do
    path = Path.join(root, name)
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp start_worker(executable, store) do
    Port.open(
      {:spawn_executable, String.to_charlist(executable)},
      [:binary, :exit_status, :use_stdio, {:args, [~c"--custody", String.to_charlist(store)]}]
    )
  end

  defp read_ready(port) do
    read_json(port) == %{
      "version" => 1,
      "event" => "ready",
      "backend" => "libcoap",
      "revision" => @revision
    }
  end

  defp command(port, id, operation, parameters) do
    line =
      Jason.encode!(%{
        "version" => 1,
        "id" => id,
        "operation" => operation,
        "parameters" => parameters,
        "timeout_ms" => 1_000
      }) <> "\n"

    assert Port.command(port, line)
  end

  defp read_json(port, buffer \\ <<>>) do
    receive do
      {^port, {:data, bytes}} ->
        case :binary.split(buffer <> bytes, "\n") do
          [line, <<>>] when byte_size(line) > 0 -> Jason.decode!(line)
          [_, _] -> flunk("native helper emitted coalesced unsolicited output")
          [_] -> read_json(port, buffer <> bytes)
        end

      {^port, {:exit_status, status}} ->
        flunk("native helper exited before its response with status #{status}")
    after
      2_000 -> flunk("native helper response timed out")
    end
  end

  defp await_exit(port, output \\ <<>>) do
    receive do
      {^port, {:data, bytes}} -> await_exit(port, output <> bytes)
      {^port, {:exit_status, status}} -> {output, status}
    after
      2_000 -> flunk("native helper did not exit")
    end
  end

  defp open_parameters(context, store, generation) do
    %{
      "host" => "127.0.0.1",
      "port" => context.peer_port,
      "generation" => generation,
      "security" => %{
        "mode" => "oscore",
        "master_secret" => bytes(context.secret),
        "master_salt" => bytes(<<>>),
        "sender_id" => bytes(<<0>>),
        "recipient_id" => bytes(<<1>>),
        "id_context" => nil,
        "context_store" => store
      }
    }
  end

  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp success(id), do: %{"version" => 1, "id" => id, "ok" => true, "result" => nil}

  defp failure(id, code),
    do: %{"version" => 1, "id" => id, "ok" => false, "error" => %{"code" => code}}
end
