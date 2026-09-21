Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeAclInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter
  alias Wotex.Matter.{AttributeReport, Descriptor, Error, Native, SoftwareScenarios, TLV}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 180_000

  test "WMA-S05 commissions a peer and preserves a nonempty ACL across write read and denial" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_ACL_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    SoftwareScenarios.with_peer(fixture, fn ->
      controller = Map.fetch!(fixture, "controller")
      controller_node = Map.fetch!(controller, "controller_node_id")

      options = [
        client: Native,
        executable: Map.fetch!(controller, "executable"),
        executable_sha256: digest(Map.fetch!(controller, "executable")),
        lifecycle: :persistent,
        storage_path: Map.fetch!(controller, "storage_path"),
        storage_mode: :create_new,
        authority: :generate_root,
        vendor_id: Map.fetch!(controller, "vendor_id"),
        fabric_id: Map.fetch!(controller, "fabric_id"),
        controller_node_id: controller_node,
        paa_trust_store: Map.fetch!(controller, "paa_trust_store"),
        timeout: 60_000
      ]

      node = Map.fetch!(fixture, "node_id")

      address = %{
        fabric_id: options[:fabric_id],
        node_id: node,
        endpoint: 0,
        cluster: 31,
        member: 0
      }

      assert {:ok, session} = Matter.connect(options)
      owner = session.handle.pid
      monitor = Process.monitor(owner)

      try do
        assert {:ok, %{case: :established, node_id: ^node}} =
                 Matter.commission_on_network(session, %{
                   node_id: node,
                   setup_pin: Map.fetch!(fixture, "setup_pin"),
                   discriminator: Map.fetch!(fixture, "discriminator"),
                   timeout: 60_000
                 })

        entries = [
          %{privilege: 5, auth_mode: 2, subjects: [controller_node], targets: nil},
          %{privilege: 1, auth_mode: 2, subjects: [0xFFFFFFEFFFFFFF02], targets: nil},
          %{
            privilege: 1,
            auth_mode: 2,
            subjects: [0xFFFFFFEFFFFFFF03],
            targets: [%{cluster: 31, endpoint: 0, device_type: nil}]
          }
        ]

        assert {:ok, value} = Descriptor.to_element(:attribute, address, :write, entries)
        assert {:ok, bytes} = TLV.encode([value])
        assert byte_size(bytes) > 64
        assert {:ok, %{status: 0}} = Matter.write_attribute(session, address, value)
        assert {:ok, %AttributeReport{value: returned}} = Matter.read_attribute(session, address)
        assert {:ok, actual} = Descriptor.from_element(:attribute, address, :read, returned)
        assert Enum.map(actual, &Map.delete(&1, :fabric_index)) == entries
        assert Enum.all?(actual, &(&1.fabric_index in 1..254))

        denied = [%{hd(entries) | subjects: [0xFFFFFFEFFFFFFF04]}]
        assert {:ok, denied_value} = Descriptor.to_element(:attribute, address, :write, denied)
        assert {:ok, %{status: 0}} = Matter.write_attribute(session, address, denied_value)

        read_result = Matter.read_attribute(session, address)

        assert {:error, %Error{} = error} = read_result
        assert error.code == :interaction_status
        assert error.details == %{status: 0x7E}
        assert error.effect == :none
      after
        assert :ok = Matter.disconnect(session)
        assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
      end
    end)
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
end
