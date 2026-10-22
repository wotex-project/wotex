defmodule WotexLabWorkbench.CanvasTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Island.Encoder
  alias WotexLabWorkbench.{Canvas, ThingReadings}

  test "freshness changes preserve the receipt and pause without fabricating a sample" do
    reading = %{
      thing: "thermostat",
      property: "temperature",
      value: -4.5,
      state: :live,
      received_ms: 1000,
      read_at: "2026-10-22T00:00:00Z"
    }

    readings = ThingReadings.put(%{}, reading)

    assert ThingReadings.get(ThingReadings.expire(readings, 16_000), "thermostat", "temperature").state ==
             :live

    stale = ThingReadings.get(ThingReadings.expire(readings, 16_001), "thermostat", "temperature")
    assert stale.state == :stale and stale.value == -4.5
    paused = ThingReadings.get(ThingReadings.pause(readings), "thermostat", "temperature")
    assert paused.state == :paused and paused.read_at == reading.read_at
    assert ThingReadings.get(readings, "thermostat", "other") == nil
    assert ThingReadings.get(%{"thermostat" => reading}, "thermostat", "temperature") == reading
  end

  test "only explicit reads populate a matching Property, never simulator state" do
    things = [thing("thermostat"), thing("meter"), thing("actuator")]
    props = Canvas.props(things, [], %{})
    assert {:ok, ^props} = Encoder.encode("canvas", props)
    assert length(props["edges"]) == 3
    assert Enum.all?(Enum.filter(props["nodes"], &(&1["kind"] == "thing")), &(&1["value"] == "—"))

    reading = %{
      thing: "thermostat",
      property: "temperature",
      value: 21.5,
      read_at: "2026-10-21T19:00:00Z"
    }

    updated = Canvas.props(things, [], %{"thermostat" => reading})
    node = Enum.find(updated["nodes"], &(&1["id"] == "thing-thermostat"))
    assert node["value"] == "21.5"
    assert node["unit"] == "°C"
    assert node["status"] == "Read"
    assert node["detail"] == "19:00:00"
    refute inspect(updated) =~ "999"

    readings = %{
      "thermostat" => reading,
      "meter" => %{thing: "meter", property: "power", value: 2500.0, read_at: reading.read_at}
    }

    retained = Canvas.props(things, [], readings)
    assert Enum.find(retained["nodes"], &(&1["id"] == "thing-thermostat"))["value"] == "21.5"
    assert Enum.find(retained["nodes"], &(&1["id"] == "thing-meter"))["value"] == "2500.0"

    wrong = Canvas.props(things, [], %{"thermostat" => %{reading | property: "other"}})
    assert Enum.all?(Enum.filter(wrong["nodes"], &(&1["kind"] == "thing")), &(&1["value"] == "—"))
  end

  test "inert entries keep unique stable identities and cannot create experiment wiring" do
    first = %{thing("registered") | id: "urn:test:one", title: nil, consumable: false}
    second = %{first | id: "urn:test:two", title: String.duplicate("字", 200)}
    props = Canvas.props([second, first], [], %{})
    assert props == Canvas.props([first, second], [], %{})
    assert props["edges"] == []
    assert Enum.all?(props["nodes"], &(&1["status"] == "Inert"))
    assert Canvas.id(first) != Canvas.id(second)
    assert {:ok, ^props} = Encoder.encode("canvas", props)
  end

  test "the closed graph refuses duplicate identities, unknown fields, bad coordinates and dangling edges" do
    props = Canvas.props([thing("thermostat"), thing("meter")], [], %{})
    node = hd(props["nodes"])

    for bad <- [
          Map.put(props, "nodes", [node, node]),
          put_in(props, ["nodes", Access.at(0), "x"], 20_001),
          put_in(props, ["nodes", Access.at(0), "kind"], "command"),
          put_in(props, ["nodes", Access.at(0), "title"], String.duplicate("a", 129)),
          put_in(props, ["nodes", Access.at(0), "private"], "not admitted"),
          put_in(props, ["nodes", Access.at(0), "operations"], ["dispatch"]),
          put_in(props, ["nodes", Access.at(0), "operations"], ["read", "read"]),
          put_in(props, ["edges", Access.at(0), "target"], "other-session-node")
        ] do
      assert {:error, :invalid_island_prop} = Encoder.encode("canvas", bad)
    end
  end

  test "projection is finite and reports actual smart-room run state" do
    things =
      for index <- 1..100, do: %{thing("registered") | id: "urn:test:#{index}", consumable: false}

    assert length(Canvas.props(things, [], %{})["nodes"]) == 31
    run = %{experiment: "smart_room", id: "run-8", status: :awaiting_approval}
    props = Canvas.props([thing("thermostat")], [run], %{})
    assert hd(props["nodes"])["status"] == "awaiting_approval"
    assert hd(props["nodes"])["detail"] == "run-8"

    assert Canvas.props([], [], %{}) == %{
             "label" => "Connected Things",
             "nodes" => [],
             "edges" => []
           }
  end

  defp thing(key),
    do: %{
      key: key,
      id: "urn:test:#{key}",
      title: key,
      consumable: true,
      stats: %{state: %{"temperature" => 999}}
    }
end
