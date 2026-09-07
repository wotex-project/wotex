defmodule Wotex.Lab.SmartRoomTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP
  alias Wotex.DataSchema
  alias Wotex.Directory
  alias Wotex.Directory.{Context, Service}
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Directory.{Authorization, Clock, EtsRepository, Identifier}
  alias Wotex.Lab.Adapters.HTTP.ReqClient
  alias Wotex.Lab.Adapters.Runtime.{Loopback, StaticRef}
  alias Wotex.Lab.Continuum.{Channel, Host}
  alias Wotex.Lab.Error, as: LabError
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Lab.SmartRoom.{Policy, Scenario}
  alias Wotex.Lab.Test.{ContinuumFixtures, HttpServer}
  alias Wotex.Nx.{ActionProposal, Decoder, OutputSchema}
  alias Wotex.Runtime.{BindingProfile, Result}
  alias Wotex.ThingDescription

  @epoch ~U[2026-09-08 12:00:00Z]
  @token "room-token-7f3a"

  setup do
    lab = start_supervised!({Lab, id: "smart-room", max_children: 32})
    {:ok, server} = HttpServer.start(self())

    thermostat_td = thermostat(server.port)

    {:ok, actuator_td} =
      Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
      |> File.read!()
      |> ThingDescription.parse()

    {:ok, actuator} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: actuator_td,
         state: %{"temperature" => 20.0, "target" => 21.0},
         tokens: %{"bearer_sc" => @token},
         actions: %{
           "setTarget" => fn input, state ->
             {:ok, %{"accepted" => true}, :accepted, Map.put(state, "target", input)}
           end
         }}
      )

    {:ok, repository} = Lab.start_child(lab, :things, {EtsRepository, id: :directory})
    {:ok, clock} = Clock.start_link(@epoch)
    {:ok, identifier} = Identifier.start_link()

    {:ok, service} =
      Service.new(
        repository: {EtsRepository, repository},
        authorization: {Authorization, :allow_all},
        clock: {Clock, {:agent, clock}},
        identifier: {Identifier, identifier},
        introduction: thermostat_td
      )

    context = Context.new!(:operator)
    {:ok, _thermostat} = Directory.register(service, thermostat_td, context)
    {:ok, _actuator} = Directory.register(service, actuator_td, context)

    {:ok, http_profile} = HTTP.profile()
    {:ok, http_config} = HTTP.config(client: {ReqClient, %{}})

    {:ok, loopback_profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations()
      )

    transport_opts = [
      profiles: [http_profile, loopback_profile],
      transports: %{
        http_profile.id => HTTP.transport(http_config),
        loopback: {Loopback, %{host: actuator}}
      },
      credentials:
        {StaticRef, %{references: %{"bearer_sc" => "ref"}, lookup: fn "ref" -> {:ok, @token} end}}
    ]

    {:ok, things} = Scenario.discover(service, context, transport_opts)

    {:ok, channel} =
      Lab.start_child(
        lab,
        :sessions,
        {Channel, id: :room_channel, clock: fn -> @epoch end, capacity: 32}
      )

    {:ok, host} =
      Lab.start_child(
        lab,
        :sessions,
        {Host,
         id: :room_host,
         channel: channel,
         endpoint: "cloud",
         clock: fn -> @epoch end,
         things: things,
         capabilities: [ContinuumFixtures.capability()]}
      )

    :ok = Channel.attach(channel, "edge", self())
    {:ok, _manifest} = Channel.send_value(channel, "edge", "cloud", ContinuumFixtures.manifest())

    {:ok, policy} =
      Lab.start_child(
        lab,
        :sessions,
        {Policy, id: :policy, allowed: [:operator], limits: %{"setTarget" => %{min: 5, max: 35}}}
      )

    run_opts = [
      things: things,
      thermostat_id: ThingDescription.id(thermostat_td),
      actuator_id: ThingDescription.id(actuator_td),
      channel: channel,
      edge: "edge",
      cloud: "cloud",
      policy: policy,
      principal: :operator,
      now: 1_000,
      epoch: @epoch,
      scope: Scenario.scope("edge", @epoch),
      watermark: 1,
      state_revision: 1
    ]

    %{
      lab: lab,
      things: things,
      run_opts: run_opts,
      policy: policy,
      host: host,
      actuator: actuator,
      channel: channel,
      transport_opts: transport_opts,
      service: service,
      context: context
    }
  end

  test "discovery, consumption, exchange, inference, decision, dispatch and effect are one inspectable cycle",
       %{
         run_opts: opts,
         policy: policy,
         host: host,
         actuator: actuator,
         things: things
       } do
    assert Map.keys(things) |> Enum.sort() == ["urn:wotex:lab:http:room", "urn:wotex:lab:room:1"]
    assert {:ok, run} = Scenario.run(opts)

    assert %ActionProposal{} = run.action_proposal
    assert %{action_name: "setTarget", input: input} = ActionProposal.to_map(run.action_proposal)
    assert_in_delta input, 22.5, 0.0001
    assert run.decision.status == :granted
    assert run.decision.proposal_digest == Policy.proposal_digest(run.action_proposal)
    assert {:ok, %Result{status: :accepted}} = run.dispatch
    assert_in_delta run.effect, 22.5, 0.0001
    assert %{handler_calls: 2, state: %{"target" => set}} = Thing.stats(actuator)
    assert_in_delta set, 22.5, 0.0001

    stats = wait_until(fn -> Host.stats(host) end, &(length(&1.received) == 3))

    assert Enum.map(stats.received, & &1.kind) == [
             "continuum_manifest",
             "observation_proposal",
             "action_result"
           ]

    assert %{{"urn:wotex:lab:http:room", :property, "temperature"} => %{value: 21.5, sequence: 1}} =
             stats.observations

    assert %{decisions: [%{status: :dispatched, attempts: [_one]}], refusals: []} =
             Policy.records(policy)

    assert {:error, %LabError{code: :already_dispatched}} =
             Policy.dispatch(
               policy,
               run.decision.id,
               [now: 1_001, watermark: 1, state_revision: 1],
               fn -> flunk("dispatched twice") end
             )
  end

  test "stale, expired, revoked, conflicting and unauthorized attempts dispatch nothing", %{
    run_opts: opts,
    policy: policy,
    actuator: actuator
  } do
    {:ok, output} = DataSchema.new(%{"type" => "number", "minimum" => 5, "maximum" => 35})

    {:ok, schema} =
      OutputSchema.new(
        kind: :action_proposal,
        thing_id: "urn:wotex:lab:room:1",
        affordance_type: :action,
        affordance_name: "setTarget",
        data_schema: output,
        dtype: :f32
      )

    proposal = fn id ->
      elem(
        Decoder.decode(Nx.tensor(24.0, type: :f32), schema, id: id, proposed_at: 1_000),
        1
      )
    end

    never = fn -> flunk("must not dispatch") end

    assert {:error, %LabError{code: :principal_denied}} =
             Policy.decide(policy, proposal.("p-stranger"),
               principal: :stranger,
               watermark: 1,
               state_revision: 1,
               now: 1_000
             )

    {:ok, granted} =
      Policy.decide(policy, proposal.("p-1"),
        principal: :operator,
        watermark: 1,
        state_revision: 1,
        now: 1_000,
        ttl: 100
      )

    assert {:error, %LabError{code: :conflicting_decision}} =
             Policy.decide(policy, proposal.("p-2"),
               principal: :operator,
               watermark: 1,
               state_revision: 1,
               now: 1_000
             )

    assert {:error, %LabError{code: :stale_observation}} =
             Policy.dispatch(
               policy,
               granted.id,
               [now: 1_001, watermark: 2, state_revision: 1],
               never
             )

    assert {:error, %LabError{code: :stale_state}} =
             Policy.dispatch(
               policy,
               granted.id,
               [now: 1_001, watermark: 1, state_revision: 2],
               never
             )

    assert {:error, %LabError{code: :expired}} =
             Policy.dispatch(
               policy,
               granted.id,
               [now: 1_200, watermark: 1, state_revision: 1],
               never
             )

    assert :ok = Policy.revoke(policy, granted.id)

    assert {:error, %LabError{code: :revoked}} =
             Policy.dispatch(
               policy,
               granted.id,
               [now: 1_001, watermark: 1, state_revision: 1],
               never
             )

    assert {:error, %LabError{code: :not_revocable}} = Policy.revoke(policy, granted.id)

    assert {:error, %LabError{code: :unknown_decision}} =
             Policy.dispatch(policy, "nope", [now: 1, watermark: 1, state_revision: 1], never)

    {:ok, wide} =
      OutputSchema.new(
        kind: :action_proposal,
        thing_id: "urn:wotex:lab:room:1",
        affordance_type: :action,
        affordance_name: "setTarget",
        data_schema: elem(DataSchema.new(%{"type" => "number"}), 1),
        dtype: :f32
      )

    {:ok, too_hot} =
      Decoder.decode(Nx.tensor(99.0, type: :f32), wide, id: "p-hot", proposed_at: 1_000)

    assert {:error, %LabError{code: :input_outside_limits}} =
             Policy.decide(policy, too_hot,
               principal: :operator,
               watermark: 1,
               state_revision: 1,
               now: 1_000
             )

    {:ok, other} =
      OutputSchema.new(
        kind: :action_proposal,
        thing_id: "urn:wotex:lab:room:1",
        affordance_type: :action,
        affordance_name: "reboot",
        data_schema: output,
        dtype: :f32
      )

    {:ok, ungoverned} =
      Decoder.decode(Nx.tensor(10.0, type: :f32), other,
        id: "p-reboot",
        proposed_at: 1_000
      )

    assert {:error, %LabError{code: :action_not_governed}} =
             Policy.decide(policy, ungoverned,
               principal: :operator,
               watermark: 1,
               state_revision: 1,
               now: 1_000
             )

    assert %{handler_calls: 0} = Thing.stats(actuator)
    records = Policy.records(policy)

    assert Enum.map(records.refusals, & &1.reason) == [
             :principal_denied,
             :conflicting_decision,
             :stale_observation,
             :stale_state,
             :expired,
             :revoked,
             :not_revocable,
             :unknown_decision,
             :input_outside_limits,
             :action_not_governed
           ]

    assert [%{status: :revoked}] = records.decisions
    assert {:ok, _run} = Scenario.run(opts)
  end

  test "a restarted policy holds no grants and a missing thing is a typed error", %{
    lab: lab,
    run_opts: opts
  } do
    {:ok, policy} =
      Lab.start_child(
        lab,
        :sessions,
        {Policy,
         id: :restarting,
         name: :wotex_lab_smart_room_restarting_policy,
         allowed: [:operator],
         limits: %{"setTarget" => %{min: 5, max: 35}},
         restart: :permanent}
      )

    {:ok, run} = Scenario.run(Keyword.put(opts, :policy, policy))
    assert %{decisions: [_one]} = Policy.records(policy)

    monitor = Process.monitor(policy)
    Process.exit(policy, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^policy, :killed}

    restarted =
      wait_until(
        fn -> Process.whereis(:wotex_lab_smart_room_restarting_policy) end,
        &(is_pid(&1) and &1 != policy)
      )

    assert %{decisions: [], refusals: []} = Policy.records(restarted)

    assert {:error, %LabError{code: :unknown_decision}} =
             Policy.dispatch(
               restarted,
               run.decision.id,
               [now: 1_001, watermark: 1, state_revision: 1],
               fn -> flunk("grant restored") end
             )

    assert {:error, %LabError{code: :thing_not_discovered}} =
             Scenario.run(Keyword.put(opts, :actuator_id, "urn:wotex:lab:ghost"))
  end

  test "discovery pages through the directory and fails closed on an unbuildable Thing", %{
    service: service,
    context: context,
    transport_opts: transport_opts
  } do
    for n <- 1..60 do
      {:ok, _mutation} =
        Directory.register(
          service,
          thing("urn:wotex:lab:extra:#{String.pad_leading(Integer.to_string(n), 3, "0")}"),
          context
        )
    end

    {:ok, things} = Scenario.discover(service, context, transport_opts)
    assert map_size(things) == 62

    assert {:error, _error} =
             Scenario.discover(service, context, Keyword.put(transport_opts, :transports, %{}))
  end

  defp thermostat(port) do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:wotex:lab:http:room",
        "title" => "HTTP thermostat",
        "base" => "http://127.0.0.1:#{port}/",
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "unit" => "Cel",
            "forms" => [
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "op" => "readproperty"
              }
            ]
          }
        }
      })

    td
  end

  defp thing(id) do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => id,
        "title" => "Extra",
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "properties" => %{
          "state" => %{
            "type" => "string",
            "forms" => [%{"href" => "loopback://extra/state", "op" => "readproperty"}]
          }
        }
      })

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
