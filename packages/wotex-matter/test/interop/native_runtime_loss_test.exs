defmodule Wotex.Matter.NativeRuntimeLossInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Address, Error, Native, RuntimeRelay}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000

  test "WMA-B03 native connection and child loss close the real Runtime route once" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_RUNTIME_LOSS_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = Map.fetch!(fixture, "controller")

    config =
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

    assert {:ok, address} =
             Address.new(%{
               fabric_id: config[:fabric_id],
               node_id: Map.fetch!(fixture, "node_id"),
               endpoint: Map.fetch!(fixture, "endpoint"),
               cluster: 6,
               member: 0
             })

    observations =
      for mode <- [:connection, :native_child] do
        request_id = Atom.to_string(mode)

        assert {:ok, relay} =
                 RuntimeRelay.start(
                   self(),
                   request_id,
                   :observeproperty,
                   :attribute,
                   address,
                   config,
                   [min_interval_s: 0, max_interval_s: 10, max_queue_length: 64],
                   10_000
                 )

        state = :sys.get_state(relay.pid)
        connection = state.session.handle.pid
        port = :sys.get_state(connection).port
        {:os_pid, child} = Port.info(port, :os_pid)
        relay_monitor = Process.monitor(relay.pid)
        connection_monitor = Process.monitor(connection)

        try do
          assert_receive {:wotex_transport_frame, frame}, 10_000
          assert :sys.get_state(connection).report_ledger.acknowledged_sequence == 0
          started = System.monotonic_time(:millisecond)

          case mode do
            :connection ->
              Process.exit(connection, :kill)

            :native_child ->
              assert {_, 0} =
                       Wotex.Matter.Native.ProcessCommand.run("/bin/kill", [
                         "-KILL",
                         to_string(child)
                       ])
          end

          assert_receive {:wotex_transport, {:error, %Error{code: :transport_closed}}}, 1_000
          assert_receive {:wotex_transport_status, :session_lost}, 1_000
          assert_receive {:DOWN, ^relay_monitor, :process, _, :normal}, 1_000
          assert_receive {:DOWN, ^connection_monitor, :process, _, _}, 1_000
          assert child_stopped?(child, started + 1_000)
          assert Port.info(port) == nil
          elapsed = System.monotonic_time(:millisecond) - started
          assert elapsed <= 1_000

          assert :ignore =
                   RuntimeRelay.decode(frame, request_id, :observeproperty, :attribute, address)

          refute_receive {:wotex_transport, {:error, _}}, 20
          refute_receive {:wotex_transport_status, _}, 20
          refute_receive {:wotex_transport_frame, _}, 20
          assert :ok = RuntimeRelay.close(relay)
          %{mode: mode, terminal_count: 1, cleanup_ms: elapsed, owned_processes_after_grace: 0}
        after
          RuntimeRelay.close(relay)
        end
      end

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
  end

  defp child_stopped?(pid, deadline) do
    case Wotex.Matter.Native.ProcessCommand.run("/bin/kill", ["-0", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          child_stopped?(pid, deadline)
        else
          false
        end

      {_, _} ->
        true
    end
  end
end
