Code.require_file("../support/oscore.ex", __DIR__)
Code.require_file("../support/oscore_peer.ex", __DIR__)

defmodule Wotex.CoAP.NativeCorpusTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.CoAP.NativeBackend
  alias Wotex.CoAP.Test.OSCOREPeer

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

  test "WCO-S03 WCO-N02 WCO-N-F21 WCO-N-F22 protected establishment and cancellation follow the corpus",
       context do
    [establish, cancel] = Enum.map(~w(WCO-N-F21 WCO-N-F22), &fixture/1)
    assert establish["operation"] == "observe_establishment_trace"
    assert cancel["operation"] == "observe_cancel_trace"
    peer = OSCOREPeer.open(context.secret, <<1>>, <<0>>)
    on_exit(fn -> OSCOREPeer.close(peer) end)
    port = open_worker(Map.put(context, :peer_port, peer.port), "trace", 1)
    state = %{port: port, peer: peer, requests: %{}, buffer: <<>>}

    {state, emitted} = run_trace(establish["input"]["steps"], state)
    expected = resolve(establish["expected"], state)
    assert Enum.concat(emitted) == expected["stdout"]
    # The credit reply precedes the report, so no report was written before credit.
    assert [[], [_], [_, _]] = emitted
    assert expected["reports_before_credit"] == 0

    {state, emitted} = run_trace(cancel["input"]["steps"], state)
    expected = resolve(cancel["expected"], state)
    assert Enum.concat(emitted) == expected["stdout"]
    # The intervening notification writes nothing; the confirmation completes the
    # cancel and the later notification writes nothing.
    assert [[], [], [_], []] = emitted
    assert expected["intervening_observe_successes"] == 0
    assert expected["reports_after_cancel"] == 0

    command(port, "20", "cancel", %{"subscription_id" => "17", "generation" => 1})
    assert [failure("20", "invalid_request")] == elem(collect(state), 1)
    assert {:error, :timeout} = :gen_udp.recv(peer.socket, 0, 200)
    assert expected["subscriptions_after"] == 0
    Port.close(port)
  end

  test "WCO-S03 WCO-N02 WCO-N-F23 a registration answered without Observe establishes nothing",
       context do
    corpus = fixture("WCO-N-F23")
    assert corpus["operation"] == "observe_establishment_failure_trace"
    peer = OSCOREPeer.open(context.secret, <<1>>, <<0>>)
    on_exit(fn -> OSCOREPeer.close(peer) end)
    port = open_worker(Map.put(context, :peer_port, peer.port), "failure", 1)
    state = %{port: port, peer: peer, requests: %{}, buffer: <<>>}

    {state, emitted} = run_trace(corpus["input"]["steps"], state)
    expected = resolve(corpus["expected"], state)
    assert Enum.concat(emitted) == expected["stdout"]
    assert expected["establishments"] == 0 and expected["reports"] == 0

    # The helper closes the generation after the failed registration.
    assert {<<>>, 0} = await_exit(port)
    assert expected["subscriptions_after"] == 0
  end

  test "WCO-C05 WCO-N02 WCO-N-F05 a second pending Event report ends the subscription",
       context do
    corpus = fixture("WCO-N-F05")
    assert corpus["operation"] == "report_credit_trace"
    expected = corpus["expected"]
    state = establish(context, "overlap", "event")

    {state, emitted} = run_trace(corpus["input"]["steps"], state)
    lines = Enum.concat(emitted)
    assert Enum.all?(credit_replies(lines), &(&1["ok"] == true))
    assert length(reports(lines)) == expected["report_frames"]
    assert [terminal] = terminals(lines)
    assert length([terminal]) == expected["terminal_frames"]
    assert terminal["value"] == %{"code" => expected["terminal"]}
    refute Map.has_key?(terminal, "report_seq")

    # The terminal closes the generation, so neither a queued report nor the
    # subscription survives.
    assert {<<>>, 0} = await_exit(state.port)
    assert expected["queued_reports"] == 0 and expected["subscriptions_after"] == 0
  end

  test "WCO-C05 WCO-N02 WCO-N-F09 replayed and regressing credit grants no report", context do
    corpus = fixture("WCO-N-F09")
    assert corpus["operation"] == "report_credit_replay_trace"
    expected = corpus["expected"]
    state = establish(context, "replay", "event")

    {state, emitted} = run_trace(corpus["input"]["steps"], state)
    lines = Enum.concat(emitted)
    assert Enum.all?(credit_replies(lines), &(&1["ok"] == true))
    sequences = Enum.map(reports(lines), & &1["report_seq"])
    assert sequences == Enum.to_list(1..expected["report_frames"])
    assert Enum.max(sequences) == expected["highest_assigned_seq"]
    assert state.acknowledged == expected["acknowledged_seq"]
    assert state.acknowledged + 8 - Enum.max(sequences) == expected["unused_report_credit"]
    assert length(terminals(lines)) == expected["terminal_frames"]

    # Fresh credit releases exactly the queued report on the live subscription.
    command(state.port, "credit-release", "credit", %{"generation" => 1, "ack_seq" => 12})
    {state, released} = collect(state)
    assert [release | queued] = released
    assert release == success("credit-release")
    assert length(queued) == expected["queued_reports"]
    assert Enum.map(queued, & &1["report_seq"]) == [13]
    command(state.port, "cancel", "cancel", %{"subscription_id" => "17", "generation" => 1})
    assert {:ok, cancellation} = OSCOREPeer.receive_request(state.peer)
    OSCOREPeer.respond(state.peer, cancellation, code: 69)
    assert {_, [cancelled]} = collect(state)
    assert cancelled == success("cancel")
    assert expected["subscriptions_after"] == 1
    Port.close(state.port)
  end

  test "WCO-C05 WCO-N02 WCO-N-F15 an inline threshold report and a streamed report use exact credit",
       context do
    corpus = fixture("WCO-N-F15")
    assert corpus["operation"] == "report_payload_credit_trace"
    expected = corpus["expected"]
    steps = corpus["input"]["steps"]
    [first | _] = for %{"produce_report_payload" => payload} <- steps, do: expand(payload)
    state = establish(context, "payload", "property", first)

    {state, emitted} = run_trace(steps, state)
    lines = Enum.concat(emitted)
    assert Enum.all?(credit_replies(lines), &(&1["ok"] == true))
    frames = Enum.filter(lines, &Map.has_key?(&1, "report_seq"))
    sequences = Enum.map(frames, & &1["report_seq"])
    assert sequences == Enum.to_list(1..expected["highest_assigned_seq"])
    assert state.acknowledged == expected["acknowledged_seq"]
    assert state.acknowledged + 8 - List.last(sequences) == expected["unused_report_credit"]

    [inline | streamed] = frames
    assert inline["event"] == "report" and length([inline]) == expected["inline_report_frames"]
    assert Base.decode64!(inline["value"]["payload"]["base64"]) == first
    assert length(streamed) == expected["streamed_report_frames"]
    assert Enum.map(streamed, & &1["event"]) == ~w(body_begin body_chunk body_chunk body_end report)

    # The streamed body completes and verifies before its single report frame.
    [begin | chunks_end] = streamed
    {chunks, [_, final]} = Enum.split(chunks_end, 2)
    body = Enum.map_join(chunks, &Base.decode64!(&1["data"]["base64"]))
    assert body == expand(List.last(for %{"produce_report_payload" => p} <- steps, do: p))
    assert begin["sha256"] == Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    assert final["value"]["body_id"] == begin["body_id"]
    assert length(reports(lines)) == expected["complete_reports"]
    assert expected["partial_deliveries"] == 0
    Port.close(state.port)
  end

  test "WCO-C04 WCO-N02 WCO-N-F24 repeated established failure emits one terminal", context do
    [establish, loss] = Enum.map(~w(WCO-N-F21 WCO-N-F24), &fixture/1)
    assert loss["operation"] == "established_loss_trace"
    peer = OSCOREPeer.open(context.secret, <<1>>, <<0>>)
    on_exit(fn -> OSCOREPeer.close(peer) end)
    port = open_worker(Map.put(context, :peer_port, peer.port), "loss", 1)
    state = %{port: port, peer: peer, requests: %{}, buffer: <<>>, acknowledged: nil}
    {state, _} = run_trace(establish["input"]["steps"], state)

    {state, emitted} = run_trace(loss["input"]["steps"], state)
    expected = resolve(loss["expected"], state)
    assert Enum.concat(emitted) == expected["stdout"]
    assert [[_], []] = emitted
    assert length(expected["stdout"]) == expected["terminal_frames"]
    refute Map.has_key?(hd(expected["stdout"]), "report_seq")
    assert expected["report_credit_consumed"] == 0
    assert {<<>>, 0} = await_exit(state.port)
    assert expected["subscriptions_after"] == 0 and expected["generation_closed"]
  end

  defp run_trace(steps, state) do
    Enum.map_reduce(steps, state, fn step, state ->
      state = step(step, state)
      {state, lines} = collect(state)
      {lines, state}
    end)
    |> then(fn {emitted, state} -> {state, emitted} end)
  end

  defp step(%{"command" => command}, state) do
    assert Port.command(state.port, Jason.encode!(command) <> "\n")

    if command["operation"] in ~w(observe cancel) do
      assert {:ok, request} = OSCOREPeer.receive_request(state.peer)
      put_in(state, [:requests, command["id"]], request)
    else
      state
    end
  end

  defp step(%{"authenticated_response" => response}, state) do
    request = Map.fetch!(state.requests, response["answers"])
    assert resolve(response["token"], state) == bytes(request.outer.token)

    {observe, options} =
      Enum.split_with(response["options"], &(&1["number"] == 6))

    fields =
      [
        type: String.to_existing_atom(response["type"]),
        code: response["code"],
        message_id: resolve(response["message_id"], state),
        options: Enum.map(options, &{&1["number"], decode(&1["value"])}),
        payload: decode(response["payload"])
      ] ++
        case observe do
          [%{"value" => value}] ->
            [observe: true, partial_iv: :binary.decode_unsigned(decode(value))]

          [] ->
            []
        end

    %{state | peer: OSCOREPeer.respond(state.peer, request, fields)}
  end

  defp step(%{"grant_report_credit" => 8}, state),
    do: step(%{"request_id" => "grant", "ack_seq" => 0}, state)

  defp step(%{"request_id" => id, "ack_seq" => ack}, state) do
    command(state.port, id, "credit", %{"generation" => 1, "ack_seq" => ack})
    %{state | acknowledged: max(state.acknowledged || 0, ack)}
  end

  defp step(%{"suspend_beam_owner" => true}, state), do: state

  defp step(%{"produce_complete_single_frame_reports" => count}, state) do
    count = if Map.get(state, :initial), do: count - 1, else: count
    state = Map.put(state, :initial, false)

    Enum.reduce(1..count//1, state, fn _, state ->
      state = notify(state, code: 69, payload: "r#{state.produced + 1}")
      Process.sleep(20)
      state
    end)
  end

  defp step(%{"validate_report_frames_through" => sequence}, state) do
    {state, _} = collect(state)
    assert Map.get(state, :highest, 0) >= sequence
    state
  end

  defp step(%{"produce_report_payload" => payload}, %{initial: true} = state) do
    assert state.requests["17"]
    _ = expand(payload)
    %{state | initial: false}
  end

  defp step(%{"produce_report_payload" => payload}, state) do
    registration = state.requests["17"]
    message_id = rem(registration.outer.message_id + 1_000 + state.produced, 65_536)

    peer =
      OSCOREPeer.respond_blockwise(state.peer, registration, expand(payload),
        type: :non,
        message_id: message_id,
        code: 69,
        observe: true,
        partial_iv: :next,
        etag: "e#{state.produced + 1}"
      )

    %{state | peer: peer, produced: state.produced + 1}
  end

  defp step(%{"authenticated_notification" => %{"code" => code}}, state) do
    state = Map.put_new(state, :produced, 1)
    notify(state, code: code, payload: <<>>)
  end

  defp resolve(%{"request" => id, "field" => "message_id"}, state),
    do: state.requests[id].outer.message_id

  defp resolve(%{"request" => id, "field" => "token"}, state),
    do: bytes(state.requests[id].outer.token)

  defp resolve(%{"fresh_message_id" => index}, state) do
    used = Enum.map(state.requests, fn {_, request} -> request.outer.message_id end)

    Stream.iterate(rem(Enum.max(used) + 1_000 * index, 65_536), &rem(&1 + 1, 65_536))
    |> Enum.find(&(&1 not in used))
  end

  defp resolve(value, state) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, resolve(v, state)} end)

  defp resolve(values, state) when is_list(values), do: Enum.map(values, &resolve(&1, state))
  defp resolve(value, _), do: value

  defp collect(state, lines \\ []) do
    case :binary.split(state.buffer, "\n") do
      [line, rest] ->
        decoded = Jason.decode!(line)
        state = %{state | buffer: rest}

        state =
          case decoded do
            %{"report_seq" => sequence} -> Map.update(state, :highest, sequence, &max(&1, sequence))
            _ -> state
          end

        collect(state, [decoded | lines])

      [_] ->
        port = state.port

        receive do
          {^port, {:data, bytes}} -> collect(%{state | buffer: state.buffer <> bytes}, lines)
        after
          250 -> {state, Enum.reverse(lines)}
        end
    end
  end

  defp decode(%{"type" => "bytes", "base64" => value}), do: Base.decode64!(value)

  defp expand(%{"repeat_byte" => byte, "count" => count}), do: :binary.copy(<<byte>>, count)

  defp establish(context, name, kind, initial \\ "r1") do
    peer = OSCOREPeer.open(context.secret, <<1>>, <<0>>)
    on_exit(fn -> OSCOREPeer.close(peer) end)
    port = open_worker(Map.put(context, :peer_port, peer.port), name, 1)

    command(port, "17", "observe", %{
      "path" => "/value",
      "confirmable" => true,
      "observation_kind" => kind,
      "renew" => false
    })

    assert {:ok, registration} = OSCOREPeer.receive_request(peer)

    fields = [code: 69, observe: true, partial_iv: :next]

    peer =
      if byte_size(initial) > 1_024,
        do: OSCOREPeer.respond_blockwise(peer, registration, initial, fields),
        else: OSCOREPeer.respond(peer, registration, [payload: initial] ++ fields)

    state = %{
      port: port,
      peer: peer,
      requests: %{"17" => registration},
      buffer: <<>>,
      acknowledged: nil,
      initial: true,
      produced: 1
    }

    assert {state, [%{"id" => "17", "ok" => true}]} = collect(state)
    state
  end

  defp reports(lines), do: Enum.filter(lines, &(&1["event"] == "report"))
  defp terminals(lines), do: Enum.filter(lines, &(&1["event"] == "error"))

  defp credit_replies(lines),
    do: Enum.filter(lines, &(Map.has_key?(&1, "ok") and not Map.has_key?(&1, "event")))

  defp notify(state, fields) do
    registration = state.requests["17"]
    message_id = rem(registration.outer.message_id + 1_000 + state.produced, 65_536)

    peer =
      OSCOREPeer.respond(
        state.peer,
        registration,
        [type: :non, message_id: message_id, observe: true, partial_iv: :next] ++ fields
      )

    %{state | peer: peer, produced: state.produced + 1}
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
