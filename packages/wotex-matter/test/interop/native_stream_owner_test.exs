defmodule Wotex.Matter.NativeStreamOwnerInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000

  test "ordinary SDK reports retain credit across stream suspension and release owned processes" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_STREAM_OWNER_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

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

    path = %{
      fabric_id: options[:fabric_id],
      node_id: Map.fetch!(fixture, "node_id"),
      endpoint: Map.fetch!(fixture, "endpoint"),
      cluster: 6,
      member: 0
    }

    for mode <- [:resume, :stream_loss, :stalled_cancellation, :connection_loss] do
      assert {:ok, session} = Matter.connect(options)
      connection = session.handle.pid
      port = :sys.get_state(connection).port
      {:os_pid, child} = Port.info(port, :os_pid)

      try do
        assert {:ok, subscription} =
                 Matter.subscribe(session, %{
                   kind: :attribute,
                   paths: [path],
                   min_interval_s: 0,
                   max_interval_s: 10,
                   resubscribe: false
                 })

        reference = subscription.reference

        assert_receive {:wotex_matter, ^reference, {:ok, %{type: :boolean, value: initial}, _}},
                       10_000

        owner = :sys.get_state(connection).subscriptions[reference].stream_owner
        assert is_pid(owner) and owner != connection
        monitor = Process.monitor(owner)
        assert eventually(fn -> :sys.get_state(connection).report_ledger.pending == %{} end, 1_000)
        acknowledged = :sys.get_state(connection).report_ledger.acknowledged_sequence
        :sys.suspend(owner)

        case mode do
          :resume ->
            command = %{path | member: 2}

            assert {:ok, %{status: 0}} =
                     Matter.invoke_command(session, command, %{
                       tag: :anonymous,
                       type: :structure,
                       value: []
                     })

            assert eventually(
                     fn -> map_size(:sys.get_state(connection).report_ledger.pending) > 0 end,
                     5_000
                   )

            refute_receive {:wotex_matter, ^reference, _}, 50
            assert :sys.get_state(connection).report_ledger.acknowledged_sequence == acknowledged
            :sys.resume(owner)
            changed = not initial

            assert_receive {:wotex_matter, ^reference,
                            {:ok, %{type: :boolean, value: ^changed}, _}},
                           1_000

            assert eventually(
                     fn -> :sys.get_state(connection).report_ledger.pending == %{} end,
                     1_000
                   )

            assert :ok = Matter.unsubscribe(session, subscription)
            assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1_000

          :stream_loss ->
            assert {_, 0} =
                     Wotex.Matter.Native.ProcessCommand.run("/bin/kill", [
                       "-STOP",
                       Integer.to_string(child)
                     ])

            Process.exit(owner, :kill)
            assert_receive {:wotex_matter, ^reference, {:error, %Error{code: :owner_closed}}}, 1_000
            assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1_000
            pending = :sys.get_state(connection)
            assert pending.subscriptions[reference].status == :closing
            assert Map.values(pending.internal_requests) == [reference]
            cancellation = Task.async(fn -> Matter.unsubscribe(session, subscription) end)

            try do
              assert Task.yield(cancellation, 50) == nil

              assert {_, 0} =
                       Wotex.Matter.Native.ProcessCommand.run("/bin/kill", [
                         "-CONT",
                         Integer.to_string(child)
                       ])

              assert :ok = Task.await(cancellation, 1_000)
              assert :sys.get_state(connection).next_id == pending.next_id
            after
              Task.shutdown(cancellation, :brutal_kill)
            end

            assert eventually(fn -> :sys.get_state(connection).subscriptions == %{} end, 1_000)
            assert {:ok, %{"status" => "ready"}} = Native.health(session.handle)

          :connection_loss ->
            started = System.monotonic_time(:millisecond)
            Process.exit(connection, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1_000
            assert eventually(fn -> not File.exists?("/proc/#{child}") end, 1_000)
            assert Port.info(port) == nil
            assert System.monotonic_time(:millisecond) - started <= 1_000

          :stalled_cancellation ->
            connection_monitor = Process.monitor(connection)

            assert {_, 0} =
                     Wotex.Matter.Native.ProcessCommand.run("/bin/kill", [
                       "-STOP",
                       Integer.to_string(child)
                     ])

            started = System.monotonic_time(:millisecond)
            Process.exit(owner, :kill)
            assert_receive {:wotex_matter, ^reference, {:error, %Error{code: :owner_closed}}}, 1_000
            assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 1_000
            assert_receive {:DOWN, ^connection_monitor, :process, ^connection, :normal}, 1_000
            assert eventually(fn -> not File.exists?("/proc/#{child}") end, 1_000)
            assert Port.info(port) == nil
            assert System.monotonic_time(:millisecond) - started <= 1_000
        end

        refute Process.alive?(owner)
        refute_receive {:wotex_matter, ^reference, _}, 30
      after
        Matter.disconnect(session)
      end
    end

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{
        status: "passed",
        modes: ["resume", "stream_loss", "stalled_cancellation", "connection_loss"],
        joined_native_cancellation: true,
        stalled_native_cancellation_reaped: true,
        owned_stream_owners_after_cleanup: 0
      }),
      [:exclusive]
    )
  end

  defp eventually(predicate, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(predicate, deadline)
  end

  defp poll(predicate, deadline) do
    if predicate.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(5)
        poll(predicate, deadline)
      else
        false
      end
    end
  end
end
