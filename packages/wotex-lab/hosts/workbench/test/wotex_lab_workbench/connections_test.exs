defmodule WotexLabWorkbench.ConnectionsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Canvas, Connections, Experiments, Room, Sessions}

  setup do
    lab = start_supervised!({Wotex.Lab, id: "connection-test", max_children: 128})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab, ttl_ms: 60_000, sweep_ms: 50, max_sessions: 8, name: __MODULE__.Registry}
      )

    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :start_room)
    %{registry: registry, session: session, room: session.room, things: Room.things(session.room)}
  end

  test "eligibility follows actual operation, scalar type and exact unit; inert entries stay inert",
       %{room: room, things: things} do
    before = counts(room)

    assert Enum.map(Connections.options(things, "power"), &{&1.thing, &1.affordance}) ==
             [{"meter", "power"}]

    temperature = Connections.options(things, "temperature")
    assert Enum.any?(temperature, &(&1.thing == "actuator" and &1.affordance == "target"))
    assert Enum.any?(temperature, &(&1.thing == "actuator" and &1.affordance == "temperature"))
    assert Enum.any?(temperature, &(&1.thing == "thermostat" and &1.affordance == "temperature"))

    assert [%{thing: "actuator", affordance: "setTarget", kind: :action}] =
             Connections.options(things, "proposal")

    thermostat = Enum.find(things, &(&1.key == "thermostat"))
    inert = %{thermostat | id: "urn:inert", consumable: false}
    wrong_unit = put_in(thermostat, [:document, "properties", "temperature", "unit"], "F")
    array = put_in(thermostat, [:document, "properties", "temperature", "type"], "array")

    no_read =
      put_in(thermostat, [:document, "properties", "temperature", "forms"], [
        %{"href" => "sim-thermostat://thermostat/temperature", "op" => "observeproperty"}
      ])

    for unavailable <- [inert, wrong_unit, array, no_read] do
      assert Connections.options([unavailable], "temperature") == []
    end

    assert Connections.options(things, "unknown") == []
    assert counts(room) == before
    assert Room.runs(room) == []
  end

  test "Apply is revision checked, closed and isolated; no-op and malformed requests execute nothing",
       %{room: room, things: things, registry: registry} do
    original = Room.connections(room)

    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "target",
      "revision" => "0"
    }

    before = counts(room)

    assert {:ok, changed} = Room.configure_connection(room, :apply, raw)
    assert changed.revision == 1
    assert {:error, %Error{code: :stale_connection}} = Room.configure_connection(room, :apply, raw)
    assert {:ok, ^changed} = Room.configure_connection(room, :apply, %{raw | "revision" => "1"})

    for bad <- [
          Map.put(raw, "authority", "grant"),
          %{raw | "revision" => "01"},
          %{raw | "revision" => "-1"},
          %{raw | "revision" => "1000000001"},
          %{raw | "revision" => 1},
          %{raw | "thing" => String.duplicate("x", 129)},
          %{raw | "port" => "other"},
          []
        ] do
      assert {:error, %Error{code: :invalid_connection}} =
               Room.configure_connection(room, :apply, bad)
    end

    assert {:error, %Error{code: :incompatible_connection}} =
             Room.configure_connection(room, :apply, %{
               raw
               | "revision" => "1",
                 "thing" => "meter",
                 "affordance" => "power"
             })

    assert Room.connections(room) == changed
    assert counts(room) == before
    assert Room.runs(room) == []
    assert Connections.new(Enum.reverse(things)) == original

    {:ok, other} = Sessions.open(registry)
    {:ok, other} = Sessions.admit(registry, other.token, :start_room)
    assert Room.connections(other.room) == original
    assert :ok = Sessions.revoke(registry, other.token)
  end

  test "handle gestures only draft compatible endpoints and never change the graph",
       %{room: room, things: things} do
    model = Room.connections(room)
    before = Canvas.props(things, [], %{}, nil, model)

    assert {:ok, draft} =
             Connections.gesture(model, things, %{
               "source" => "thing-actuator",
               "target" => "process-smart-room",
               "target_handle" => "temperature"
             })

    assert draft["thing"] == "actuator"
    assert draft["affordance"] == "temperature"
    assert Connections.draft?(draft)

    for bad <- [
          %{
            "source" => "thing-meter",
            "target" => "process-smart-room",
            "target_handle" => "temperature"
          },
          %{
            "source" => "thing-thermostat",
            "target" => "thing-actuator",
            "target_handle" => "input"
          },
          %{
            "source" => "process-smart-room",
            "target" => "thing-thermostat",
            "target_handle" => "input"
          },
          %{"source" => "other-room", "target" => "process-smart-room", "target_handle" => "power"},
          %{
            "source" => "thing-meter",
            "target" => "process-smart-room",
            "target_handle" => "power",
            "apply" => true
          }
        ] do
      assert {:error, %Error{}} = Connections.gesture(model, things, bad)
    end

    assert Room.connections(room) == model
    assert Canvas.props(things, [], %{}, nil, model) == before
    assert Room.runs(room) == []
  end

  test "the next Run reads the selected exact Property and records binding evidence before approval",
       %{room: room, things: things} do
    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "target",
      "revision" => "0"
    }

    assert {:ok, model} = Room.configure_connection(room, :apply, raw)
    assert counts(room)["thermostat"].handler_calls == 0
    assert counts(room)["actuator"].handler_calls == 0

    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, run} = Room.start_run(room, experiment.id, params)
    assert run.status == :awaiting_approval
    assert run.proposal["input"] == 20.0
    assert is_binary(run.record_digest)
    assert run.record.outcomes.connection_revision == 1
    assert run.tensor.feature_order == ["temperature", "power"]
    assert Enum.map(run.tensor.features, &{&1.dtype, &1.unit}) == [{"f32", "Cel"}, {"f32", "W"}]
    assert Enum.map(hd(run.tensor.preview).cells, &{&1.value, &1.mask}) == [{21.0, 1}, {2500.0, 1}]

    refs =
      for "connection:" <> json <- run.record.inputs, do: Jason.decode!(json)

    actuator = Enum.find(things, &(&1.key == "actuator"))
    assert ["temperature", actuator.id, "property", "target", "Cel"] in refs
    assert ["proposal", actuator.id, "action", "setTarget", "Cel"] in refs
    assert ("connections:" <> Connections.digest(model)) in run.record.inputs
    assert counts(room)["thermostat"].handler_calls == 0
    assert counts(room)["actuator"].handler_calls == 1
    assert counts(room)["actuator"].state["target"] == 21.0

    assert {:error, %Error{code: :pending_decision}} =
             Room.configure_connection(room, :remove, %{"port" => "temperature", "revision" => "1"})

    assert {:ok, _} = Room.cancel_run(room, run.id)

    assert {:ok, removed} =
             Room.configure_connection(room, :remove, %{"port" => "temperature", "revision" => "1"})

    assert removed.revision == 2
    assert run.record.outcomes.connection_revision == 1
    assert ["temperature", actuator.id, "property", "target", "Cel"] in refs
  end

  test "missing required input fails before reads; missing disabled power retains the declared fill mask",
       %{room: room} do
    {:ok, model} =
      Room.configure_connection(room, :remove, %{"port" => "power", "revision" => "0"})

    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})
    before = counts(room)
    assert {:ok, failed} = Room.start_run(room, experiment.id, params)
    assert failed.status == :failed
    assert failed.error.code == "missing_connection"
    assert counts(room) == before

    {:ok, without_meter} = Experiments.admit(experiment, %{"meter" => "off"})
    assert {:ok, run} = Room.start_run(room, experiment.id, without_meter)
    assert run.status == :awaiting_approval
    assert run.record.outcomes.connection_revision == model.revision

    assert Enum.map(hd(run.tensor.preview).cells, &{&1.value, &1.mask, &1.quality}) ==
             [{21.5, 1, 0}, {0.0, 0, 3}]

    assert counts(room)["meter"].handler_calls == 0
  end

  test "edge receipts retain exact Property identity and unavailable states within the graph bound",
       %{room: room, things: things} do
    model = Room.connections(room)

    {:ok, changed} =
      Connections.change(model, things, %{
        "port" => "temperature",
        "thing" => "actuator",
        "affordance" => "temperature",
        "revision" => "0"
      })

    reading = %{thing: "actuator", property: "temperature", value: 24.5, state: :stale}
    edges = Connections.edges(changed, things, %{"actuator/temperature" => reading})
    temperature = Enum.find(edges, &(&1["id"] == "temperature"))
    assert temperature["source"] == "thing-actuator"
    assert temperature["label"] == "temperature · 24.5 °C · Stale"

    assert Connections.edges(changed, things, %{
             "actuator/target" => %{reading | property: "target"}
           })
           |> Enum.find(&(&1["id"] == "temperature"))
           |> Map.fetch!("label") == "temperature · °C"

    large = %{reading | value: Integer.pow(10, 100), state: :disconnected}

    assert Connections.edges(changed, things, %{"actuator/temperature" => large})
           |> Enum.all?(&(byte_size(&1["label"]) <= 128))
  end

  test "integer source schemas keep their declared dtype and exact identity through the real Runtime",
       %{room: room} do
    state = :sys.get_state(room)
    original = state.things["thermostat"]
    document = put_in(original.document, ["properties", "temperature", "type"], "integer")
    {:ok, td} = Wotex.ThingDescription.from_map(document)

    host =
      start_supervised!(
        {Wotex.Lab.Reference.Thing,
         id: "integer-temperature", td: td, state: %{"temperature" => 21}, tokens: %{}}
      )

    {:ok, profile} =
      Wotex.Runtime.BindingProfile.new(
        id: :integer_temperature,
        schemes: ["sim-thermostat"],
        operations: Wotex.Runtime.operations()
      )

    {:ok, consumed} =
      Wotex.Runtime.ConsumedThing.new(td,
        profiles: [profile],
        transports: %{integer_temperature: {Wotex.Lab.Adapters.Runtime.Loopback, %{host: host}}},
        credentials:
          {Wotex.Lab.Adapters.Runtime.StaticRef,
           %{references: %{}, lookup: fn _ -> {:error, :unavailable} end}}
      )

    channel =
      start_supervised!(
        {Wotex.Lab.Continuum.Channel,
         id: :integer_channel, clock: fn -> state.epoch end, capacity: 64}
      )

    consumed_things = Map.put(state.consumed, original.id, consumed)

    start_supervised!(
      {Wotex.Lab.Continuum.Host,
       id: :integer_cloud,
       channel: channel,
       endpoint: "cloud",
       clock: fn -> state.epoch end,
       things: consumed_things}
    )

    :ok = Wotex.Lab.Continuum.Channel.attach(channel, "edge", self())

    fixture = %{
      state
      | things: Map.put(state.things, "thermostat", %{original | td: td, document: document}),
        consumed: consumed_things,
        channel: channel
    }

    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, result} = WotexLabWorkbench.Runs.SmartRoom.run(params, fixture)
    assert result.tensor.feature_order == ["temperature", "power"]
    assert hd(result.tensor.features).dtype == "s64"
    assert hd(hd(result.tensor.preview).cells).value == 21
    assert result.proposal["input"] == 20.0
    assert Wotex.Lab.Reference.Thing.stats(host).handler_calls == 1
  end

  defp counts(room),
    do: Map.new(Room.things(room), &{&1.key, &1.stats})
end
