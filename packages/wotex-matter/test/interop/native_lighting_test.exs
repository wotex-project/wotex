Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeLightingInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter

  alias Wotex.Matter.{
    AttributeReport,
    Error,
    Native,
    RuntimeCredentials,
    SoftwareScenarios,
    TLV,
    Transport
  }

  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context, Result}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 180_000
  @empty %{tag: :anonymous, type: :structure, value: []}
  @off_value %{tag: :anonymous, type: :boolean, value: false}
  @on_value %{tag: :anonymous, type: :boolean, value: true}

  test "WMA-N03 discovers a light, preserves reports and reopens its commissioned fabric" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_LIGHTING_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    result =
      SoftwareScenarios.with_peer(fixture, fn ->
        options = options(fixture)
        assert native_ports(options[:executable]) == []
        node = %{fabric_id: options[:fabric_id], node_id: Map.fetch!(fixture, "node_id")}

        {address, report_ids} =
          with_session(options, fn session ->
            assert {:ok, %{case: :established, node_id: commissioned}} =
                     Matter.commission_on_network(session, %{
                       node_id: node.node_id,
                       setup_pin: Map.fetch!(fixture, "setup_pin"),
                       discriminator: Map.fetch!(fixture, "discriminator"),
                       timeout: 60_000
                     })

            assert commissioned == node.node_id
            assert {:ok, catalogue} = Matter.discover_endpoints(session, node)
            assert catalogue.consistency == :not_atomic

            endpoints =
              Enum.filter(catalogue.endpoints, fn entry ->
                match?({:ok, _}, entry.server_clusters) and
                  6 in elem(entry.server_clusters, 1).value
              end)

            assert length(endpoints) == 1
            address = Map.merge(node, %{endpoint: hd(endpoints).endpoint, cluster: 6, member: 0})
            assert_read(session, address, @off_value)
            assert {:ok, <<0x15, 0x18>>} = TLV.encode([@empty])

            assert {:error, %Error{code: :not_writable, effect: :none}} =
                     Matter.write_attribute(session, address, @on_value)

            assert {:ok, subscription} =
                     Matter.subscribe(session, %{
                       kind: :attribute,
                       paths: [address],
                       min_interval_s: 0,
                       max_interval_s: 10,
                       resubscribe: false
                     })

            first = report(subscription.reference, @off_value)
            invoke(session, address, 1)
            assert_read(session, address, @on_value)
            second = report(subscription.reference, @on_value)
            invoke(session, address, 0)
            assert_read(session, address, @off_value)
            third = report(subscription.reference, @off_value)

            assert first.path == second.path and second.path == third.path
            assert first.report_id < second.report_id and second.report_id < third.report_id
            assert first.data_version != third.data_version
            assert :ok = Matter.unsubscribe(session, subscription)
            assert :ok = Matter.unsubscribe(session, subscription)
            invoke(session, address, 1)
            assert_read(session, address, @on_value)
            reference = subscription.reference
            refute_receive {:wotex_matter, ^reference, _}, 1_100
            {address, Enum.map([first, second, third], & &1.report_id)}
          end)

        stored = Keyword.merge(options, storage_mode: :open_existing, authority: :stored)
        with_session(stored, &assert_read(&1, address, @on_value))
        consumed = consumed(stored, address)

        assert {:ok, %Result{payload: @on_value, metadata: metadata}} =
                 ConsumedThing.read_property(consumed, "on", context("read-on"))

        assert metadata.path == address

        assert {:ok, %Result{payload: nil, metadata: %{status: 0, response_path: nil}}} =
                 ConsumedThing.invoke_action(consumed, "off", @empty, context("invoke-off"))

        assert {:ok, %Result{payload: @off_value}} =
                 ConsumedThing.read_property(consumed, "on", context("read-off"))

        with_session(stored, &assert_read(&1, address, @off_value))
        assert native_ports(options[:executable]) == []

        %{
          status: "passed",
          address: address,
          report_ids: report_ids,
          owned_ports_after_cleanup: 0
        }
      end)

    File.write!(Map.fetch!(fixture, "result_path"), Jason.encode!(result), [:exclusive])
  end

  defp options(fixture) do
    controller = Map.fetch!(fixture, "controller")

    [
      client: Native,
      lifecycle: :persistent,
      storage_mode: :create_new,
      authority: :generate_root,
      timeout: 60_000
    ] ++
      Enum.map(
        [:executable, :storage_path, :vendor_id, :fabric_id, :controller_node_id, :paa_trust_store],
        &{&1, Map.fetch!(controller, Atom.to_string(&1))}
      )
  end

  defp with_session(options, function) do
    assert {:ok, session} = Matter.connect(options)
    owner = session.handle.pid
    monitor = Process.monitor(owner)
    [port] = native_ports(options[:executable])
    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      function.(session)
    after
      assert :ok = Matter.disconnect(session)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
      assert child_stopped?(child, 100)
    end
  end

  defp native_ports(executable) do
    Enum.filter(Port.list(), fn port ->
      Port.info(port, :name) == {:name, String.to_charlist(executable)}
    end)
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, remaining) do
    case Wotex.Matter.Native.ProcessCommand.run("kill", ["-0", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, remaining - 1)

      {_, _} ->
        true
    end
  end

  defp assert_read(session, address, value) do
    assert {:ok, %AttributeReport{value: ^value, data_version: version}} =
             Matter.read_attribute(session, address)

    assert is_integer(version)
  end

  defp invoke(session, address, command) do
    assert {:ok, %{path: nil, value: nil, status: 0}} =
             Matter.invoke_command(session, %{address | member: command}, @empty)
  end

  defp report(reference, value) do
    assert_receive {:wotex_matter, ^reference, {:ok, ^value, metadata}}, 15_000
    assert metadata.kind == :attribute
    metadata
  end

  defp consumed(options, address) do
    href = "matter://#{address.fabric_id}/#{address.node_id}/#{address.endpoint}/6/0"

    assert {:ok, td} =
             Wotex.ThingDescription.from_map(%{
               "@context" => "https://www.w3.org/2022/wot/td/v1.1",
               "id" => "urn:example:matter:native-lighting",
               "title" => "Native Matter lighting fixture",
               "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
               "security" => ["none"],
               "properties" => %{
                 "on" => %{
                   "readOnly" => true,
                   "forms" => [%{"href" => href, "op" => "readproperty"}]
                 }
               },
               "actions" => %{
                 "off" => %{"forms" => [%{"href" => href, "op" => "invokeaction"}]}
               }
             })

    assert {:ok, profile} = Matter.profile(:controller)
    transport = Keyword.put(options, :target, Integer.to_string(address.fabric_id))

    assert {:ok, consumed} =
             ConsumedThing.new(td,
               profiles: [profile],
               transports: %{BindingProfile.id(profile) => {Transport, transport}},
               credentials: {RuntimeCredentials, %{test_pid: self()}}
             )

    consumed
  end

  defp context(id) do
    assert {:ok, context} =
             Context.new(request_id: id, deadline: System.monotonic_time(:millisecond) + 60_000)

    context
  end
end
