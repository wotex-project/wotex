defmodule WotexLabWorkbench.RoomProfilesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.ThingDescription
  alias WotexLabWorkbench.{RoomProfiles, Seeds}

  @profile %{id: "zone-1", title: "Zone controller", host: {127, 0, 0, 1}, port: 5020, unit_id: 1}

  test "configuration is closed, bounded and rejects endpoint aliases" do
    assert {:ok, %{}} = RoomProfiles.new([])
    assert {:ok, %{"zone-1" => @profile}} = RoomProfiles.new([@profile])

    invalid = [
      nil,
      %{},
      [Map.put(@profile, :extra, true)],
      [Map.delete(@profile, :host)],
      [Map.new(@profile, fn {key, value} -> {Atom.to_string(key), value} end)],
      [@profile, @profile],
      [@profile, %{@profile | id: "alias", unit_id: 2}],
      List.duplicate(@profile, 5)
    ]

    fields = %{
      id: ["", "loopback", "A", "1zone", "zone/a", String.duplicate("a", 33), <<255>>],
      title: ["", " \t", "bad\nname", "bad\u0085name", <<255>>, String.duplicate("a", 65)],
      host: ["localhost", {127, 0, 0}, {256, 0, 0, 1}, {-1, 0, 0, 1}, {1.0, 0, 0, 1}],
      port: [0, 65_536, "5020", 5020.0],
      unit_id: [0, 248, "1", 1.0]
    }

    invalid =
      invalid ++ for({key, values} <- fields, value <- values, do: [Map.put(@profile, key, value)])

    for input <- invalid do
      assert {:error, %Error{code: :invalid_room_profiles}} = RoomProfiles.new(input)
    end
  end

  test "choices disclose no route and distinguish the owning room from a busy endpoint" do
    {:ok, profiles} = RoomProfiles.new([@profile])
    assert {:ok, :loopback} = RoomProfiles.fetch(profiles, "loopback")
    assert {:ok, @profile} = RoomProfiles.fetch(profiles, "zone-1")
    assert {:error, %Error{code: :unknown_room_profile}} = RoomProfiles.fetch(profiles, "caller")
    assert {:error, %Error{code: :invalid_room_profiles}} = RoomProfiles.fetch(profiles, %{})

    lease = %{"zone-1" => %{room: self(), actors: []}}

    assert [_, %{id: "zone-1", available: true} = choice] =
             RoomProfiles.choices(profiles, lease, self())

    assert Map.keys(choice) |> Enum.sort() == [:available, :id, :title]
    assert [_, %{available: false}] = RoomProfiles.choices(profiles, lease, nil)
  end

  test "backend descriptions map float registers and expose only supported operations" do
    {:ok, seeds} = Seeds.room()
    assert {:ok, ^seeds} = RoomProfiles.specs(:loopback, seeds)
    assert {:ok, specs} = RoomProfiles.specs(@profile, seeds)
    assert Enum.all?(specs, &(&1.state == %{} and &1.scheme == "modbus+tcp"))

    for {key, property, entity, address} <- [
          {"thermostat", "temperature", "InputRegister", 1},
          {"meter", "power", "InputRegister", 3},
          {"actuator", "target", "HoldingRegister", 1}
        ] do
      spec = Enum.find(specs, &(&1.key == key))
      doc = ThingDescription.to_map(spec.td)
      assert doc["id"] == "urn:wotex:lab:modbus:zone-1:#{key}"
      assert Map.keys(doc["properties"]) == [property]
      refute doc["properties"][property]["observable"]
      assert doc["events"] == %{}
      assert [form] = doc["properties"][property]["forms"]
      assert form["href"] == "modbus+tcp://127.0.0.1:5020/1/#{address}?quantity=2"
      assert form["modv:entity"] == entity
      assert form["modv:type"] == "xsd:float"

      if key == "actuator" do
        assert [action] = doc["actions"]["setTarget"]["forms"]
        assert action["modv:function"] == "writeMultipleHoldingRegisters"
        assert doc["actions"]["setTarget"]["input"]["minimum"] == 5
        assert doc["actions"]["setTarget"]["input"]["maximum"] == 35
      else
        assert doc["actions"] == %{}
      end
    end
  end
end
