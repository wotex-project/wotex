defmodule WotexLabWorkbench.Runs.SmartRoom do
  @moduledoc """
  The smart-room cycle split at the authorization seam.

  `run/2` observes the session's disposable thermostat and meter through the
  runtime, exchanges the observations over the continuum channel, encodes one
  Nx row, evaluates the public room rule `Wotex.Lab.SmartRoom.Scenario.target/2`,
  decodes an inert `setTarget` proposal and asks the room policy for a
  decision. It stops there: a granted decision is presented for explicit
  approval and nothing is dispatched. `dispatch/3` executes one approved
  decision through `Wotex.Lab.SmartRoom.Policy.dispatch/4`, which refuses a
  replayed, expired, revoked or stale approval, records the result on the
  channel and reads the simulated effect afterwards.
  """

  alias Wotex.DataSchema
  alias Wotex.Lab.Continuum.{Channel, Wire}
  alias Wotex.Lab.Error
  alias Wotex.Lab.SmartRoom.{Policy, Scenario}
  alias Wotex.Nx.{ActionProposal, Decoder, Encoder, Feature, Observation, OutputSchema, Row, Schema}
  alias Wotex.Runtime.{ConsumedThing, Context}
  alias Wotex.ThingDescription
  alias WotexLabWorkbench.{Preview, Runs}

  @backend Nx.BinaryBackend

  @doc "Observes, exchanges, infers and decides; never dispatches."
  @spec run(keyword(), map()) :: {:ok, map()} | {:error, term()}
  def run(params, room) do
    now = System.monotonic_time(:millisecond)
    meter? = Keyword.fetch!(params, :meter)

    {outcome, elapsed} =
      Runs.measure(fn ->
        with {:ok, thermostat} <- fetch(room, :thermostat),
             {:ok, actuator} <- fetch(room, :actuator),
             {:ok, temperature} <- observe(thermostat, "temperature", "Cel", now),
             {:ok, power} <- meter(room, meter?, now),
             {:ok, deliveries} <- exchange(room, [temperature, power]),
             {:ok, encoded, proposal} <- infer(actuator, temperature, power, params, now) do
          {:ok,
           %{
             temperature: temperature,
             power: power,
             deliveries: deliveries,
             encoded: encoded,
             proposal: proposal
           }}
        end
      end)

    with {:ok, cycle} <- outcome do
      fields = ActionProposal.to_map(cycle.proposal)
      tensor = Preview.tensor_summary(cycle.encoded, @backend)
      decision = decide(room, cycle.proposal, params, now)
      temperature = Observation.to_map(cycle.temperature)
      power = cycle.power && Observation.to_map(cycle.power)

      {:ok,
       %{
         duration_ms: elapsed,
         backend: inspect(@backend),
         summary:
           [
             {"Thermostat", "#{temperature.thing_id}: #{Preview.format(temperature.value)} Cel"},
             {"Meter",
              if(power,
                do: "#{power.thing_id}: #{Preview.format(power.value)} W",
                else: "off (power filled, mask 0)"
              )},
             {"Power budget", Preview.format(params[:power_budget]) <> " W"},
             {"Proposal",
              "#{fields.action_name} #{Preview.format(fields.input)} Cel for #{fields.thing_id} (inert)"},
             {"Exchanged", "#{length(cycle.deliveries)} observation proposal(s) edge to cloud"}
           ] ++ decision_summary(decision),
         tensor: tensor,
         timeseries: Runs.timeseries(tensor),
         assertions: [
           Runs.assertion(
             "room:proposal-in-limits",
             fields.input >= 5 and fields.input <= 35,
             "input inside 5..35 Cel"
           ),
           Runs.assertion("room:decision", decision_ok?(decision), decision_note(decision)),
           Runs.assertion("room:dispatch-once", :not_run, "dispatch needs an explicit approval")
         ],
         proposal: Runs.plain(fields),
         decision: decision_view(decision, fields),
         outcomes: %{
           proposal_input: fields.input,
           decision: decision_status(decision),
           power_observed: not is_nil(power)
         },
         inputs: ["fixture:loopback/thing-description.json", "room:" <> room.id],
         seed: 0,
         budgets: %{max_rows: 1, ttl_ms: params[:ttl_ms]}
       }}
    end
  end

  @doc "Dispatches one approved decision once; the policy refuses replays and stale approvals."
  @spec dispatch(map(), map(), map()) :: {:ok, map()} | {:error, Error.t()}
  def dispatch(%{decision: %{} = decision} = run, approval, room) do
    now = System.monotonic_time(:millisecond)

    with :ok <- match(decision, approval),
         {:ok, actuator} <- fetch(room, :actuator),
         {:ok, outcome} <-
           Policy.dispatch(
             room.policy,
             decision["id"],
             [now: now, watermark: room.watermark, state_revision: room.state_revision],
             fn ->
               ConsumedThing.invoke_action(
                 actuator,
                 decision["action_name"],
                 decision["input"],
                 context("decision:" <> decision["id"], now)
               )
             end
           ),
         {:ok, result} <-
           Wire.result_from_runtime(
             outcome,
             "room-result-" <> run.proposal["id"],
             run.proposal["id"],
             room.scope,
             DateTime.add(room.epoch, now, :millisecond)
           ),
         {:ok, _delivery} <- Channel.send_value(room.channel, "edge", "cloud", result),
         {:ok, effect} <- ConsumedThing.read_property(actuator, "target", context("effect", now)) do
      {:ok, %{dispatch: Runs.plain(outcome), effect: effect.payload}}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, other} ->
        {:error,
         Error.new(:dispatch_failed, :dispatch, "dispatch failed",
           details: %{reason: Runs.plain(other)}
         )}
    end
  end

  def dispatch(_run, _approval, _room),
    do: {:error, Error.new(:no_decision, :dispatch, "run has no granted decision")}

  defp match(decision, approval) do
    expected = %{
      "decision_id" => decision["id"],
      "proposal_digest" => decision["proposal_digest"],
      "revision" => Integer.to_string(decision["state_revision"]),
      "expires_at" => Integer.to_string(decision["expires_at"])
    }

    if Enum.all?(expected, fn {key, value} -> Map.get(approval, key) == value end) do
      :ok
    else
      {:error,
       Error.new(:approval_mismatch, :dispatch, "approval does not name the granted decision")}
    end
  end

  defp fetch(room, role) do
    id = Map.fetch!(room.ids, role)

    case Map.fetch(room.consumed, id) do
      {:ok, consumed} -> {:ok, consumed}
      :error -> {:error, Error.new(:thing_not_discovered, :scenario, "Thing was not discovered")}
    end
  end

  defp observe(thing, name, unit, now) do
    with {:ok, reading} <-
           ConsumedThing.read_property(thing, name, context("observe:" <> name, now)) do
      Observation.new(
        id: "room-#{name}-#{now}",
        thing_id: ThingDescription.id(ConsumedThing.thing_description(thing)),
        affordance_type: :property,
        affordance_name: name,
        observed_at: now,
        value: reading.payload,
        unit: unit,
        quality: :good
      )
    end
  end

  defp meter(_room, false, _now), do: {:ok, nil}

  defp meter(room, true, now) do
    with {:ok, meter} <- fetch(room, :meter), do: observe(meter, "power", "W", now)
  end

  defp exchange(room, observations) do
    observations
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while({:ok, []}, fn observation, {:ok, acc} ->
      with {:ok, proposal} <-
             Wire.proposal_from_observation(observation, room.scope, room.epoch,
               sequence: room.watermark
             ),
           {:ok, delivery} <- Channel.send_value(room.channel, "edge", "cloud", proposal) do
        {:cont, {:ok, acc ++ [delivery]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp infer(actuator, temperature, power, params, now) do
    td = ConsumedThing.thing_description(actuator)
    document = ThingDescription.to_map(td)
    fields = Observation.to_map(temperature)
    budget = Nx.tensor(params[:power_budget] * 1.0, type: :f32)
    power_thing = if power, do: Observation.to_map(power).thing_id, else: fields.thing_id

    with {:ok, temperature_feature} <- feature(fields.thing_id, "temperature", "Cel", :error),
         {:ok, power_feature} <- feature(power_thing, "power", "W", {:fill, 0.0}),
         {:ok, schema} <- Schema.new(features: [temperature_feature, power_feature], max_rows: 1),
         {:ok, row} <- Row.new(fields.observed_at, row_values(temperature, power)),
         {:ok, encoded} <- Encoder.encode([row], schema),
         tensor <-
           Nx.Defn.jit_apply(&Scenario.target/2, [encoded, budget], compiler: Nx.Defn.Evaluator),
         {:ok, output_schema} <- DataSchema.new(document["actions"]["setTarget"]["input"]),
         {:ok, output} <-
           OutputSchema.new(
             kind: :action_proposal,
             thing_id: ThingDescription.id(td),
             affordance_type: :action,
             affordance_name: "setTarget",
             data_schema: output_schema,
             dtype: :f32
           ),
         {:ok, proposal} <-
           Decoder.decode(tensor, output, id: "room-proposal-#{now}", proposed_at: now) do
      {:ok, encoded, proposal}
    end
  end

  defp feature(thing_id, name, unit, missing) do
    with {:ok, schema} <- DataSchema.new(%{"type" => "number", "unit" => unit}) do
      Feature.new(
        name: name,
        thing_id: thing_id,
        affordance_type: :property,
        affordance_name: name,
        data_schema: schema,
        accepted_quality: [:good],
        missing: missing
      )
    end
  end

  defp row_values(temperature, nil), do: %{"temperature" => temperature}
  defp row_values(temperature, power), do: %{"temperature" => temperature, "power" => power}

  defp decide(room, proposal, params, now) do
    Policy.decide(room.policy, proposal,
      principal: params[:principal],
      watermark: room.watermark,
      state_revision: room.state_revision,
      now: now,
      ttl: params[:ttl_ms]
    )
  end

  defp decision_view({:ok, decision}, fields) do
    %{
      "id" => decision.id,
      "status" => Atom.to_string(decision.status),
      "thing_id" => decision.thing_id,
      "action_name" => decision.action_name,
      "input" => decision.input,
      "proposal_id" => fields.id,
      "proposal_digest" => decision.proposal_digest,
      "principal" => Atom.to_string(decision.principal),
      "watermark" => decision.watermark,
      "state_revision" => decision.state_revision,
      "expires_at" => decision.expires_at
    }
  end

  defp decision_view({:error, _error}, _fields), do: nil

  defp decision_summary({:ok, decision}),
    do: [{"Decision", "#{decision.id} granted, awaiting explicit approval"}]

  defp decision_summary({:error, %Error{code: code}}),
    do: [{"Decision", "refused: #{code}"}]

  defp decision_ok?({:ok, _decision}), do: true
  defp decision_ok?({:error, _error}), do: false
  defp decision_note({:ok, _decision}), do: "policy granted one decision"
  defp decision_note({:error, %Error{code: code}}), do: "policy refused: #{code}"
  defp decision_status({:ok, _decision}), do: :granted
  defp decision_status({:error, %Error{code: code}}), do: code

  defp context(label, now),
    do: Context.new!(request_id: "room:#{label}:#{now}", deadline: now + 5_000)
end
