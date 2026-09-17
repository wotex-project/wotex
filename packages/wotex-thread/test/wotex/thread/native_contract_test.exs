defmodule Wotex.Thread.NativeContractTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread.OpenThread.ReportLedger

  @moduletag :software
  @moduletag requirements: ["WTH-B02", "WTH-B03"]
  @fixture Path.expand("../../../docs/specs/fixtures/native-port-v1.json", __DIR__)
  # LeakSanitizer is part of the Linux fault lane; Apple AddressSanitizer rejects it.
  @leaks if match?({:unix, :linux}, :os.type()), do: "detect_leaks=1:", else: ""
  @sanitizer_env [
    {"ASAN_OPTIONS", @leaks <> "halt_on_error=1:abort_on_error=0"},
    {"UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1"}
  ]

  setup do
    driver = System.fetch_env!("WOTEX_THREAD_CONTRACT_DRIVER")
    assert Path.type(driver) == :absolute and File.regular?(driver)

    directory =
      Path.join(System.tmp_dir!(), "wotex-thread-contract-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{driver: driver, directory: directory}
  end

  test "WTH-B-F01 through F05 execute the shared production request validator", context do
    selected = cases("parse_request")
    assert Enum.map(selected, & &1["id"]) == Enum.map(1..5, &"WTH-B-F0#{&1}")

    for item <- selected do
      path = input!(context, item["id"], item["input"]["line_utf8"])
      assert {0, output} = run!(context.driver, ["parse_request", path])
      assert Jason.decode!(output) == expectation!(item), item["id"]
    end
  end

  test "WTH-B-F07 through F10 observe production report credit accounting", context do
    selected =
      Enum.filter(cases("flow_trace"), &(&1["id"] in ~w(WTH-B-F07 WTH-B-F08 WTH-B-F09 WTH-B-F10)))

    assert length(selected) == 4

    for item <- selected do
      path = input!(context, item["id"], Jason.encode!(item["input"]) <> "\n")
      assert {0, output} = run!(context.driver, ["flow_trace", path])
      [result | frames] = output |> String.split("\n", trim: true) |> Enum.reverse()
      frames = Enum.reverse(frames)
      observed = Jason.decode!(result)
      assert length(frames) == observed["transmitted"]

      requested =
        Enum.flat_map(item["input"]["events"], fn
          %{"event" => "transmit", "bytes" => bytes} = event ->
            List.duplicate(bytes, Map.get(event, "count", 1))

          _ ->
            []
        end)

      # Each transmitted frame carries the next session sequence at its exact encoded length.
      assert Enum.map(frames, &(byte_size(&1) + 1)) == Enum.take(requested, length(frames))

      assert Enum.map(frames, &Jason.decode!(&1)["report_sequence"]) ==
               Enum.to_list(1..length(frames)//1)

      assert observed == expectation!(item), item["id"]
    end
  end

  test "WTH-B-F14 and F15 couple native retirement to the production BEAM ledger", context do
    selected = Enum.filter(cases("flow_trace"), &(&1["id"] in ~w(WTH-B-F14 WTH-B-F15)))
    assert length(selected) == 2

    for item <- selected do
      configuration = Map.take(item["input"], ["session_generation", "queue_limit"])
      path = input!(context, item["id"], Jason.encode!(configuration) <> "\n")

      port =
        Port.open({:spawn_executable, context.driver}, [
          :binary,
          :exit_status,
          {:line, 131_072},
          args: ["flow_session", path],
          env: Enum.map(@sanitizer_env, fn {key, value} -> {~c"#{key}", ~c"#{value}"} end)
        ])

      {:os_pid, os_pid} = Port.info(port, :os_pid)

      initial = %{
        port: port,
        ledger: ReportLedger.new(),
        generation: configuration["session_generation"],
        queue_limit: configuration["queue_limit"],
        terminal: nil,
        transmitted: 0,
        snapshot: nil,
        sizes: %{},
        tokens: %{}
      }

      state =
        Enum.reduce_while(item["input"]["events"], initial, fn event, state ->
          state = trace(event, state)
          if state.terminal, do: {:halt, state}, else: {:cont, state}
        end)

      state = exchange(state, %{"event" => "close"})
      assert_receive {^port, {:exit_status, 0}}, 5_000
      assert exited?(os_pid)
      assert state.snapshot["transmitted"] == state.transmitted
      observed = Map.put(state.snapshot, "terminal", state.terminal)
      assert observed == expectation!(item), item["id"]
    end
  end

  defp trace(%{"event" => "transmit", "stream" => stream, "bytes" => bytes} = event, state) do
    key = {stream, 1}

    ledger =
      if ReportLedger.live?(state.ledger, key) do
        state.ledger
      else
        assert {:ok, ledger} = ReportLedger.open(state.ledger, key, state.queue_limit)
        ledger
      end

    exchange(%{state | ledger: ledger, sizes: Map.put(state.sizes, stream, bytes)}, event)
  end

  defp trace(%{"event" => "retire"} = event, state), do: state |> exchange(event) |> acknowledge()

  defp trace(%{"event" => "consume", "stream" => stream, "report_sequence" => sequence}, state) do
    token = Map.fetch!(state.tokens, sequence)
    assert {:ok, ledger} = ReportLedger.consume(state.ledger, {stream, 1}, sequence, token)
    acknowledge(%{state | ledger: ledger})
  end

  defp acknowledge(%{terminal: terminal} = state) when terminal != nil, do: state

  defp acknowledge(state) do
    case ReportLedger.advance(state.ledger) do
      {nil, _} ->
        state

      {ack, ledger} ->
        exchange(%{state | ledger: ledger}, %{
          "event" => "ack",
          "session_generation" => state.generation,
          "report_sequence" => ack.report_sequence,
          "acknowledged_bytes" => ack.acknowledged_bytes
        })
    end
  end

  defp exchange(state, event) do
    assert Port.command(state.port, [Jason.encode!(event), ?\n])
    frames(state)
  end

  defp frames(%{port: port} = state) do
    assert_receive {^port, {:data, {:eol, bytes}}}, 5_000

    case Jason.decode!(bytes) do
      %{"event" => "trace_snapshot"} = snapshot ->
        snapshot = Map.delete(snapshot, "event")
        assert snapshot["transmitted"] == state.transmitted
        %{state | snapshot: snapshot, terminal: state.terminal || snapshot["terminal"]}

      %{"event" => "trace_report", "stream" => stream, "report_sequence" => sequence} = frame
      when map_size(frame) == 4 ->
        assert byte_size(bytes) + 1 == Map.fetch!(state.sizes, stream)
        token = make_ref()

        assert {:ok, ledger} =
                 ReportLedger.register(
                   state.ledger,
                   {stream, 1},
                   sequence,
                   byte_size(bytes) + 1,
                   token
                 )

        tokens = Map.put(state.tokens, sequence, token)
        frames(%{state | ledger: ledger, tokens: tokens, transmitted: state.transmitted + 1})

      %{"event" => "trace_retired", "stream" => stream, "last_report_sequence" => last} = frame
      when map_size(frame) == 3 ->
        case ReportLedger.retire(state.ledger, {stream, 1}, last) do
          {:ok, ledger} -> frames(%{state | ledger: ledger})
          :error -> frames(%{state | terminal: "invalid_frame"})
        end
    end
  end

  defp run!(driver, args) do
    port =
      Port.open({:spawn_executable, driver}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        env: Enum.map(@sanitizer_env, fn {key, value} -> {~c"#{key}", ~c"#{value}"} end)
      ])

    collect(port, <<>>, System.monotonic_time(:millisecond) + 5_000)
  end

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 4_194_304 ->
        collect(port, output <> data, deadline)

      {^port, {:exit_status, status}} ->
        {status, output}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("native contract driver exceeded its deadline")
    end
  end

  defp exited?(os_pid, attempts \\ 100)
  defp exited?(_, 0), do: false

  defp exited?(os_pid, attempts) do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        exited?(os_pid, attempts - 1)

      _ ->
        true
    end
  end

  defp input!(context, id, bytes) do
    path = Path.join(context.directory, id)
    File.write!(path, bytes, [:exclusive])
    path
  end

  defp expectation!(%{"expectation" => %{"operator" => "exact", "value" => value}}), do: value

  defp cases(operation) do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    assert fixture["format"] == "wotex.native-contract"
    assert fixture["version"] == "1.0.0"
    assert fixture["package"] == "wotex_thread"

    assert Enum.map(fixture["cases"], & &1["id"]) ==
             Enum.map(1..15, &"WTH-B-F#{String.pad_leading(Integer.to_string(&1), 2, "0")}")

    assert Enum.all?(
             fixture["cases"],
             &(&1["operation"] in ~w(parse_request ready flow_trace process_flow))
           )

    Enum.filter(fixture["cases"], &(&1["operation"] == operation))
  end
end
