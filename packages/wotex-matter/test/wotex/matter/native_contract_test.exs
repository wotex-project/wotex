Code.require_file("../../support/software/command.exs", __DIR__)
Code.require_file("../../support/software/process_flow.exs", __DIR__)

defmodule Wotex.Matter.NativeContractTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.Native.ReportLedger
  alias Wotex.Matter.SoftwareCommand

  @moduletag :software
  @fixture "priv/fixtures/native-port-v1.json"

  for {id, suspended} <- [
        {"WMA-B-F11", "connection"},
        {"WMA-B-F12", "stream_owner"},
        {"WMA-B-F13", "receiver"}
      ] do
    @tag :process_flow
    test "#{id} suspends the actual #{suspended} across native callbacks" do
      item = Enum.find(fixture!()["cases"], &(&1["id"] == unquote(id)))
      assert item["input"]["suspend"] == unquote(suspended)
      assert item["expectation"]["operator"] == "exact"

      fixture =
        System.fetch_env!("WOTEX_MATTER_PROCESS_FLOW_FIXTURE")
        |> File.read!()
        |> Jason.decode!()

      observed = Wotex.Matter.SoftwareProcessFlow.run!(item, fixture)
      assert observed == item["expectation"]["value"], item["id"]
    end
  end

  test "WMA-B-F01 through F05 execute the shared native request validator" do
    fixture = fixture!()
    selected = Enum.filter(fixture["cases"], &(&1["operation"] == "parse_request"))
    assert Enum.map(selected, & &1["id"]) == Enum.map(1..5, &"WMA-B-F0#{&1}")
    executable = System.fetch_env!("WOTEX_MATTER_CONTRACT_DRIVER")

    directory =
      Path.join(System.tmp_dir!(), "wotex-native-corpus-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)

    try do
      for item <- selected do
        assert item["expectation"]["operator"] == "exact"
        path = Path.join(directory, item["id"])
        File.write!(path, item["input"]["line_utf8"], [:exclusive])

        assert {:ok, output} =
                 SoftwareCommand.run(executable, [item["operation"], path],
                   timeout: 1_000,
                   env: [
                     {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
                     {"UBSAN_OPTIONS", "halt_on_error=1"}
                   ]
                 )

        assert Jason.decode!(output) == item["expectation"]["value"], item["id"]
      end
    after
      File.rm_rf!(directory)
    end
  end

  test "WMA-B-F06 captures the real native ready frame and reaps its closed input" do
    item = Enum.find(fixture!()["cases"], &(&1["id"] == "WMA-B-F06"))
    assert item["operation"] == "ready"
    assert item["input"] == %{"stdin" => "close_after_ready"}
    executable = System.fetch_env!("WOTEX_MATTER_NATIVE_EXECUTABLE")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [:binary, :exit_status, :use_stdio, {:line, 131_072}]
      )

    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      assert_receive {^port, {:data, {:eol, bytes}}}, 1_000
      Port.close(port)
      remaining = surviving_child(child, 100)
      observation = %{"frame" => Jason.decode!(bytes), "owned_processes_after_grace" => remaining}
      assert observation == item["expectation"]["value"]
    after
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end
  end

  test "WMA-B-F16 and F17 execute the production encoded-result size guard" do
    selected = Enum.filter(fixture!()["cases"], &(&1["operation"] == "result_budget"))
    assert Enum.map(selected, & &1["id"]) == ["WMA-B-F16", "WMA-B-F17"]
    executable = System.fetch_env!("WOTEX_MATTER_CONTRACT_DRIVER")

    directory =
      Path.join(System.tmp_dir!(), "wotex-result-budget-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)

    try do
      for item <- selected do
        assert item["expectation"]["operator"] == "exact"
        bytes = Map.fetch!(item["input"], "encoded_result_bytes")
        assert is_integer(bytes) and bytes >= 0
        path = Path.join(directory, item["id"])
        File.write!(path, Integer.to_string(bytes) <> "\n", [:exclusive])

        assert {:ok, output} =
                 SoftwareCommand.run(executable, ["result_budget", path],
                   timeout: 1_000,
                   env: [
                     {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
                     {"UBSAN_OPTIONS", "halt_on_error=1"}
                   ]
                 )

        assert Jason.decode!(output) == item["expectation"]["value"], item["id"]
      end
    after
      File.rm_rf!(directory)
    end
  end

  test "WMA-B-F07 through F10 observe production report credit accounting" do
    selected =
      Enum.filter(
        fixture!()["cases"],
        &(&1["id"] in ["WMA-B-F07", "WMA-B-F08", "WMA-B-F09", "WMA-B-F10"])
      )

    assert length(selected) == 4
    executable = System.fetch_env!("WOTEX_MATTER_CONTRACT_DRIVER")

    directory =
      Path.join(System.tmp_dir!(), "wotex-flow-trace-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)

    try do
      for item <- selected do
        assert item["operation"] == "flow_trace"
        assert item["expectation"]["operator"] == "exact"
        path = Path.join(directory, item["id"])
        File.write!(path, Jason.encode!(item["input"]) <> "\n", [:exclusive])

        assert {:ok, output} =
                 SoftwareCommand.run(executable, ["flow_trace", path],
                   timeout: 1_000,
                   env: [
                     {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"},
                     {"UBSAN_OPTIONS", "halt_on_error=1"}
                   ]
                 )

        [result | reversed_frames] =
          output
          |> String.split("\n", trim: true)
          |> Enum.reverse()

        observed = Jason.decode!(result)
        frames = Enum.reverse(reversed_frames)
        assert length(frames) == observed["transmitted"]

        requested_bytes =
          Enum.flat_map(item["input"]["events"], fn
            %{"event" => "transmit", "bytes" => bytes} = event ->
              List.duplicate(bytes, Map.get(event, "count", 1))

            _ ->
              []
          end)

        assert Enum.map(frames, &(byte_size(&1) + 1)) == Enum.take(requested_bytes, length(frames))
        assert observed == item["expectation"]["value"], item["id"]
      end
    after
      File.rm_rf!(directory)
    end
  end

  test "WMA-B-F14 and F15 couple native retirement to the production BEAM ledger" do
    selected = Enum.filter(fixture!()["cases"], &(&1["id"] in ["WMA-B-F14", "WMA-B-F15"]))
    assert length(selected) == 2
    executable = System.fetch_env!("WOTEX_MATTER_CONTRACT_DRIVER")

    directory =
      Path.join(System.tmp_dir!(), "wotex-retire-trace-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)

    try do
      for item <- selected do
        assert item["operation"] == "flow_trace"
        assert item["expectation"]["operator"] == "exact"
        configuration = Map.take(item["input"], ["session_generation", "queue_limit"])
        path = Path.join(directory, item["id"])
        File.write!(path, Jason.encode!(configuration) <> "\n", [:exclusive])

        port =
          Port.open({:spawn_executable, String.to_charlist(executable)}, [
            :binary,
            :exit_status,
            :use_stdio,
            {:line, 131_072},
            {:args, [~c"flow_session", String.to_charlist(path)]},
            {:env,
             [
               {~c"ASAN_OPTIONS", ~c"detect_leaks=1:halt_on_error=1"},
               {~c"UBSAN_OPTIONS", ~c"halt_on_error=1"}
             ]}
          ])

        {:os_pid, child} = Port.info(port, :os_pid)

        try do
          initial = %{
            port: port,
            ledger: ReportLedger.new(),
            generation: configuration["session_generation"],
            terminal: nil,
            transmitted: 0,
            snapshot: nil,
            byte_sizes: %{},
            barriers: []
          }

          state =
            Enum.reduce_while(item["input"]["events"], initial, fn event, state ->
              observed = trace_event(event, state)
              if observed.terminal, do: {:halt, observed}, else: {:cont, observed}
            end)

          state = trace_exchange(state, %{"event" => "close"})
          assert_receive {^port, {:exit_status, 0}}, 1_000
          assert surviving_child(child, 100) == 0
          assert state.snapshot["transmitted"] == state.transmitted
          observed = Map.put(state.snapshot, "terminal", state.terminal)
          assert observed == item["expectation"]["value"], item["id"]
        after
          try do
            Port.close(port)
          rescue
            ArgumentError -> :ok
          end
        end
      end
    after
      File.rm_rf!(directory)
    end
  end

  defp trace_event(%{"event" => "transmit", "stream" => stream, "bytes" => bytes} = event, state) do
    ledger =
      if Map.has_key?(state.ledger.streams, stream) do
        state.ledger
      else
        assert {:ok, opened} = ReportLedger.open(state.ledger, stream)
        opened
      end

    state = %{state | ledger: ledger, byte_sizes: Map.put(state.byte_sizes, stream, bytes)}
    trace_exchange(state, event)
  end

  defp trace_event(%{"event" => "retire", "stream" => stream} = event, state) do
    received = trace_exchange(state, event)
    assert [%{"stream" => ^stream}] = received.barriers
    flush_trace_ack(received)
  end

  defp trace_event(
         %{"event" => "consume", "stream" => stream, "report_sequence" => sequence},
         state
       ) do
    %{stream: ^stream, token: token} = Map.fetch!(state.ledger.pending, sequence)
    assert {:ok, consumed} = ReportLedger.consume(state.ledger, stream, sequence, token)
    flush_trace_ack(%{state | ledger: consumed})
  end

  defp flush_trace_ack(%{terminal: terminal} = state) when terminal != nil, do: state

  defp flush_trace_ack(state) do
    case ReportLedger.advance(state.ledger) do
      {nil, _} ->
        state

      {ack, ledger} ->
        trace_exchange(%{state | ledger: ledger}, %{
          "event" => "ack",
          "session_generation" => state.generation,
          "report_sequence" => ack.report_sequence,
          "acknowledged_bytes" => ack.acknowledged_bytes
        })
    end
  end

  defp trace_exchange(state, event) do
    assert Port.command(state.port, [Jason.encode!(event), ?\n])
    trace_frames(%{state | barriers: []})
  end

  defp trace_frames(%{port: port} = state) do
    assert_receive {^port, {:data, {:eol, bytes}}}, 1_000
    frame = Jason.decode!(bytes)

    case frame do
      %{"event" => "trace_snapshot"} ->
        snapshot = Map.delete(frame, "event")
        assert snapshot["transmitted"] == state.transmitted
        %{state | snapshot: snapshot, terminal: state.terminal || snapshot["terminal"]}

      %{
        "event" => "trace_report",
        "stream" => stream,
        "report_sequence" => sequence,
        "body" => body
      }
      when map_size(frame) == 4 and is_binary(body) ->
        assert byte_size(bytes) + 1 == Map.fetch!(state.byte_sizes, stream)

        assert {:ok, ledger} =
                 ReportLedger.register(
                   state.ledger,
                   stream,
                   sequence,
                   byte_size(bytes) + 1,
                   make_ref()
                 )

        trace_frames(%{state | ledger: ledger, transmitted: state.transmitted + 1})

      %{"event" => "trace_retired", "stream" => stream, "last_report_sequence" => last}
      when map_size(frame) == 3 ->
        state = %{state | barriers: [frame | state.barriers]}

        case ReportLedger.retire(state.ledger, stream, last) do
          {:ok, ledger} -> trace_frames(%{state | ledger: ledger})
          :error -> trace_frames(%{state | terminal: "invalid_frame"})
        end
    end
  end

  defp surviving_child(_, 0), do: 1

  defp surviving_child(pid, remaining) do
    case Wotex.Matter.Native.ProcessCommand.run("kill", ["-0", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Process.sleep(10)
        surviving_child(pid, remaining - 1)

      {_, _} ->
        0
    end
  end

  defp fixture! do
    fixture =
      @fixture
      |> File.read!()
      |> Jason.decode!()

    assert fixture["format"] == "wotex.native-contract"
    assert fixture["version"] == "1.0.0"
    assert fixture["package"] == "wotex_matter"

    assert Enum.map(fixture["cases"], & &1["id"]) ==
             Enum.map(1..17, &"WMA-B-F#{String.pad_leading(Integer.to_string(&1), 2, "0")}")

    assert Enum.all?(
             fixture["cases"],
             &(&1["operation"] in [
                 "parse_request",
                 "ready",
                 "flow_trace",
                 "process_flow",
                 "result_budget"
               ])
           )

    fixture
  end
end
