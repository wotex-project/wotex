Code.require_file("../support/software/exposed_bridge.exs", __DIR__)

defmodule Wotex.Matter.ExposedBridgeInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Error, SoftwareExposedBridge}
  alias Wotex.Matter.Native.ProcessCommand

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000
  @empty %{tag: :anonymous, type: :structure, value: []}
  @node %{fabric_id: 55, node_id: 780_001}
  @light Map.merge(@node, %{endpoint: 3, cluster: 6, member: 0})
  @sensor Map.merge(@node, %{endpoint: 4, cluster: 0x0402, member: 0})

  test "authenticated SDK requests traverse policy, public dispatch and approved reporting" do
    fixture = fixture()

    root = SoftwareExposedBridge.prepare!(fixture, "authenticated")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, owner} = SoftwareExposedBridge.start_link(parent: self(), fixture: fixture, root: root)
    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)
    {:ok, session} = Matter.connect(SoftwareExposedBridge.controller_options(fixture, root))

    try do
      assert {:ok, %{case: :established, node_id: 780_001}} =
               Matter.commission_on_network(session, %{
                 node_id: 780_001,
                 setup_pin: 20_202_021,
                 discriminator: 3840,
                 timeout: 15_000
               })

      assert_read(session, @light, :boolean, false)
      assert_policy(:read, 3, 6, 0)
      assert_receive {:bridge_handler, _, :readproperty, "value", context}, 1000
      assert_receive {:bridge_approved, request_id, {:ok, :applied}}, 1000
      assert context.request_id == request_id
      assert context.metadata.matter_bridge.request.thing == <<0, 1>>
      assert_read(session, @sensor, :i16, 2100)
      assert_policy(:read, 4, 0x0402, 0)
      flush_receipts()

      assert :ok = SoftwareExposedBridge.call(owner, {:allowed, false})

      assert {:error, %Error{code: :interaction_status, details: %{status: 0x7E}, effect: :none}} =
               Matter.read_attribute(session, @light)

      assert_policy(:read, 3, 6, 0)
      refute_receive {:bridge_handler, _, _, _, _}, 0
      assert :ok = SoftwareExposedBridge.call(owner, {:allowed, true})

      assert {:ok, %{status: 0}} =
               Matter.invoke_command(session, %{@light | member: 1}, @empty)

      assert_policy(:invoke, 3, 6, 1)
      assert_receive {:bridge_handler, _, :invokeaction, "set", _}, 1000
      assert_receive {:bridge_approved, _, {:ok, :applied}}, 1000
      assert_read(session, @light, :boolean, true)
      flush_receipts()

      duration = %{@light | member: 0x4001}

      assert {:error, %Error{code: :unsupported_schema, effect: :none}} =
               Matter.write_attribute(session, duration, %{tag: :anonymous, type: :u16, value: 7})

      refute_receive {:bridge_policy, _, _}, 0

      assert {:ok, subscription} =
               Matter.subscribe(session, %{
                 kind: :attribute,
                 paths: [@light],
                 min_interval_s: 0,
                 max_interval_s: 1,
                 resubscribe: false
               })

      report(subscription.reference, true)
      flush_receipts()
      assert {:ok, %{status: 0}} = Matter.invoke_command(session, @light, @empty)
      report(subscription.reference, false)
      assert :ok = Matter.unsubscribe(session, subscription)
      assert_read(session, @light, :boolean, false)
      flush_receipts()

      assert :ok = SoftwareExposedBridge.call(owner, {:delay, 1000})
      assert {:error, %Error{}} = Matter.read_attribute(session, @light)
      assert_receive {:bridge_handler, worker, :readproperty, "value", _}, 1000
      monitor = Process.monitor(worker)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
      refute_receive {:bridge_approved, _, _}, 0
      assert :ok = SoftwareExposedBridge.call(owner, {:delay, 0})
      assert_read(session, @light, :boolean, false)

      assert {:ok, %{pending: 0, observations: 0, probing: false}} =
               SoftwareExposedBridge.call(owner, :status)

      flush_receipts()

      acl = Map.merge(@node, %{endpoint: 0, cluster: 0x001F, member: 0})
      entries = [%{privilege: 5, auth_mode: 2, subjects: [0xFFFFFFEFFFFFFF04], targets: nil}]
      assert {:ok, value} = Matter.Descriptor.to_element(:attribute, acl, :write, entries)
      assert {:ok, %{status: 0}} = Matter.write_attribute(session, acl, value)

      assert {:error, %Error{code: :interaction_status, details: %{status: 0x7E}, effect: :none}} =
               Matter.read_attribute(session, @light)

      refute_receive {:bridge_policy, _, _}, 0
      refute_receive {:bridge_handler, _, _, _, _}, 0
    after
      assert :ok = Matter.disconnect(session)
      assert :ok = SoftwareExposedBridge.call(owner, :close)
    end
  end

  test "reopened native and controller stores retain the authenticated fabric and endpoint identity" do
    fixture = fixture()

    root = SoftwareExposedBridge.prepare!(fixture, "reopen")
    on_exit(fn -> File.rm_rf!(root) end)

    first =
      with_pair(fixture, root, false, fn owner, session ->
        assert {:ok, %{case: :established}} =
                 Matter.commission_on_network(
                   session,
                   %{node_id: 780_001, setup_pin: 20_202_021, discriminator: 3840, timeout: 15_000}
                 )

        assert {:ok, %{status: 0}} = Matter.invoke_command(session, %{@light | member: 1}, @empty)
        assert_policy(:invoke, 3, 6, 1)
        assert_receive {:bridge_handler, _, :invokeaction, "set", context}, 1000
        assert_receive {:bridge_approved, _, {:ok, :applied}}, 1000
        assert {:ok, %{generation: generation}} = SoftwareExposedBridge.call(owner, :status)
        {generation, context.metadata.matter_bridge.request.fabric_scope}
      end)

    SoftwareExposedBridge.reopen!(root)

    with_pair(fixture, root, true, fn owner, session ->
      assert_read(session, @light, :boolean, false)
      assert_policy(:read, 3, 6, 0)
      assert_receive {:bridge_handler, _, :readproperty, "value", context}, 1000
      assert_receive {:bridge_approved, _, {:ok, :applied}}, 1000
      assert {:ok, %{generation: generation}} = SoftwareExposedBridge.call(owner, :status)
      {old_generation, old_scope} = first
      assert generation != old_generation
      scope = context.metadata.matter_bridge.request.fabric_scope

      assert Map.take(scope, [:fabric_id, :bridge_node, :root_public_key, :noc_sha256]) ==
               Map.take(old_scope, [:fabric_id, :bridge_node, :root_public_key, :noc_sha256])

      assert_read(session, @sensor, :i16, 2100)
    end)

    assert {"controller operational key replaced for refusal probe\n", 0} =
             ProcessCommand.run(
               fixture["material"],
               ["replace-controller-key", Path.join(root, "controller")], stderr_to_stdout: true)

    assert {:error, %Error{effect: :none}} =
             Matter.connect(SoftwareExposedBridge.controller_options(fixture, root, true))

    assert {"controller operational key removed for refusal probe\n", 0} =
             ProcessCommand.run(
               fixture["material"],
               ["remove-controller-key", Path.join(root, "controller")],
               stderr_to_stdout: true
             )

    assert {:error, %Error{effect: :none}} =
             Matter.connect(SoftwareExposedBridge.controller_options(fixture, root, true))
  end

  test "independently built SDK controller writes all four finite child attributes" do
    fixture = fixture()

    root = SoftwareExposedBridge.prepare!(fixture, "independent")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, owner} = SoftwareExposedBridge.start_link(parent: self(), fixture: fixture, root: root)
    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)

    try do
      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, ["pairing", "onnetwork", "780001", "20202021"])

      assert status == 0, output
      assert output =~ "Commissioning complete for node ID"

      for {cluster, command, attribute, member, name, value} <- [
            {3, "identify", "identify-time", 0, "identify", 20},
            {6, "onoff", "on-time", 0x4001, "duration", 7},
            {6, "onoff", "off-wait-time", 0x4002, "wait", 8},
            {6, "onoff", "start-up-on-off", 0x4003, "startup", 2}
          ] do
        {output, status} =
          SoftwareExposedBridge.peer(fixture, root, [
            command,
            "write",
            attribute,
            Integer.to_string(value),
            "780001",
            "3"
          ])

        assert status == 0, output
        assert_policy(:write, 3, cluster, member)
        assert_receive {:bridge_handler, _, :writeproperty, ^name, context}, 1000
        expected = if member == 0x4003, do: {:nullable_enum8, value}, else: {:u16, value}
        assert context.metadata.matter_bridge.request.payload == expected
      end

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, [
          "onoff",
          "read",
          "start-up-on-off",
          "780001",
          "3"
        ])

      assert status == 0, output
      assert output =~ "StartUpOnOff: 2"
      assert_policy(:read, 3, 6, 0x4003)
      assert_receive {:bridge_handler, _, :readproperty, "startup", _}, 1000
      flush_receipts()
      assert :ok = SoftwareExposedBridge.call(owner, {:allowed, false})

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, [
          "onoff",
          "write",
          "start-up-on-off",
          "1",
          "780001",
          "3"
        ])

      assert status != 0, output
      assert_policy(:write, 3, 6, 0x4003)
      refute_receive {:bridge_handler, _, _, _, _}, 0
      assert :ok = SoftwareExposedBridge.call(owner, {:allowed, true})

      {output, status} =
        SoftwareExposedBridge.peer(fixture, root, [
          "onoff",
          "read",
          "start-up-on-off",
          "780001",
          "3"
        ])

      assert status == 0, output
      assert output =~ "StartUpOnOff: 2"
    after
      assert :ok = SoftwareExposedBridge.call(owner, :close)
    end
  end

  test "native process loss retires an authenticated mutation without claiming its physical effect" do
    fixture = fixture()

    root = SoftwareExposedBridge.prepare!(fixture, "native-loss")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, owner} = SoftwareExposedBridge.start_link(parent: self(), fixture: fixture, root: root)
    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)
    {:ok, session} = Matter.connect(SoftwareExposedBridge.controller_options(fixture, root))

    try do
      assert {:ok, %{case: :established}} =
               Matter.commission_on_network(
                 session,
                 %{node_id: 780_001, setup_pin: 20_202_021, discriminator: 3840, timeout: 15_000}
               )

      assert :ok = SoftwareExposedBridge.call(owner, {:delay, 1000})

      caller =
        Task.async(fn ->
          Matter.invoke_command(session, %{@light | member: 1}, @empty, timeout: 2000)
        end)

      assert_policy(:invoke, 3, 6, 1)
      assert_receive {:bridge_handler, worker, :invokeaction, "set", _}, 1000
      worker_monitor = Process.monitor(worker)
      connection = SoftwareExposedBridge.call(owner, :connection)
      {:links, links} = Process.info(connection, :links)
      [port] = Enum.filter(links, &is_port/1)
      {:os_pid, native} = Port.info(port, :os_pid)

      assert {_, 0} =
               ProcessCommand.run("/bin/kill", ["-KILL", Integer.to_string(native)],
                 stderr_to_stdout: true
               )

      assert_receive {:bridge_lost, ^connection, _, %Error{effect: :unknown}}, 1500
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 1000
      assert {:error, %Error{effect: :unknown}} = Task.await(caller, 3000)
      refute_receive {:bridge_approved, _, _}, 0

      assert {_, status} =
               ProcessCommand.run("/bin/kill", ["-0", Integer.to_string(native)],
                 stderr_to_stdout: true
               )

      assert status != 0
    after
      assert :ok = Matter.disconnect(session)
    end
  end

  defp fixture do
    path = System.fetch_env!("WOTEX_MATTER_EXPOSED_BRIDGE_FIXTURE")
    Jason.decode!(File.read!(path))
  end

  defp with_pair(fixture, root, reopen, operation) do
    {:ok, owner} = SoftwareExposedBridge.start_link(parent: self(), fixture: fixture, root: root)
    on_exit(fn -> if Process.alive?(owner), do: GenServer.stop(owner) end)
    {:ok, session} = Matter.connect(SoftwareExposedBridge.controller_options(fixture, root, reopen))

    try do
      operation.(owner, session)
    after
      assert :ok = Matter.disconnect(session)
      assert :ok = SoftwareExposedBridge.call(owner, :close)
    end
  end

  defp assert_read(session, address, type, value) do
    expected = %{tag: :anonymous, type: type, value: value}

    assert {:ok, %AttributeReport{value: ^expected, data_version: version}} =
             Matter.read_attribute(session, address)

    assert is_integer(version)
  end

  defp assert_policy(operation, endpoint, cluster, member) do
    assert_receive {:bridge_policy, request, context}, 1000
    assert request.operation == operation
    assert request.path == %{endpoint: endpoint, cluster: cluster, member: member}
    assert request.principal.auth_mode == :case
    assert request.principal.subject == 770_001
    assert request.fabric_scope.fabric_id == 55
    assert request.fabric_scope.bridge_node == 780_001
    assert byte_size(request.fabric_scope.root_public_key) == 65
    assert byte_size(request.fabric_scope.noc_sha256) == 32
    assert context.metadata.matter_bridge.request == request
    assert is_integer(context.deadline)
  end

  defp report(reference, value) do
    expected = %{tag: :anonymous, type: :boolean, value: value}
    assert_receive {:wotex_matter, ^reference, {:ok, ^expected, metadata}}, 3000
    assert metadata.kind == :attribute
  end

  defp flush_receipts do
    receive do
      {:bridge_policy, _, _} -> flush_receipts()
      {:bridge_handler, _, _, _, _} -> flush_receipts()
      {:bridge_approved, _, _} -> flush_receipts()
    after
      0 -> :ok
    end
  end
end
