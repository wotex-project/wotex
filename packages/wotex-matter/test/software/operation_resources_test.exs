Code.require_file("../support/software/resources.exs", __DIR__)
Code.require_file("../support/software/scenarios.exs", __DIR__)

defmodule Wotex.Matter.NativeOperationResourcesTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Matter

  alias Wotex.Matter.{
    AttributeReport,
    Descriptor,
    Native,
    OnboardingMaterial,
    SoftwareResources,
    SoftwareScenarios
  }

  @moduletag :software
  @moduletag :interop
  @moduletag timeout: 180_000
  @empty %{tag: :anonymous, type: :structure, value: []}

  test "WMA-V13 commissioning, writes, commands and windows release their actual native owners" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_OPERATION_RESOURCES_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    result =
      SoftwareScenarios.with_peer(fixture, fn ->
        SoftwareResources.with_probe(fixture["resource_directory"], fn probe ->
          controller = fixture["controller"]

          options =
            [
              client: Native,
              lifecycle: :persistent,
              storage_mode: :create_new,
              authority: :generate_root,
              timeout: 60_000
            ] ++
              Enum.map(
                ~w(executable storage_path vendor_id fabric_id controller_node_id paa_trust_store)a,
                &{&1, Map.fetch!(controller, Atom.to_string(&1))}
              )

          assert {:ok, session} = Matter.connect(options)
          owner = session.handle.pid
          monitor = Process.monitor(owner)
          port = :sys.get_state(owner).port
          {:os_pid, child} = Port.info(port, :os_pid)

          observations =
            try do
              assert {:ok, %{case: :established}} =
                       Matter.commission_on_network(session, %{
                         node_id: fixture["node_id"],
                         setup_pin: fixture["setup_pin"],
                         discriminator: fixture["discriminator"],
                         timeout: 60_000
                       })

              commissioned = SoftwareResources.quiescent!(probe)
              assert commissioned["objects"]["commissioning"]["acquired"] == 1

              address = %{
                fabric_id: options[:fabric_id],
                node_id: fixture["node_id"],
                endpoint: fixture["endpoint"],
                cluster: 6,
                member: 0
              }

              assert {:ok, %AttributeReport{value: %{type: :boolean, value: false}}} =
                       Matter.read_attribute(session, address)

              baseline = SoftwareResources.quiescent!(probe)

              assert {:ok, %{status: 0}} =
                       Matter.invoke_command(session, %{address | member: 1}, @empty)

              assert {:ok, %AttributeReport{value: %{type: :boolean, value: true}}} =
                       Matter.read_attribute(session, address)

              invoked = SoftwareResources.quiescent!(probe, baseline)
              assert invoked["objects"]["command_sender"]["acquired"] == 1

              acl = %{address | endpoint: 0, cluster: 31, member: 0}

              entries = [
                %{
                  privilege: 5,
                  auth_mode: 2,
                  subjects: [controller["controller_node_id"]],
                  targets: nil
                }
              ]

              assert {:ok, value} = Descriptor.to_element(:attribute, acl, :write, entries)
              assert {:ok, %{status: 0}} = Matter.write_attribute(session, acl, value)
              assert {:ok, %AttributeReport{value: returned}} = Matter.read_attribute(session, acl)
              assert {:ok, actual} = Descriptor.from_element(:attribute, acl, :read, returned)
              assert Enum.map(actual, &Map.delete(&1, :fabric_index)) == entries
              written = SoftwareResources.quiescent!(probe, baseline)
              assert written["objects"]["write_client"]["acquired"] == 1

              assert {:ok, %OnboardingMaterial{expires_in_s: 180}} =
                       Matter.open_commissioning_window(session, %{
                         node_id: fixture["node_id"],
                         timeout_s: 180,
                         iteration_count: 1_000,
                         discriminator: 2620
                       })

              window = SoftwareResources.quiescent!(probe, baseline)
              assert window["objects"]["window"]["acquired"] == 1
              assert window["objects"]["window_opener"]["acquired"] == 1

              %{
                commissioned: commissioned,
                baseline: baseline,
                invoked: invoked,
                written: written,
                window: window
              }
            after
              assert :ok = Matter.disconnect(session)
              assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
              assert Port.info(port) == nil
              refute File.exists?("/proc/#{child}")
              SoftwareResources.final!(probe)
            end

          %{status: "passed", observations: observations, final: SoftwareResources.final!(probe)}
        end)
      end)

    File.write!(fixture["result_path"], Jason.encode!(result), [:exclusive])
  end
end
