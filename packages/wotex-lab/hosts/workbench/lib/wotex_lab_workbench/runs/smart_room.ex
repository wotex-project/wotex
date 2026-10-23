defmodule WotexLabWorkbench.Runs.SmartRoom do
  @moduledoc """
  The smart-room cycle split at the authorization seam.

  `run/2` resolves the room's configured Property bindings, then reads them through the
  runtime, exchanges the observations over the continuum channel, encodes one
  Nx row, evaluates the public room rule `Wotex.Lab.SmartRoom.Scenario.target/2`,
  decodes an inert `setTarget` proposal and asks the room policy for a
  decision. It stops there: a granted decision is presented for explicit
  approval and nothing is dispatched. `dispatch/3` executes one approved
  decision through `Wotex.Lab.SmartRoom.Policy.dispatch/4`, which refuses a
  replayed, expired, revoked or stale approval, records the result on the
  channel and reads the target afterwards. An attempted dispatch is terminal
  even if recording or readback fails; its Action cannot be retried.
  """

  alias Wotex.{DataSchema, ThingDescription}
  alias Wotex.Lab.Continuum.{Channel, Wire}
  alias Wotex.Lab.Error
  alias Wotex.Lab.SmartRoom.{Policy, Scenario}
  alias Wotex.Nx.{ActionProposal, Decoder, Encoder, Feature, Observation, OutputSchema, Row, Schema}
  alias Wotex.Runtime.{ConsumedThing, Context, Result}
  alias WotexLabWorkbench.{Canvas, Connections, Preview, Runs}

  @backend Nx.BinaryBackend

  @doc "Observes, exchanges, infers and decides; never dispatches."
  @spec run(keyword(), map()) :: {:ok, map()} | {:error, term()}
  def run(params, room) do
    with {:ok, sources} <- sources(room, Keyword.fetch!(params, :meter)) do
      run_cycle(params, room, sources)
    end
  end

  defp run_cycle(params, room, sources) do
    now = System.monotonic_time(:millisecond)
    meter? = Keyword.fetch!(params, :meter)

    {outcome, elapsed} =
      Runs.measure(fn ->
        with {:ok, temperature} <- observe(sources.temperature, "Cel", now),
             {:ok, power} <- meter(sources.power, meter?, now),
             {:ok, deliveries} <- exchange(room, [temperature, power]),
             {:ok, encoded, proposal} <- infer(sources, temperature, power, params, now) do
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
             {"Temperature", source_value(room, sources.temperature, temperature.value, "°C")},
             {"Meter",
              if(power,
                do: source_value(room, sources.power, power.value, "W"),
                else: "Off"
              )},
             {"Power budget", Preview.format(params[:power_budget]) <> " W"},
             {"Proposal", "#{fields.action_name} · #{Preview.format(fields.input)} °C"},
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
           power_observed: not is_nil(power),
           connection_revision: room.connections.revision
         },
         inputs:
           [
             "fixture:loopback/thing-description.json",
             "room:" <> room.id,
             "connections:" <> Connections.digest(room.connections)
           ] ++ Connections.inputs(room.connections, Map.values(room.things)),
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
         {:ok, target} <- fetch(room, "proposal"),
         {:ok, outcome} <-
           Policy.dispatch(
             room.policy,
             decision["id"],
             [now: now, watermark: room.watermark, state_revision: room.state_revision],
             fn ->
               ConsumedThing.invoke_action(
                 target.consumed,
                 decision["action_name"],
                 decision["input"],
                 context("decision:" <> decision["id"], now)
               )
             end
           ) do
      {:ok, complete_dispatch(outcome, run, room, target, now)}
    else
      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def dispatch(_, _, _),
    do: {:error, Error.new(:no_decision, :dispatch, "run has no granted decision")}

  defp complete_dispatch(outcome, run, room, target, now) do
    completed =
      with {:ok, result} <-
             Wire.result_from_runtime(
               wire_outcome(outcome),
               "room-result-" <> run.proposal["id"],
               run.proposal["id"],
               room.scope,
               DateTime.add(room.epoch, now, :millisecond)
             ),
           {:ok, _} <- Channel.send_value(room.channel, "edge", "cloud", result),
           :ok <- successful_dispatch(outcome),
           {:ok, effect} <-
             ConsumedThing.read_property(target.consumed, "target", context("effect", now)) do
        %{status: :dispatched, effect: effect.payload, error: nil}
      else
        {:error, reason} ->
          %{
            status: :failed,
            effect: nil,
            error:
              Error.new(:dispatch_failed, :dispatch, "Dispatch or readback failed; no retry",
                details: %{reason: Runs.plain(reason)}
              )
          }
      end

    {status, result} = outcome
    Map.put(completed, :dispatch, [Atom.to_string(status), Runs.plain(result)])
  end

  defp wire_outcome({:ok, %Result{payload: :written} = result}),
    do: {:ok, %{result | payload: "written"}}

  defp wire_outcome(outcome), do: outcome

  defp successful_dispatch({:ok, %Result{status: status}}) when status in [:ok, :accepted],
    do: :ok

  defp successful_dispatch({:error, reason}), do: {:error, reason}

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

  defp sources(room, meter?) do
    with {:ok, temperature} <- fetch(room, "temperature"),
         {:ok, proposal} <- fetch(room, "proposal"),
         {:ok, power} <- power_source(room, meter?) do
      {:ok, %{temperature: temperature, proposal: proposal, power: power}}
    end
  end

  defp power_source(_, false), do: {:ok, nil}
  defp power_source(room, true), do: fetch(room, "power")

  defp fetch(room, port) do
    with {:ok, binding} <- Connections.fetch(room.connections, Map.values(room.things), port),
         {:ok, consumed} <- Map.fetch(room.consumed, binding.thing_id) do
      {:ok, Map.put(binding, :consumed, consumed)}
    else
      :error -> {:error, Error.new(:thing_not_discovered, :scenario, "Thing was not discovered")}
      {:error, error} -> {:error, error}
    end
  end

  defp observe(source, unit, now) do
    with {:ok, reading} <-
           ConsumedThing.read_property(
             source.consumed,
             source.affordance,
             context("observe:" <> source.affordance, now)
           ) do
      Observation.new(
        id: "room-#{source.affordance}-#{now}",
        thing_id: source.thing_id,
        affordance_type: :property,
        affordance_name: source.affordance,
        observed_at: now,
        value: reading.payload,
        unit: unit,
        quality: :good
      )
    end
  end

  defp meter(_, false, _), do: {:ok, nil}
  defp meter(source, true, now), do: observe(source, "W", now)

  defp source_value(room, source, value, unit) do
    title = Canvas.title(Map.fetch!(room.things, source.thing))
    "#{title} · #{source.affordance}: #{Preview.format(value)} #{unit}"
  end

  defp exchange(room, observations) do
    delivered =
      observations
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce_while({:ok, []}, fn observation, {:ok, acc} ->
        with {:ok, proposal} <-
               Wire.proposal_from_observation(observation, room.scope, room.epoch,
                 sequence: room.watermark
               ),
             {:ok, delivery} <- Channel.send_value(room.channel, "edge", "cloud", proposal) do
          {:cont, {:ok, [delivery | acc]}}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, reversed} <- delivered, do: {:ok, Enum.reverse(reversed)}
  end

  defp infer(sources, temperature, power, params, now) do
    td = ConsumedThing.thing_description(sources.proposal.consumed)
    document = ThingDescription.to_map(td)
    fields = Observation.to_map(temperature)
    budget = Nx.tensor(params[:power_budget] * 1.0, type: :f32)

    power_fields =
      if power,
        do: Observation.to_map(power),
        else: %{thing_id: fields.thing_id, affordance_name: "power"}

    power_schema = if power, do: sources.power.schema, else: %{"type" => "number", "unit" => "W"}

    with {:ok, temperature_feature} <-
           feature("temperature", fields, sources.temperature.schema, :error),
         {:ok, power_feature} <- feature("power", power_fields, power_schema, {:fill, 0.0}),
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

  defp feature(name, fields, declaration, missing) do
    with {:ok, schema} <- DataSchema.new(declaration) do
      Feature.new(
        name: name,
        thing_id: fields.thing_id,
        affordance_type: :property,
        affordance_name: fields.affordance_name,
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

  defp decision_view({:error, _}, _), do: nil

  defp decision_summary({:ok, decision}),
    do: [{"Decision", "#{decision.id} granted, awaiting explicit approval"}]

  defp decision_summary({:error, %Error{code: code}}),
    do: [{"Decision", "refused: #{code}"}]

  defp decision_ok?({:ok, _}), do: true
  defp decision_ok?({:error, _}), do: false
  defp decision_note({:ok, _}), do: "policy granted one decision"
  defp decision_note({:error, %Error{code: code}}), do: "policy refused: #{code}"
  defp decision_status({:ok, _}), do: :granted
  defp decision_status({:error, %Error{code: code}}), do: code

  defp context(label, now),
    do: Context.new!(request_id: "room:#{label}:#{now}", deadline: now + 5_000)
end
