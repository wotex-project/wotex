Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeThermostatInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.SoftwareScenarios
  alias Wotex.Matter.{AttributeReport, Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 180_000

  test "WMA-N03 preserves thermostat values null and stale DataVersion status through the SDK" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_THERMOSTAT_FIXTURE")
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

            endpoints =
              Enum.filter(catalogue.endpoints, fn entry ->
                match?({:ok, _}, entry.server_clusters) and
                  Enum.all?([0x0201, 0x0402], &(&1 in elem(entry.server_clusters, 1).value))
              end)

            assert length(endpoints) == 1
            assert 0xFFF1FC05 in elem(hd(endpoints).server_clusters, 1).value
            endpoint = hd(endpoints).endpoint
            temperature = Map.merge(node, %{endpoint: endpoint, cluster: 0x0201, member: 0})
            sensor = %{temperature | cluster: 0x0402}
            heating = %{temperature | member: 0x0012}
            mode = %{temperature | member: 0x001C}

            control(fixture, endpoint, 2150, nil)
            assert eventually_value(session, temperature, integer(2150), 20)
            assert_report(session, sensor, %{tag: :anonymous, type: :null, value: nil})

            assert {:ok, %{status: 0}} = Matter.write_attribute(session, heating, integer(2000))
            version = assert_report(session, heating, integer(2000)).data_version

            assert {:ok, %{status: 0}} =
                     Matter.write_attribute(session, heating, integer(2050),
                       expected_data_version: version,
                       timed_request_timeout_ms: 1000
                     )

            updated = assert_report(session, heating, integer(2050)).data_version
            assert updated != version

            assert {:error, %Error{code: :interaction_status, details: %{status: 0x92}}} =
                     Matter.write_attribute(session, heating, integer(2100),
                       expected_data_version: version
                     )

            assert_report(session, heating, integer(2050))

            for value <- [0, 1, 3, 4] do
              element = %{tag: :anonymous, type: :u8, value: value}
              assert {:ok, %{status: 0}} = Matter.write_attribute(session, mode, element)
              assert_report(session, mode, element)
            end

            control(fixture, endpoint, 2200, 0)
            assert eventually_value(session, temperature, integer(2200), 20)
            assert_report(session, sensor, integer(0))

            %{
              status: "passed",
              endpoint: endpoint,
              initial_data_version: version,
              updated_data_version: updated,
              stale_status: 0x92
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

  defp integer(value), do: %{tag: :anonymous, type: :i16, value: value}

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

  defp control(fixture, endpoint, local, measured) do
    command =
      Jason.encode!(%{
        "Name" => "WotexSetTemperature",
        "EndpointId" => endpoint,
        "LocalTemperature" => local,
        "MeasuredValue" => measured
      }) <> "\n"

    task = Task.async(fn -> File.write!(Map.fetch!(fixture, "control_path"), command) end)
    assert {:ok, :ok} = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)
  end

  defp assert_report(session, path, value) do
    assert {:ok, %AttributeReport{value: ^value} = report} = Matter.read_attribute(session, path)
    assert is_integer(report.data_version)
    report
  end

  defp eventually_value(_, _, _, 0), do: false

  defp eventually_value(session, path, value, remaining) do
    case Matter.read_attribute(session, path, timeout: 1_000) do
      {:ok, %AttributeReport{value: ^value}} ->
        true

      {:ok, %AttributeReport{}} ->
        Process.sleep(20)
        eventually_value(session, path, value, remaining - 1)

      result ->
        flunk("fixture read failed: #{inspect(result)}")
    end
  end
end
