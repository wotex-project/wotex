Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeBridgeInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.SoftwareScenarios
  alias Wotex.Matter.{AttributeReport, EventReport, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 180_000

  test "WMA-N03 discovers a bridge and preserves reachability event history and cancellation" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_BRIDGE_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    result =
      SoftwareScenarios.with_peer(fixture, fn ->
        controller = Map.fetch!(fixture, "controller")

        options =
          [
            client: Native,
            lifecycle: :persistent,
            storage_mode: :create_new,
            authority: :generate_root,
            timeout: 60_000
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

        node = %{fabric_id: options[:fabric_id], node_id: Map.fetch!(fixture, "node_id")}
        assert {:ok, session} = Matter.connect(options)
        owner = session.handle.pid
        monitor = Process.monitor(owner)
        {:links, links} = Process.info(owner, :links)
        [port] = Enum.filter(links, &is_port/1)
        {:os_pid, child} = Port.info(port, :os_pid)

        observation =
          try do
            assert {:ok, %{case: :established, node_id: commissioned}} =
                     Matter.commission_on_network(session, %{
                       node_id: node.node_id,
                       setup_pin: Map.fetch!(fixture, "setup_pin"),
                       discriminator: Map.fetch!(fixture, "discriminator"),
                       timeout: 60_000
                     })

            assert commissioned == node.node_id
            assert {:ok, catalogue} = Matter.discover_endpoints(session, node)

            candidates =
              Enum.filter(catalogue.endpoints, fn entry ->
                match?({:ok, _}, entry.server_clusters) and
                  Enum.all?([0x0039, 0x0402], &(&1 in elem(entry.server_clusters, 1).value))
              end)

            assert candidates != []
            endpoint = Enum.min_by(candidates, & &1.endpoint).endpoint
            attribute = Map.merge(node, %{endpoint: endpoint, cluster: 0x0039, member: 0x0011})
            event = %{attribute | member: 3}
            assert_value(session, attribute, true)

            assert {:ok, subscription} =
                     Matter.subscribe(session, %{
                       kind: :event,
                       paths: [event],
                       min_interval_s: 0,
                       max_interval_s: 1,
                       resubscribe: false
                     })

            discard_initial(subscription.reference)

            control(fixture, false)
            first = report(subscription.reference, false, -1)
            assert_value(session, attribute, false)
            control(fixture, true)
            second = report(subscription.reference, true, first.event_number)
            assert_value(session, attribute, true)
            assert second.report_id > first.report_id
            assert first.path == second.path
            assert first.timestamp.kind in [:epoch, :system]
            assert second.timestamp.kind == first.timestamp.kind
            assert second.timestamp.value >= first.timestamp.value
            assert is_integer(first.priority)

            assert {:ok, history} =
                     Matter.read_events(session, [event], min_event_number: first.event_number)

            reports = Enum.map(history, fn %{result: {:ok, %EventReport{} = report}} -> report end)
            assert Enum.map(reports, & &1.event_number) == [first.event_number, second.event_number]
            assert Enum.map(reports, & &1.value) == [event_value(false), event_value(true)]
            assert Enum.map(reports, & &1.timestamp) == [first.timestamp, second.timestamp]

            assert {:ok, []} =
                     Matter.read_events(session, [event], min_event_number: second.event_number + 1)

            assert :ok = Matter.unsubscribe(session, subscription)
            reference = subscription.reference
            control(fixture, false)
            assert eventually_value(session, attribute, false, 20)
            refute_receive {:wotex_matter, ^reference, _}, 1_100

            %{
              status: "passed",
              endpoint: endpoint,
              event_numbers: [first.event_number, second.event_number]
            }
          after
            assert :ok = Matter.disconnect(session)
            assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
            assert child_stopped?(child, 100)
          end

        observation
      end)

    File.write!(Map.fetch!(fixture, "result_path"), Jason.encode!(result), [:exclusive])
  end

  defp event_value(value),
    do: %{
      tag: :anonymous,
      type: :structure,
      value: [%{tag: {:context, 0}, type: :boolean, value: value}]
    }

  defp control(fixture, reachable) do
    command = Jason.encode!(%{"Name" => "WotexSetReachable", "Reachable" => reachable}) <> "\n"
    task = Task.async(fn -> File.write!(Map.fetch!(fixture, "control_path"), command) end)
    assert {:ok, :ok} = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)
  end

  defp report(reference, value, minimum) do
    expected = event_value(value)

    assert_receive {:wotex_matter, ^reference, {:ok, ^expected, %{event_number: number} = metadata}}
                   when number > minimum,
                   15_000

    metadata
  end

  defp discard_initial(reference, remaining \\ 32)
  defp discard_initial(_, 0), do: flunk("initial event history exceeds fixture limit")

  defp discard_initial(reference, remaining) do
    receive do
      {:wotex_matter, ^reference, {:ok, _, _}} -> discard_initial(reference, remaining - 1)
    after
      100 -> :ok
    end
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, remaining) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, remaining - 1)

      {_, _} ->
        true
    end
  end

  defp assert_value(session, path, value) do
    assert {:ok, %AttributeReport{value: %{type: :boolean, value: ^value}}} =
             Matter.read_attribute(session, path)
  end

  defp eventually_value(_, _, _, 0), do: false

  defp eventually_value(session, path, value, remaining) do
    case Matter.read_attribute(session, path, timeout: 1_000) do
      {:ok, %AttributeReport{value: %{type: :boolean, value: ^value}}} ->
        true

      {:ok, %AttributeReport{}} ->
        Process.sleep(20)
        eventually_value(session, path, value, remaining - 1)

      result ->
        flunk("fixture read failed: #{inspect(result)}")
    end
  end
end
