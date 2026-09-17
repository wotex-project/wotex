defmodule Wotex.BACnet.DiscoveryWindowTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.{APDU, ObjectIdentifier}
  alias Wotex.BACnet.{DiscoveryWindow, Error}

  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)
  @source {{192, 0, 2, 20}, 47_808}
  @options %{destination: {{192, 0, 2, 255}, 47_808}, timeout_ms: 100, max_devices: 2}

  test "WBA-N04 WBA-F10 WBA-F11 pure collection projection uses fixture events and virtual time" do
    for vector <- @cases, vector["id"] in ["WBA-F10", "WBA-F11"] do
      input = vector["input"]
      config = input["discovery"]

      options = %{
        destination: source(config["destination"]),
        timeout_ms: config["timeout_ms"],
        max_devices: config["max_devices"]
      }

      assert {:ok, state} =
               DiscoveryWindow.new(
                 options,
                 input["low_limit"],
                 input["high_limit"],
                 0,
                 input["session_timeout_ms"]
               )

      state = Enum.reduce(input["events"], state, &event/2)
      expected = vector["expectation"]["value"]

      case state.outcome do
        {:ok, devices} ->
          assert Enum.map(devices, &projection/1) == expected["ok"]

        {:error, error} ->
          assert %{"code" => Atom.to_string(error.code), "effect" => Atom.to_string(error.effect)} ==
                   expected["error"]

          assert state.devices == %{}
      end

      # Collection projection only; listener, timer and custody evidence requires the native owner.
      assert state.destination == options.destination
    end
  end

  test "WBA-N04 admission preserves the configured window and rejects fewer than ten remaining ms" do
    assert {:error, %Error{code: :discovery_not_configured}} =
             DiscoveryWindow.new(nil, nil, nil, 0, 1000)

    assert {:error, %Error{code: :invalid_discovery_options}} =
             DiscoveryWindow.new(%{}, nil, nil, 0, 1000)

    assert {:error, %Error{code: :invalid_discovery_options}} =
             DiscoveryWindow.new(@options, nil, nil, :invalid, 1000)

    assert {:error, %Error{code: :invalid_discovery_range}} =
             DiscoveryWindow.new(@options, 10, nil, 0, 1000)

    assert {:error, %Error{code: :deadline_exceeded}} =
             DiscoveryWindow.new(@options, nil, nil, 0, 9)

    assert {:ok, state} = DiscoveryWindow.new(@options, 0, 10, 0, 1000)
    assert state.deadline == 1000
    assert state.expires == 100
    assert {:ok, 91} = DiscoveryWindow.admission(state, 90)
    assert {:error, %Error{code: :deadline_exceeded}} = DiscoveryWindow.admission(state, 91)
    assert {:ok, minimum} = DiscoveryWindow.new(@options, nil, nil, 0, 10)
    assert {:ok, 1} = DiscoveryWindow.admission(minimum, 0)
    assert DiscoveryWindow.finish(state, 99) == state
    assert %{outcome: {:ok, []}} = DiscoveryWindow.finish(state, 100)

    assert %{outcome: {:error, %Error{code: :deadline_exceeded}}} =
             DiscoveryWindow.finish(minimum, 10)

    assert %{outcome: {:error, %Error{code: :deadline_exceeded}}} =
             DiscoveryWindow.finish(state, 1000)
  end

  test "WBA-N04 all observations are sorted, distinct sources stay distinct and late traffic is discarded" do
    assert {:ok, state} = DiscoveryWindow.new(%{@options | max_devices: 4}, nil, nil, 0, 1000)
    second = {{192, 0, 2, 21}, 47_808}
    third = {{192, 0, 2, 20}, 47_809}
    state = DiscoveryWindow.accept(state, third, i_am(10), 1)
    state = DiscoveryWindow.accept(state, second, i_am(10), 2)
    state = DiscoveryWindow.accept(state, @source, i_am(11), 3)
    state = DiscoveryWindow.accept(state, @source, i_am(10), 4)
    assert DiscoveryWindow.accept(state, @source, i_am(10), 5) == state
    finished = DiscoveryWindow.accept(state, @source, i_am(1), 100)
    assert {:ok, devices} = finished.outcome

    assert Enum.map(devices, &{&1.source, &1.instance}) ==
             [{@source, 10}, {@source, 11}, {third, 10}, {second, 10}]

    assert DiscoveryWindow.accept(finished, @source, i_am(1), 101) == finished
    assert DiscoveryWindow.finish(finished, 1001) == finished
  end

  test "WBA-N04 conflicting fields invalidate the whole result instead of selecting a route" do
    for {field, replacement} <- [
          {1, {:unsigned_integer, 50}},
          {2, {:enumerated, 0}},
          {3, {:unsigned_integer, 1}}
        ] do
      assert {:ok, state} = DiscoveryWindow.new(@options, nil, nil, 0, 1000)
      apdu = i_am(10)
      state = DiscoveryWindow.accept(state, @source, apdu, 1)
      changed = %{apdu | parameters: List.replace_at(apdu.parameters, field, replacement)}

      failed = DiscoveryWindow.accept(state, @source, changed, 2)
      assert failed.devices == %{}
      assert {:error, %Error{code: :conflicting_discovery_response}} = failed.outcome
    end
  end

  test "WBA-N04 malformed and out of range reports are ignored with a bounded counter" do
    assert {:ok, state} = DiscoveryWindow.new(@options, 1, 10, 0, 1000)
    state = DiscoveryWindow.accept(state, @source, :malformed, 1)
    state = DiscoveryWindow.accept(state, @source, i_am(0), 2)
    state = DiscoveryWindow.accept(state, @source, i_am(11), 3)
    assert state.ignored == 3
    assert state.devices == %{}
    saturated = %{state | ignored: 4_294_967_295}
    assert DiscoveryWindow.accept(saturated, @source, :malformed, 4) == saturated
    state = DiscoveryWindow.accept(state, @source, i_am(1), 5)
    state = DiscoveryWindow.accept(state, @source, i_am(10), 6)
    assert map_size(state.devices) == 2
  end

  defp event(%{"event" => "advance_clock", "at_ms" => now}, state),
    do: DiscoveryWindow.finish(state, now)

  defp event(%{"event" => "i_am", "at_ms" => now, "device" => device}, state) do
    assert device["segmentation"] == "no_segmentation"
    apdu = i_am(device["instance"], device["max_apdu"], device["vendor_id"])
    DiscoveryWindow.accept(state, source(device["source"]), apdu, now)
  end

  defp projection(device) do
    {ip, port} = device.source

    %{
      "source" => [Tuple.to_list(ip), port],
      "instance" => device.instance,
      "max_apdu" => device.max_apdu,
      "segmentation" => Atom.to_string(device.segmentation),
      "vendor_id" => device.vendor_id
    }
  end

  defp source([octets, port]), do: {List.to_tuple(octets), port}

  defp i_am(instance, max_apdu \\ 1476, vendor_id \\ 260) do
    %APDU.UnconfirmedServiceRequest{
      service: :i_am,
      parameters: [
        {:object_identifier, %ObjectIdentifier{type: :device, instance: instance}},
        {:unsigned_integer, max_apdu},
        {:enumerated, 3},
        {:unsigned_integer, vendor_id}
      ]
    }
  end
end
