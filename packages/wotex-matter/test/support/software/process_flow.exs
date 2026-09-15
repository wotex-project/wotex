defmodule Wotex.Matter.SoftwareProcessFlow do
  @moduledoc false

  import ExUnit.Assertions

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native}

  @spec run!(map(), map()) :: map()
  def run!(item, fixture) do
    assert File.dir?("/proc/self/fd"), "process-flow ownership requires Linux procfs"
    assert item["operation"] == "process_flow"
    input = Map.fetch!(item, "input")
    directory = Path.join(Map.fetch!(fixture, "directory"), item["id"])
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    config = Path.join(directory, "configuration.json")
    gate = Path.join(directory, "start")
    done = Path.join(directory, "source-complete")
    result = Path.join(directory, "native-result.json")

    File.write!(
      config,
      Jason.encode!(%{input: input, gate_path: gate, done_path: done, result_path: result}),
      [:exclusive]
    )

    File.chmod!(config, 0o600)
    previous = System.get_env("WOTEX_MATTER_FLOW_CONFIG")
    System.put_env("WOTEX_MATTER_FLOW_CONFIG", config)
    parent = self()
    {receiver, monitor} = spawn_monitor(fn -> receiver(parent, fixture, input) end)

    try do
      assert_receive {:flow_prepared, ^receiver, prepared}, 15_000
      Process.put({__MODULE__, receiver}, prepared)
      processes = Map.put(prepared, :receiver, receiver)
      selected = Map.fetch!(processes, String.to_existing_atom(input["suspend"]))
      assert is_pid(selected) and Process.alive?(selected)
      assert length(Enum.uniq([processes.connection, processes.stream_owner, receiver])) == 3
      assert :erlang.suspend_process(selected)
      started = System.monotonic_time(:millisecond)
      File.write!(gate, "start\n", [:exclusive])
      File.chmod!(gate, 0o600)

      state = %{
        maximum: %{},
        terminal: nil,
        receiver_result: nil,
        receiver_down: false,
        resumed_at_ms: nil,
        resume_action: nil,
        resources_gone_at_ms: nil,
        close_sent: false,
        observed_values: 0
      }

      observed = observe(state, processes, selected, monitor, input, done, started)
      assert observed.resumed_at_ms >= input["resume_at_ms"]
      assert is_integer(observed.resources_gone_at_ms)
      assert observed.resources_gone_at_ms <= input["observe_until_ms"]
      assert observed.terminal in [:queue_overflow, :receiver_overflow]
      assert observed.receiver_down
      assert %{terminal_count: 1} = observed.receiver_result
      assert File.read!(done) == "complete\n"
      assert Port.info(processes.port) == nil
      assert :ets.info(processes.admission) == :undefined
      native = result |> File.read!() |> Jason.decode!()
      assert native["exit_status"] == 0
      counts = Map.fetch!(native, "counts")
      maximum = Map.fetch!(native, "maximum")
      assert counts["sdk_reports"] >= 1
      assert counts["sdk_subscriptions_acquired"] == 1
      assert counts["sdk_controllers_closed"] == 1
      assert counts["sources_acquired"] == 1
      assert counts["sources_destroyed"] == 1
      assert counts["callbacks_acquired"] == input["callback_count"]
      assert counts["callbacks_destroyed"] == input["callback_count"]
      assert counts["iterations"] == input["callback_count"]
      assert is_integer(counts["source_elapsed_us"]) and counts["source_elapsed_us"] > 0
      assert counts["callbacks_admitted"] + counts["callbacks_refused"] == input["callback_count"]
      assert counts["callbacks_admitted"] > 0
      assert counts["callbacks_refused"] > 0
      assert counts["sdk_cancellations_completed"] == 1
      assert counts["retirement_barriers"] == 1
      assert counts["values_encoded"] > 0
      assert counts["reports_transmitted"] > 0
      assert_resources_released(native)

      for key <-
            ~w(queued_reports queued_report_bytes outstanding_reports outstanding_report_bytes output_report_frames output_report_bytes output_control_frames output_control_bytes output_reply_frames output_reply_bytes),
          do: assert(is_integer(Map.fetch!(maximum, key)))

      for key <-
            ~w(invalid_callback_values invalid_encoded_values source_completion_write_failures reports_after_terminal),
          do: assert(Map.get(counts, key, 0) == 0)

      if input["suspend"] == "connection", do: assert(observed.observed_values > 0)

      surviving =
        Enum.count([processes.connection, processes.stream_owner, receiver], &Process.alive?/1) +
          if(File.exists?("/proc/#{processes.child}"), do: 1, else: 0)

      normalized = %{
        "frame_bound" =>
          within?(maximum, ~w(queued_reports outstanding_reports output_report_frames), 64) and
            within?(maximum, ["output_control_frames"], 256) and
            within?(maximum, ["output_reply_frames"], 64) and
            within?(observed.maximum, ~w(port_reports owner_reports receiver_reports), 64) and
            within?(observed.maximum, ["port_controls"], 256) and
            within?(observed.maximum, ["port_replies"], 64),
        "byte_bound" =>
          within?(
            maximum,
            ~w(queued_report_bytes outstanding_report_bytes output_report_bytes output_control_bytes),
            1_048_576
          ) and
            within?(maximum, ["output_reply_bytes"], 8_388_608) and
            within?(
              observed.maximum,
              ~w(port_report_bytes port_control_bytes owner_bytes receiver_bytes),
              1_048_576
            ) and
            within?(observed.maximum, ["port_reply_bytes"], 8_388_608),
        "terminal_count" => observed.receiver_result.terminal_count,
        "deliveries_after_terminal" => observed.receiver_result.deliveries_after_terminal,
        "owned_processes_after_grace" => surviving
      }

      File.write!(
        Path.join(directory, "observation.json"),
        Jason.encode!(%{
          case_id: item["id"],
          normalized: normalized,
          mailbox_maximum: observed.maximum,
          resumed_at_ms: observed.resumed_at_ms,
          resume_action: observed.resume_action,
          resources_gone_at_ms: observed.resources_gone_at_ms,
          native: native
        }),
        [:exclusive]
      )

      normalized
    after
      # A failing assertion still owns every process started by this case.
      Process.exit(receiver, :kill)

      try do
        if prepared = Process.delete({__MODULE__, receiver}) do
          Process.exit(prepared.connection, :kill)
          Process.exit(prepared.stream_owner, :kill)
          cleanup_port(prepared, System.monotonic_time(:millisecond) + 1_000)
        end
      after
        Process.demonitor(monitor, [:flush])

        if previous,
          do: System.put_env("WOTEX_MATTER_FLOW_CONFIG", previous),
          else: System.delete_env("WOTEX_MATTER_FLOW_CONFIG")
      end
    end
  end

  defp assert_resources_released(native) do
    before = Map.fetch!(native, "resources_before")
    after_cleanup = Map.fetch!(native, "resources_after")
    objects = Map.fetch!(after_cleanup, "objects")

    assert Enum.sort(Map.keys(objects)) ==
             Enum.sort(~w(interaction commissioning window subscription read_client write_client
                          command_sender window_opener recovery_timer))

    for {name, counts} <- objects do
      assert before["objects"][name] == %{"acquired" => 0, "destroyed" => 0}
      assert is_integer(counts["acquired"]) and counts["acquired"] >= 0
      assert counts["destroyed"] == counts["acquired"], name
    end

    assert objects["subscription"]["acquired"] == 1
    assert objects["read_client"]["acquired"] == 1
    assert after_cleanup["events"]["subscription_published"] == 1
    assert after_cleanup["events"]["subscription_cancelled"] >= 1
    sdk = Map.fetch!(after_cleanup, "sdk")
    assert sdk == Map.fetch!(before, "sdk")

    for name <- ["Packet Buffers", "Timers", "UDP endpoints", "Exchange contexts"],
        do: assert(is_integer(Map.fetch!(sdk, name)) and Map.fetch!(sdk, name) >= 0)
  end

  defp receiver(parent, fixture, input) do
    controller = Map.fetch!(fixture, "controller")

    options =
      [
        client: Native,
        lifecycle: :persistent,
        storage_mode: :open_existing,
        authority: :stored,
        timeout: 10_000
      ] ++
        Enum.map(
          [
            :executable,
            :storage_path,
            :vendor_id,
            :fabric_id,
            :controller_node_id,
            :paa_trust_store
          ],
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    assert {:ok, session} = Matter.connect(options)

    try do
      path = %{
        fabric_id: options[:fabric_id],
        node_id: fixture["node_id"],
        endpoint: fixture["endpoint"],
        cluster: 6,
        member: 0
      }

      assert {:ok, subscription} =
               Matter.subscribe(session, %{
                 kind: :attribute,
                 paths: [path],
                 min_interval_s: 0,
                 max_interval_s: 60,
                 max_queue_length: input["queue_limit"],
                 resubscribe: false
               })

      reference = subscription.reference

      assert_receive {:wotex_matter, ^reference,
                      {:ok, %{type: :boolean, value: initial}, metadata}},
                     10_000

      connection = session.handle.pid
      assert credit_returned?(connection, System.monotonic_time(:millisecond) + 1_000)
      state = :sys.get_state(connection)
      {:os_pid, child} = Port.info(state.port, :os_pid)

      send(
        parent,
        {:flow_prepared, self(),
         %{
           connection: connection,
           stream_owner: state.subscriptions[reference].stream_owner,
           port: state.port,
           child: child,
           admission: session.handle.admission
         }}
      )

      receiver_loop(parent, session, reference, initial, %{
        terminal_count: 0,
        deliveries_after_terminal: 0,
        last_report_id: metadata.report_id,
        delivered: 0
      })
    after
      Matter.disconnect(session)
    end
  end

  defp receiver_loop(parent, session, reference, initial, counters) do
    receive do
      {:wotex_matter, ^reference, {:ok, %{type: :boolean, value: ^initial}, metadata}} ->
        assert metadata.report_id > counters.last_report_id

        counters = %{
          counters
          | last_report_id: metadata.report_id,
            delivered: counters.delivered + 1,
            deliveries_after_terminal:
              counters.deliveries_after_terminal + if(counters.terminal_count > 0, do: 1, else: 0)
        }

        receiver_loop(parent, session, reference, initial, counters)

      {:wotex_matter, ^reference, {:error, %Error{code: code}}} ->
        send(parent, {:flow_terminal, self(), code})

        receiver_loop(parent, session, reference, initial, %{
          counters
          | terminal_count: counters.terminal_count + 1
        })

      :flow_close ->
        assert {:ok, %{"status" => "ready"}} = Native.health(session.handle)
        assert :ok = Matter.disconnect(session)
        send(parent, {:flow_receiver_result, self(), drain(reference, counters)})

      {:wotex_matter, ^reference, _} ->
        flunk("process-flow received a value outside its real SDK report template")
    after
      5_000 -> flunk("process-flow receiver did not finish")
    end
  end

  defp drain(reference, counters) do
    receive do
      {:wotex_matter, ^reference, {:ok, _, _}} ->
        drain(reference, %{
          counters
          | deliveries_after_terminal: counters.deliveries_after_terminal + 1
        })

      {:wotex_matter, ^reference, {:error, _}} ->
        drain(reference, %{counters | terminal_count: counters.terminal_count + 1})
    after
      0 -> counters
    end
  end

  defp credit_returned?(connection, deadline) do
    if :sys.get_state(connection).report_ledger.pending == %{} do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(1)
        credit_returned?(connection, deadline)
      else
        false
      end
    end
  end

  defp observe(state, processes, selected, monitor, input, done, started) do
    elapsed = System.monotonic_time(:millisecond) - started
    state = messages(state, processes.receiver, monitor)

    state =
      if is_nil(state.resumed_at_ms) and elapsed >= input["resume_at_ms"] do
        action =
          if Process.alive?(selected) do
            try do
              assert :erlang.resume_process(selected)
              :resumed
            rescue
              ArgumentError ->
                refute Process.alive?(selected)
                :already_closed
            end
          else
            :already_closed
          end

        %{state | resumed_at_ms: elapsed, resume_action: action}
      else
        state
      end

    state =
      if (not state.close_sent and state.terminal) && File.exists?(done) do
        send(processes.receiver, :flow_close)
        %{state | close_sent: true}
      else
        state
      end

    state = sample(state, processes)

    state =
      if is_nil(state.resources_gone_at_ms) and resources_gone?(processes),
        do: %{state | resources_gone_at_ms: System.monotonic_time(:millisecond) - started},
        else: state

    if elapsed < input["observe_until_ms"] do
      Process.sleep(1)
      observe(state, processes, selected, monitor, input, done, started)
    else
      messages(state, processes.receiver, monitor)
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

  defp sample(state, processes) do
    port = processes.port

    port_counts =
      Enum.reduce(mailbox(processes.connection), %{}, fn
        {^port, {:data, {:eol, bytes}}}, acc ->
          frame = Jason.decode!(bytes)

          {kind, count_key, byte_key} =
            case frame["event"] do
              "subscription_report" -> {:report, "port_reports", "port_report_bytes"}
              nil -> {:reply, "port_replies", "port_reply_bytes"}
              _ -> {:control, "port_controls", "port_control_bytes"}
            end

          acc = acc |> increment(count_key, 1) |> increment(byte_key, byte_size(bytes) + 1)

          if kind == :report do
            assert [_, value] =
                     Regex.run(
                       ~r/"value":(\{"tag":"anonymous","type":"boolean","value":(?:true|false) *\})/,
                       bytes
                     )

            assert byte_size(value) == 128
            increment(acc, "observed_values", 1)
          else
            acc
          end

        _, acc ->
          acc
      end)

    counts =
      Enum.reduce(
        [{"owner", processes.stream_owner}, {"receiver", processes.receiver}],
        port_counts,
        fn {name, pid}, acc ->
          reports =
            Enum.filter(mailbox(pid), fn
              {:wotex_matter, _, %Wotex.Matter.Native.Delivery{}} -> true
              {:wotex_matter, _, {:ok, _, _}} -> true
              _ -> false
            end)

          acc
          |> Map.put(name <> "_reports", length(reports))
          |> Map.put(name <> "_bytes", Enum.reduce(reports, 0, &(:erlang.external_size(&1) + &2)))
        end
      )

    %{
      state
      | maximum: Map.merge(state.maximum, counts, fn _, old, current -> max(old, current) end),
        observed_values: state.observed_values + Map.get(counts, "observed_values", 0)
    }
  end

  defp mailbox(pid) do
    case Process.info(pid, :messages) do
      {:messages, messages} -> messages
      nil -> []
    end
  end

  defp increment(map, key, count), do: Map.update(map, key, count, &(&1 + count))
  defp within?(counts, names, limit), do: Enum.all?(names, &(Map.get(counts, &1, 0) <= limit))

  defp cleanup_port(prepared, deadline) do
    if Port.info(prepared.port) != nil or File.exists?("/proc/#{prepared.child}") do
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(1)
        cleanup_port(prepared, deadline)
      else
        flunk("process-flow native owner survived cleanup")
      end
    end
  end

  defp resources_gone?(processes) do
    Enum.all?(
      [processes.connection, processes.stream_owner, processes.receiver],
      &(not Process.alive?(&1))
    ) and
      Port.info(processes.port) == nil and :ets.info(processes.admission) == :undefined and
      not File.exists?("/proc/#{processes.child}")
  end
end
