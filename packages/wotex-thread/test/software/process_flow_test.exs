defmodule Wotex.Thread.ProcessFlowTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Error, OpenThread, State}

  @moduletag :software
  @moduletag requirements: ["WTH-B02", "WTH-B03", "WTH-C05"]
  @fixture Path.expand("../../priv/fixtures/native-port-v1.json", __DIR__)

  setup do
    assert match?({:unix, :linux}, :os.type()), "process-flow ownership requires Linux procfs"
    host = System.fetch_env!("WOTEX_THREAD_FLOW_HOST")
    rcp = System.fetch_env!("WOTEX_THREAD_RCP")
    assert Path.type(host) == :absolute and File.regular?(host)
    assert Path.type(rcp) == :absolute and File.regular?(rcp)

    directory =
      Path.join(System.tmp_dir!(), "wth-flow-#{System.pid()}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{host: host, rcp: rcp, directory: directory}
  end

  for {id, suspended, node} <- [
        {"WTH-B-F11", "connection", 21},
        {"WTH-B-F12", "stream_owner", 22},
        {"WTH-B-F13", "receiver", 23}
      ] do
    # Each case covers 10000 native callbacks plus real SDK acquisition and cleanup.
    @tag timeout: 120_000
    test "#{id} suspends the actual #{suspended} across native State callbacks", context do
      item =
        @fixture
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("cases")
        |> Enum.find(&(&1["id"] == unquote(id)))

      assert item["operation"] == "process_flow"
      assert item["input"]["suspend"] == unquote(suspended)
      assert %{"operator" => "exact", "value" => expected} = item["expectation"]
      assert run!(item, context, unquote(node)) == expected
    end
  end

  defp run!(item, context, node) do
    input = item["input"]
    directory = Path.join(context.directory, item["id"])
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    executable = Path.join(directory, "flow-host")
    File.cp!(context.host, executable)
    File.chmod!(executable, 0o700)
    gate = Path.join(directory, "start")
    result = Path.join(directory, "native-result.json")

    File.write!(
      executable <> ".flow.json",
      Jason.encode!(%{
        callback_count: input["callback_count"],
        value_bytes: input["value_bytes"],
        callbacks_per_iteration: input["callbacks_per_iteration"],
        gate_path: gate,
        result_path: result
      }) <> "\n",
      [:exclusive]
    )

    parent = self()
    config = %{executable: executable, directory: directory, rcp: context.rcp, node: node}
    {receiver, monitor} = spawn_monitor(fn -> receiver(parent, config, input) end)

    try do
      observe_case(item, input, receiver, monitor, gate, result, directory)
    after
      # A failed assertion still ends the receiver, which owns the session and native host.
      Process.exit(receiver, :kill)
    end
  end

  defp observe_case(item, input, receiver, monitor, gate, result, directory) do
    assert_receive {:flow_prepared, ^receiver, prepared}, 30_000
    processes = Map.put(prepared, :receiver, receiver)
    selected = Map.fetch!(processes, String.to_existing_atom(input["suspend"]))
    assert length(Enum.uniq([processes.connection, processes.stream_owner, receiver])) == 3
    assert :erlang.suspend_process(selected)
    started = System.monotonic_time(:millisecond)
    File.write!(gate, "start\n", [:exclusive])

    initial = %{
      maximum: %{},
      terminal: nil,
      receiver_result: nil,
      receiver_down: false,
      resumed_at_ms: nil,
      close_sent_at_ms: nil,
      observed_values: 0
    }

    observed = observe(initial, processes, selected, monitor, input, result, started)
    observed = finish(observed, processes, monitor, result, started)
    assert observed.resumed_at_ms >= input["resume_at_ms"]

    assert observed.receiver_down,
           "receiver still open: #{inspect(Map.put(observed, :native_result, File.exists?(result)))}"

    assert observed.terminal in expected_terminals(input["suspend"])
    assert observed.receiver_result.delivered > 0
    # Reports reached the suspended connection's mailbox before it resumed.
    if input["suspend"] == "connection", do: assert(observed.observed_values > 0)

    native = Jason.decode!(File.read!(result))
    assert native["callbacks"] == input["callback_count"]
    assert native["iterations"] == div(input["callback_count"], input["callbacks_per_iteration"])
    assert native["reports_assigned"] > 0
    assert native["retirements"] == 1 and native["live_streams"] == 0
    assert native["stream_errors"] in 0..1

    if input["suspend"] in ["connection", "stream_owner"],
      do: assert(native["stream_errors"] == 1)

    survivors =
      Enum.count([processes.connection, processes.stream_owner, receiver], &Process.alive?/1) +
        Enum.count(processes.native, &File.exists?("/proc/#{&1}"))

    # The observation is retained beside the software run's case results.
    File.write!(
      Path.join(
        Path.dirname(System.fetch_env!("WOTEX_THREAD_CASE_RESULTS")),
        "process-flow-#{item["id"]}.json"
      ),
      Jason.encode!(%{
        case_id: item["id"],
        terminal: observed.terminal,
        receiver: observed.receiver_result,
        mailbox_maximum: observed.maximum,
        resumed_at_ms: observed.resumed_at_ms,
        close_sent_at_ms: observed.close_sent_at_ms,
        native: native
      })
    )

    %{
      "frame_bound" => frame_bound?(native["maximum"], observed.maximum, input),
      "byte_bound" => byte_bound?(native["maximum"], observed.maximum),
      "terminal_count" => observed.receiver_result.terminal_count,
      "deliveries_after_terminal" => observed.receiver_result.deliveries_after_terminal,
      "owned_processes_after_grace" => survivors
    }
  end

  # A suspended receiver can fill its queue first, or the native queue can overflow
  # first while deliveries to that receiver wait; either bound ends only this stream.
  defp expected_terminals("receiver"), do: [:receiver_overflow, :queue_overflow]
  defp expected_terminals(_), do: [:queue_overflow]

  defp receiver(parent, config, input) do
    options = [
      client: OpenThread,
      executable: config.executable,
      radio_url: "spinel+hdlc+forkpty://#{config.rcp}?forkpty-arg=#{config.node}",
      interface: "wthflow#{config.node}",
      storage_path: Path.join(config.directory, "settings"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 10_000
    ]

    assert {:ok, session} = Thread.connect(options)
    request = %{type: :state, max_queue_length: input["queue_limit"]}
    assert {:ok, subscription} = Thread.subscribe(session, request)
    reference = subscription.reference
    assert_receive {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: 0}}}, 10_000
    connection = session.handle.pid
    eventually(fn -> map_size(:sys.get_state(connection).reports) == 0 end)
    state = :sys.get_state(connection)
    [record] = Map.values(state.subscriptions)
    {:os_pid, os_pid} = Port.info(state.port, :os_pid)

    send(
      parent,
      {:flow_prepared, self(),
       %{
         connection: connection,
         stream_owner: record.owner,
         port: state.port,
         native: [os_pid | descendants(os_pid)]
       }}
    )

    counters = %{terminal_count: 0, deliveries_after_terminal: 0, delivered: 0}
    receiver_loop(parent, session, reference, counters)
  end

  defp receiver_loop(parent, session, reference, counters) do
    receive do
      {:wotex_thread, ^reference, {:ok, %State{}, %{changed_flags: flags}}} when flags > 0 ->
        after_terminal = if counters.terminal_count > 0, do: 1, else: 0

        receiver_loop(parent, session, reference, %{
          counters
          | delivered: counters.delivered + 1,
            deliveries_after_terminal: counters.deliveries_after_terminal + after_terminal
        })

      {:wotex_thread, ^reference, {:error, %Error{code: code}}} ->
        if counters.terminal_count == 0, do: send(parent, {:flow_terminal, self(), code})

        receiver_loop(parent, session, reference, %{
          counters
          | terminal_count: counters.terminal_count + 1
        })

      :flow_close ->
        assert :ok = Thread.disconnect(session)
        send(parent, {:flow_receiver_result, self(), drain(reference, counters)})

      {:wotex_thread, ^reference, other} ->
        flunk("unexpected process-flow delivery #{inspect(other)}")
    after
      30_000 -> flunk("process-flow receiver did not finish")
    end
  end

  defp drain(reference, counters) do
    receive do
      {:wotex_thread, ^reference, {:ok, _, _}} ->
        drain(reference, %{
          counters
          | deliveries_after_terminal: counters.deliveries_after_terminal + 1
        })

      {:wotex_thread, ^reference, {:error, _}} ->
        drain(reference, %{counters | terminal_count: counters.terminal_count + 1})
    after
      0 -> counters
    end
  end

  defp observe(state, processes, selected, monitor, input, result, started) do
    elapsed = System.monotonic_time(:millisecond) - started
    state = messages(state, processes.receiver, monitor)

    state =
      if is_nil(state.resumed_at_ms) and elapsed >= input["resume_at_ms"] do
        # A retired stream owner may already have been stopped while suspended.
        try do
          :erlang.resume_process(selected)
        rescue
          ArgumentError -> refute Process.alive?(selected)
        end

        %{state | resumed_at_ms: elapsed}
      else
        state
      end

    state = maybe_close(sample(state, processes, input), processes, result, started)

    if elapsed < input["observe_until_ms"] do
      Process.sleep(1)
      observe(state, processes, selected, monitor, input, result, started)
    else
      state
    end
  end

  # After the observation window, completion and cleanup keep their own bounds.
  defp finish(state, processes, monitor, result, started) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    finish_loop(state, processes, monitor, result, started, deadline)
  end

  defp finish_loop(state, processes, monitor, result, started, deadline) do
    state =
      state
      |> messages(processes.receiver, monitor)
      |> maybe_close(processes, result, started)

    cond do
      state.receiver_down and resources_gone?(processes) ->
        state

      System.monotonic_time(:millisecond) >= deadline ->
        state

      true ->
        Process.sleep(5)
        finish_loop(state, processes, monitor, result, started, deadline)
    end
  end

  defp maybe_close(state, processes, result, started) do
    if is_nil(state.close_sent_at_ms) and state.terminal != nil and File.exists?(result) do
      send(processes.receiver, :flow_close)
      %{state | close_sent_at_ms: System.monotonic_time(:millisecond) - started}
    else
      state
    end
  end

  defp messages(state, receiver, monitor) do
    receive do
      {:flow_terminal, ^receiver, code} ->
        messages(%{state | terminal: code}, receiver, monitor)

      {:flow_receiver_result, ^receiver, result} ->
        messages(%{state | receiver_result: result}, receiver, monitor)

      {:DOWN, ^monitor, :process, ^receiver, :normal} ->
        messages(%{state | receiver_down: true}, receiver, monitor)
    after
      0 -> state
    end
  end

  defp sample(state, processes, input) do
    port = processes.port

    port_counts =
      Enum.reduce(mailbox(processes.connection), %{}, fn
        {^port, {:data, {:eol, line}}}, counts ->
          {frames, bytes} =
            cond do
              :binary.match(line, ~s("event":"state")) != :nomatch ->
                {"port_reports", "port_report_bytes"}

              :binary.match(line, ~s("event":)) != :nomatch ->
                {"port_controls", "port_control_bytes"}

              true ->
                {"port_replies", "port_reply_bytes"}
            end

          counts = increment(increment(counts, frames, 1), bytes, byte_size(line) + 1)

          if frames == "port_reports" do
            assert [_, value] = Regex.run(~r/"value":(\{[^}]*\})/, line)
            assert byte_size(value) == input["value_bytes"]
            increment(counts, "observed_values", 1)
          else
            counts
          end

        _, counts ->
          counts
      end)

    owner =
      Enum.filter(mailbox(processes.stream_owner), &match?({:wotex_thread_report, _, _, _, _}, &1))

    receiver =
      Enum.filter(mailbox(processes.receiver), &match?({:wotex_thread, _, {:ok, _, _}}, &1))

    counts =
      port_counts
      |> Map.put("owner_reports", length(owner))
      |> Map.put("owner_bytes", Enum.reduce(owner, 0, &(:erlang.external_size(&1) + &2)))
      |> Map.put("receiver_reports", length(receiver))
      |> Map.put("receiver_bytes", Enum.reduce(receiver, 0, &(:erlang.external_size(&1) + &2)))

    %{
      state
      | maximum:
          Map.merge(state.maximum, Map.delete(counts, "observed_values"), fn _, old, new ->
            max(old, new)
          end),
        observed_values: state.observed_values + Map.get(counts, "observed_values", 0)
    }
  end

  defp frame_bound?(native, observed, input) do
    within?(native, ~w(queued_reports outstanding_reports output_report_frames), 64) and
      within?(native, ["output_control_frames"], 256) and
      within?(native, ["output_reply_frames"], 64) and
      within?(observed, ~w(port_reports owner_reports), 64) and
      within?(observed, ["receiver_reports"], input["queue_limit"]) and
      within?(observed, ["port_controls"], 256) and
      within?(observed, ["port_replies"], 64)
  end

  defp byte_bound?(native, observed) do
    within?(
      native,
      ~w(queued_report_bytes outstanding_report_bytes output_report_bytes output_control_bytes),
      1_048_576
    ) and
      within?(native, ["output_reply_bytes"], 8_388_608) and
      within?(
        observed,
        ~w(port_report_bytes port_control_bytes owner_bytes receiver_bytes),
        1_048_576
      ) and
      within?(observed, ["port_reply_bytes"], 8_388_608)
  end

  defp resources_gone?(processes) do
    Enum.all?(
      [processes.connection, processes.stream_owner, processes.receiver],
      &(not Process.alive?(&1))
    ) and
      Port.info(processes.port) == nil and
      Enum.all?(processes.native, &(not File.exists?("/proc/#{&1}")))
  end

  defp mailbox(pid) do
    case Process.info(pid, :messages) do
      {:messages, messages} -> messages
      nil -> []
    end
  end

  defp increment(map, key, count), do: Map.update(map, key, count, &(&1 + count))
  defp within?(counts, names, limit), do: Enum.all?(names, &(Map.get(counts, &1, 0) <= limit))

  defp descendants(pid) do
    case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, text} ->
        children = Enum.map(String.split(text), &String.to_integer/1)
        children ++ Enum.flat_map(children, &descendants/1)

      {:error, _} ->
        []
    end
  end

  defp eventually(condition, remaining \\ 500)
  defp eventually(condition, 0), do: assert(condition.())

  defp eventually(condition, remaining) do
    unless condition.() do
      Process.sleep(10)
      eventually(condition, remaining - 1)
    end
  end
end
