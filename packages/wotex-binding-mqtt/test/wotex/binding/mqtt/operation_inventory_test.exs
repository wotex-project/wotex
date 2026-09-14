defmodule Wotex.Binding.MQTT.OperationInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Command, Error, Mapping}
  alias Wotex.Binding.MQTT.Test.RequestFactory
  alias Wotex.Runtime.BindingProfile

  @rows [
    %{
      operation: :readproperty,
      type: :property,
      packet: :subscribe,
      target: "mqv:filter",
      retain: true
    },
    %{
      operation: :writeproperty,
      type: :property,
      packet: :publish,
      target: "mqv:topic",
      retain: false
    },
    %{
      operation: :invokeaction,
      type: :action,
      packet: :publish,
      target: "mqv:topic",
      retain: false
    },
    %{
      operation: :observeproperty,
      type: :property,
      packet: :subscribe,
      target: "mqv:filter",
      retain: false
    },
    %{
      operation: :subscribeevent,
      type: :event,
      packet: :subscribe,
      target: "mqv:filter",
      retain: false
    },
    %{
      operation: :unobserveproperty,
      type: :property,
      packet: :unsubscribe,
      target: "mqv:filter",
      retain: false
    },
    %{
      operation: :unsubscribeevent,
      type: :event,
      packet: :unsubscribe,
      target: "mqv:filter",
      retain: false
    }
  ]

  @source_revision "715b40d756e25ef87bcef806e76e8db013b7343c"
  @source_files ~w[
    bindings/protocols/mqtt/context.jsonld
    bindings/protocols/mqtt/index.html
    bindings/protocols/mqtt/index.template.html
    bindings/protocols/mqtt/mapping.ttl
    bindings/protocols/mqtt/mqtt.schema.json
    bindings/protocols/mqtt/ontology.ttl
    bindings/protocols/mqtt/template.sparql
  ]

  test "all seven rows preserve exact default packet, target, qos, retain, and limit values" do
    for row <- @rows do
      assert Mapping.default_control_packet(row.operation) == {:ok, row.packet}
      assert {:ok, command} = Mapping.command(request(row), 4_096)
      assert Command.operation(command) == row.operation
      assert Command.packet(command) == row.packet
      assert Command.retain?(command) == row.retain
      assert Command.content_type(command) == "application/json"
      assert Command.max_payload_bytes(command) == 4_096

      if row.packet == :publish do
        assert Command.topic(command) == target_value(row)
        assert Command.filters(command) == []
      else
        assert Command.topic(command) == nil
        assert Command.filters(command) == [target_value(row)]
      end

      expected_qos = if row.packet == :unsubscribe, do: nil, else: 0
      assert Command.qos(command) == expected_qos
    end
  end

  test "all seven rows accept only their matching explicit packet and normalize qos" do
    for row <- @rows do
      overrides = %{
        "mqv:controlPacket" => Atom.to_string(row.packet),
        "mqv:qos" => "2",
        "mqv:retain" => true
      }

      assert {:ok, command} = Mapping.command(request(row, overrides), 512)
      assert Command.packet(command) == row.packet
      assert Command.retain?(command)
      assert Command.qos(command) == if(row.packet == :unsubscribe, do: nil, else: 2)
      assert Command.max_payload_bytes(command) == 512
    end
  end

  test "every supported row rejects packet conflicts and wrong or mixed target terms" do
    for row <- @rows do
      conflicting_packet = if row.packet == :subscribe, do: "publish", else: "subscribe"

      assert_error(
        Mapping.command(request(row, %{"mqv:controlPacket" => conflicting_packet}), 100),
        :control_packet_mismatch
      )

      wrong_target = if row.target == "mqv:topic", do: "mqv:filter", else: "mqv:topic"

      without_target =
        row
        |> form()
        |> Map.delete(row.target)
        |> Map.put(wrong_target, "wrong/target")

      assert_error(
        Mapping.command(request(row, without_target, :replace), 100),
        :missing_mqtt_target
      )

      mixed =
        row
        |> form()
        |> Map.put(wrong_target, "wrong/target")

      assert_error(Mapping.command(request(row, mixed, :replace), 100), :mixed_mqtt_targets)
    end
  end

  test "only the exact mqv-prefixed vocabulary keys affect mapping" do
    write = Enum.find(@rows, &(&1.operation == :writeproperty))
    read = Enum.find(@rows, &(&1.operation == :readproperty))

    unprefixed_target =
      write
      |> form()
      |> Map.delete("mqv:topic")
      |> Map.put("topic", target_value(write))

    assert_error(
      Mapping.command(request(write, unprefixed_target, :replace), 100),
      :missing_mqtt_target
    )

    unprefixed_retain =
      read
      |> form()
      |> Map.delete("mqv:retain")
      |> Map.put("retain", true)

    assert_error(
      Mapping.command(request(read, unprefixed_retain, :replace), 100),
      :retained_read_required
    )

    assert {:ok, command} =
             Mapping.command(
               request(write, %{
                 "controlPacket" => "subscribe",
                 "qos" => "2",
                 "retain" => true
               }),
               100
             )

    assert Command.packet(command) == :publish
    assert Command.qos(command) == 0
    refute Command.retain?(command)
  end

  test "the Runtime profile contains exactly the seven rows and rejects every other operation" do
    profile = MQTT.profile()
    supported = MapSet.new(Enum.map(@rows, & &1.operation))
    runtime_operations = MapSet.new(Wotex.Runtime.operations())

    assert MapSet.filter(runtime_operations, &BindingProfile.supports_operation?(profile, &1)) ==
             supported

    for operation <- MapSet.difference(runtime_operations, supported) do
      refute BindingProfile.supports_operation?(profile, operation)
      assert_error(Mapping.default_control_packet(operation), :unsupported_operation)

      request =
        RequestFactory.request(operation,
          affordance_type: Wotex.Runtime.interaction_type(operation),
          form: %{
            "href" => "mqtt://broker.example",
            "op" => Atom.to_string(operation),
            "mqv:topic" => "unsupported/value"
          }
        )

      assert_error(Mapping.command(request, 100), :unsupported_operation)
    end
  end

  test "the inventory pins the dated upstream source revision and file digests" do
    manifest =
      "docs/provenance/mqtt-binding-source-manifest.json"
      |> File.read!()
      |> Jason.decode!()

    assert manifest["schema_version"] == "1.0.0"
    assert manifest["observed_at"] == "2026-09-02"
    assert manifest["repository"] == "https://github.com/w3c/wot-binding-templates"
    assert manifest["revision"] == @source_revision

    manifest_files =
      manifest["files"]
      |> Map.keys()
      |> Enum.sort()

    assert manifest_files == Enum.sort(@source_files)

    assert Enum.all?(manifest["files"], fn {_, digest} ->
             digest =~ ~r/\A[0-9a-f]{64}\z/
           end)
  end

  defp request(row, overrides \\ %{}, mode \\ :merge) do
    form = if mode == :replace, do: overrides, else: Map.merge(form(row), overrides)

    RequestFactory.request(row.operation,
      affordance_type: row.type,
      input: %{"value" => Atom.to_string(row.operation)},
      form: form
    )
  end

  defp form(row) do
    %{
      "href" => "mqtts://broker.example:8883",
      "op" => Atom.to_string(row.operation),
      row.target => target_value(row)
    }
    |> maybe_retain(row)
  end

  defp maybe_retain(form, %{retain: true}), do: Map.put(form, "mqv:retain", true)
  defp maybe_retain(form, _), do: form

  defp target_value(%{target: "mqv:topic", operation: operation}),
    do: "things/#{operation}/input"

  defp target_value(%{target: "mqv:filter", operation: operation}),
    do: "things/#{operation}/+"

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code}} = result
  end
end
