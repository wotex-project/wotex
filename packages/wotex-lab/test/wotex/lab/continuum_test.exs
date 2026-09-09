defmodule Wotex.Lab.ContinuumTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Runtime.{Loopback, StaticRef}
  alias Wotex.Lab.Continuum.{Channel, FaultSchedule, Host, Wire}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Lab.Test.ContinuumFixtures, as: Fixtures
  alias Wotex.Nx.{Decoder, Observation, OutputSchema}
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Error, Result}
  alias Wotex.ThingDescription
  alias WotexContinuum.{ActionIntent, ActionResult, Codec, Delivery, Lifecycle, ObservationProposal}

  @epoch ~U[2026-09-08 10:00:00Z]

  setup context do
    lab = start_supervised!({Lab, id: "continuum", max_children: 16})
    clock = fn -> @epoch end
    faults = Map.get(context, :faults, [])

    {:ok, channel} =
      Lab.start_child(
        lab,
        :sessions,
        {Channel, id: :channel, clock: clock, capacity: 16, faults: faults}
      )

    td = fixture()

    {:ok, thing} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: td,
         state: %{"temperature" => 20.0, "target" => 21.0},
         tokens: %{"bearer_sc" => "room-token"}}
      )

    {:ok, profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations()
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: thing}}},
        credentials: bearer_credentials()
      )

    {:ok, host} =
      Lab.start_child(
        lab,
        :sessions,
        {Host,
         id: :host,
         channel: channel,
         endpoint: "cloud",
         clock: clock,
         things: %{ThingDescription.id(td) => consumed},
         capabilities: [Fixtures.capability()]}
      )

    :ok = Channel.attach(channel, "edge-a", self())
    %{lab: lab, channel: channel, host: host, thing: thing, td: td}
  end

  test "every registered kind round-trips through the channel as canonical bytes", %{
    channel: channel,
    host: host
  } do
    for value <- Fixtures.all_kinds() do
      assert {:ok, %Delivery{status: :in_flight}} =
               Channel.send_value(channel, "edge-a", "cloud", value)
    end

    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.received) == 13))
    assert Enum.map(stats.received, & &1.kind) |> Enum.sort() == WotexContinuum.kinds()

    # The intent in the fixture set was dispatched once and answered on the edge endpoint.
    assert_receive {:wotex_continuum, "edge-a", result_delivery, result_wire}
    assert {:ok, %ActionResult{intent_id: "intent-1"}} = Codec.decode(result_wire)
    assert :ok = Channel.ack(channel, result_delivery)
    assert Enum.all?(Channel.deliveries(channel), &(&1.status == :acknowledged))

    :ok = Channel.attach(channel, "fixture-cloud", self())

    {:ok, delivery} =
      Channel.send_value(channel, "fixture-cloud", "edge-a", Fixtures.manifest())

    assert_receive {:wotex_continuum, "edge-a", delivery_id, wire}
    assert delivery_id == delivery.delivery_id
    assert {:ok, decoded} = Codec.decode(wire)
    assert decoded == Fixtures.manifest()

    assert {:error, %Wotex.Lab.Error{code: :invalid_continuum_value}} =
             Channel.send_value(channel, "edge-a", "cloud", %{"kind" => "x"})
  end

  test "manifest compatibility gates intents and stale authority never dispatches", %{
    channel: channel,
    host: host,
    thing: thing
  } do
    [_, _, _, _, _, intent | _] = Fixtures.all_kinds()

    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", intent)
    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.rejected) == 1))
    assert [%{reason: :stale_authority}] = stats.rejected
    assert %{handler_calls: 0} = Thing.stats(thing)

    incompatible =
      Fixtures.manifest(id: "manifest-old", compatibility: Fixtures.compatibility(">= 9.0.0"))

    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", incompatible)
    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.rejected) == 2))
    assert Enum.any?(stats.rejected, &(&1.reason == :incompatible_manifest))
    assert stats.manifests == []

    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", Fixtures.manifest())
    stats = wait_until(fn -> Host.stats(host) end, &(&1.manifests == ["manifest-edge-a"]))
    assert stats.manifests == ["manifest-edge-a"]
  end

  test "source ownership and per-source manifests prevent identity transplantation", %{
    channel: channel,
    host: host,
    thing: thing
  } do
    parent = self()

    attacker =
      spawn_link(fn ->
        send(parent, {:attacker_attached, Channel.attach(channel, "edge-b", self())})

        for _ <- 1..2 do
          receive do
            {:send, value} ->
              send(
                parent,
                {:attacker_result, Channel.send_value(channel, "edge-b", "cloud", value)}
              )
          end
        end
      end)

    assert_receive {:attacker_attached, :ok}

    assert {:error, %Wotex.Lab.Error{code: :endpoint_in_use}} =
             Channel.attach(channel, "edge-b", self())

    assert {:error, %Wotex.Lab.Error{code: :source_not_attached}} =
             Channel.send_value(channel, "edge-b", "cloud", Fixtures.manifest())

    [_, _, _, _, _, intent | _] = Fixtures.all_kinds()
    {:ok, forged_wire} = Codec.encode(intent, canonical: true)

    send(
      host,
      {:wotex_continuum, "cloud", "edge-a", "forged-delivery", make_ref(), forged_wire}
    )

    Process.sleep(10)
    assert Process.alive?(host)
    assert Host.stats(host).received == []

    send(attacker, {:send, intent})
    assert_receive {:attacker_result, {:ok, _delivery}}

    edge_b_intent = %{
      intent
      | intent_id: "intent-edge-b",
        idempotency_key: "set-edge-b",
        context: Fixtures.scope("edge-b")
    }

    send(attacker, {:send, edge_b_intent})
    assert_receive {:attacker_result, {:ok, _delivery}}

    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.rejected) == 2))
    assert Enum.map(stats.rejected, & &1.reason) == [:source_mismatch, :stale_authority]
    assert Enum.all?(stats.rejected, &(&1.source == "edge-b"))
    assert %{handler_calls: 0} = Thing.stats(thing)
  end

  @tag faults: [duplicate: [2]]
  test "a duplicate delivery of an intent cannot cause a second dispatch", %{
    channel: channel,
    host: host,
    thing: thing
  } do
    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", Fixtures.manifest())
    [_, _, _, _, _, intent | _] = Fixtures.all_kinds()
    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", intent)

    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.received) == 3))
    assert %{"set-22" => %{duplicates: 1, outcome: {:ok, :accepted}}} = stats.dispatches
    assert [%{reason: :duplicate_intent}] = stats.rejected
    assert %{handler_calls: 1, state: %{"setTarget" => 22.0}} = Thing.stats(thing)

    assert_receive {:wotex_continuum, "edge-a", _delivery_id, wire}
    assert {:ok, %ActionResult{intent_id: "intent-1", status: :accepted}} = Codec.decode(wire)
    refute_receive {:wotex_continuum, "edge-a", _other, _wire}, 50
  end

  @tag faults: [hold: %{3 => 4}, drop: [5]]
  test "reordered and dropped proposals never move the observed state backwards", %{
    channel: channel,
    host: host,
    td: td
  } do
    thing_id = ThingDescription.id(td)
    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", Fixtures.manifest())

    proposals =
      for {sequence, value} <- [{1, 20.0}, {2, 21.0}, {3, 22.0}], into: [] do
        {:ok, observation} =
          Observation.new(
            id: "obs-#{sequence}",
            thing_id: thing_id,
            affordance_type: :property,
            affordance_name: "temperature",
            observed_at: sequence * 1_000,
            value: value,
            unit: "Cel"
          )

        {:ok, proposal} =
          Wire.proposal_from_observation(observation, Fixtures.scope(), @epoch, sequence: sequence)

        proposal
      end

    Enum.each(proposals, &({:ok, _} = Channel.send_value(channel, "edge-a", "cloud", &1)))
    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.received) == 3))
    key = {thing_id, :property, "temperature"}

    # Channel sequence 3 (obs-2) was held until obs-3 was sent, so obs-3 arrived first.
    assert %{sequence: 3, value: 22.0, observed_at: "2026-09-08T10:00:03.000Z"} =
             stats.observations[key]

    assert Enum.map(stats.received, & &1.item_id) == ["manifest-edge-a", "obs-1", "obs-3", "obs-2"]
    assert [%{reason: :stale_observation, item_id: "obs-2"}] = stats.rejected
    assert [_, _, _, _ | _] = deliveries = Channel.deliveries(channel)

    assert Enum.at(deliveries, 3).status == :in_flight or
             Enum.at(deliveries, 3).status == :acknowledged

    {:ok, observation} =
      Observation.new(
        id: "obs-4",
        thing_id: thing_id,
        affordance_type: :property,
        affordance_name: "temperature",
        observed_at: 4_000,
        value: 30.0,
        unit: "Cel"
      )

    {:ok, dropped} =
      Wire.proposal_from_observation(observation, Fixtures.scope(), @epoch, sequence: 4)

    assert {:ok, %Delivery{status: :failed, error: %{code: "dropped"}}} =
             Channel.send_value(channel, "edge-a", "cloud", dropped)

    assert %{sequence: 3} = Host.stats(host).observations[key]
  end

  test "disconnection replays unacknowledged deliveries without a second mutation", %{
    lab: lab,
    channel: channel,
    td: td,
    thing: thing
  } do
    # A silent cloud endpoint that never acknowledges: deliveries stay in flight.
    :ok = Channel.attach(channel, "silent", self())
    {:ok, delivery} = Channel.send_value(channel, "edge-a", "silent", Fixtures.manifest())
    assert_receive {:wotex_continuum, "silent", delivery_id, _wire}
    assert delivery_id == delivery.delivery_id

    :ok = Channel.disconnect(channel)
    {:ok, buffered} = Channel.send_value(channel, "edge-a", "silent", Fixtures.capability())
    assert buffered.status == :pending
    refute_receive {:wotex_continuum, "silent", _id, _wire}, 50

    :ok = Channel.reconnect(channel)
    assert_receive {:wotex_continuum, "silent", ^delivery_id, _wire}
    assert_receive {:wotex_continuum, "silent", buffered_id, _wire}
    assert buffered_id == buffered.delivery_id
    assert [%Delivery{attempt: 2}, %Delivery{attempt: 1}] = Channel.deliveries(channel)
    assert :ok = Channel.ack(channel, delivery_id)
    assert {:error, %Wotex.Lab.Error{code: :unknown_delivery}} = Channel.ack(channel, "nope")

    # The same replay against the real host: manifest twice, intent twice, one dispatch.
    {:ok, profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations()
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: thing}}},
        credentials: bearer_credentials()
      )

    {:ok, replay_channel} =
      Lab.start_child(lab, :sessions, {Channel, id: :replay, clock: fn -> @epoch end})

    {:ok, host} =
      Lab.start_child(
        lab,
        :sessions,
        {Host,
         id: :replay_host,
         channel: replay_channel,
         endpoint: "cloud",
         clock: fn -> @epoch end,
         things: %{ThingDescription.id(td) => consumed},
         capabilities: [Fixtures.capability()]}
      )

    :ok = Channel.attach(replay_channel, "edge-a", self())
    :ok = Channel.disconnect(replay_channel)
    {:ok, _} = Channel.send_value(replay_channel, "edge-a", "cloud", Fixtures.manifest())
    [_, _, _, _, _, intent | _] = Fixtures.all_kinds()
    {:ok, _} = Channel.send_value(replay_channel, "edge-a", "cloud", intent)
    :ok = Channel.reconnect(replay_channel)
    stats = wait_until(fn -> Host.stats(host) end, &(map_size(&1.dispatches) == 1))
    :ok = Channel.disconnect(replay_channel)
    :ok = Channel.reconnect(replay_channel)
    Process.sleep(20)
    assert %{"set-22" => %{duplicates: 0}} = stats.dispatches
    assert %{handler_calls: 1} = Thing.stats(thing)
  end

  test "capacity is bounded and the host lifecycle refuses intents while draining", %{
    lab: lab,
    host: host,
    channel: channel
  } do
    {:ok, silent_channel} =
      Lab.start_child(lab, :sessions, {Channel, id: :bounded, clock: fn -> @epoch end, capacity: 2})

    :ok = Channel.attach(silent_channel, "edge-a", self())
    :ok = Channel.attach(silent_channel, "silent", self())
    {:ok, _} = Channel.send_value(silent_channel, "edge-a", "silent", Fixtures.mode())
    {:ok, _} = Channel.send_value(silent_channel, "edge-a", "silent", Fixtures.mode())

    assert {:error, %Wotex.Lab.Error{code: :capacity_exhausted, class: :unavailable}} =
             Channel.send_value(silent_channel, "edge-a", "silent", Fixtures.mode())

    assert {:ok, %Lifecycle{state: :draining, generation: 1}} = Host.drain(host)
    assert {:error, _} = Host.drain(host)
    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", Fixtures.manifest())
    [_, _, _, _, _, intent | _] = Fixtures.all_kinds()
    {:ok, _} = Channel.send_value(channel, "edge-a", "cloud", intent)
    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.rejected) == 1))
    assert [%{reason: :host_not_accepting}] = stats.rejected
    assert %Lifecycle{state: :draining} = stats.lifecycle
  end

  test "wire conversions follow the documented mapping in both directions", %{td: td} do
    thing_id = ThingDescription.id(td)
    {:ok, data_schema} = Wotex.DataSchema.new(%{"type" => "number", "unit" => "Cel"})

    {:ok, output} =
      OutputSchema.new(
        kind: :action_proposal,
        thing_id: thing_id,
        affordance_type: :action,
        affordance_name: "setTarget",
        data_schema: data_schema,
        dtype: :f32
      )

    {:ok, proposal} =
      Decoder.decode(Nx.tensor(23.0, type: :f32), output, id: "proposal-9", proposed_at: 5_000)

    {:ok, intent} =
      Wire.intent_from_proposal(proposal, Fixtures.scope(), @epoch, requested_by: "policy")

    assert %ActionIntent{
             intent_id: "proposal-9",
             idempotency_key: "proposal-9",
             requested_at: "2026-09-08T10:00:05.000Z",
             input: 23.0
           } = intent

    {:ok, observation} =
      Observation.new(
        id: "obs-9",
        thing_id: thing_id,
        affordance_type: :property,
        affordance_name: "temperature",
        observed_at: 250,
        value: 20.5,
        unit: "Cel",
        source: "sensor-a",
        quality: :uncertain
      )

    {:ok, wire_proposal} = Wire.proposal_from_observation(observation, Fixtures.scope(), @epoch)

    assert %ObservationProposal{proposal_id: "obs-9", observed_at: "2026-09-08T10:00:00.250Z"} =
             wire_proposal

    assert wire_proposal.extensions["urn:wotex:lab:continuum:unit"] == "Cel"
    assert wire_proposal.extensions["urn:wotex:lab:continuum:quality"] == "uncertain"

    {:ok, ok_result} =
      Result.new("intent:proposal-9", :invokeaction, %{"done" => true})

    assert {:ok, %ActionResult{status: :succeeded, output: %{"done" => true}}} =
             Wire.result_from_runtime(
               {:ok, ok_result},
               "r1",
               "proposal-9",
               Fixtures.scope("cloud"),
               @epoch
             )

    {:ok, accepted} =
      Result.new("intent:proposal-9", :invokeaction, nil, status: :accepted)

    assert {:ok, %ActionResult{status: :accepted, completed_at: nil}} =
             Wire.result_from_runtime(
               {:ok, accepted},
               "r2",
               "proposal-9",
               Fixtures.scope("cloud"),
               @epoch
             )

    error = Error.new(:compatible_form_not_found, :selection, "no form")

    assert {:ok, %ActionResult{status: :failed, error: %{code: "compatible_form_not_found"}}} =
             Wire.result_from_runtime(
               {:error, error},
               "r3",
               "proposal-9",
               Fixtures.scope("cloud"),
               @epoch
             )

    assert {:error, _} = FaultSchedule.new(drop: [0])
  end

  defp bearer_credentials do
    {StaticRef, %{references: %{"bearer_sc" => "ref"}, lookup: fn "ref" -> {:ok, "room-token"} end}}
  end

  defp fixture do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
    {:ok, td} = path |> File.read!() |> ThingDescription.parse()
    td
  end

  defp wait_until(read, predicate, attempts \\ 200) do
    value = read.()

    cond do
      predicate.(value) ->
        value

      attempts == 0 ->
        value

      true ->
        Process.sleep(5)
        wait_until(read, predicate, attempts - 1)
    end
  end
end
