# Compiled only when the optional package behind this seam is present;
# the base package stays usable without it.
if Code.ensure_loaded?(Wotex.Runtime.Transport) and
     Code.ensure_loaded?(Wotex.Directory.Repository) and
     Code.ensure_loaded?(WotexContinuum.Codec) do
  defmodule Wotex.Lab.SmartRoom.Scenario do
    @moduledoc """
    The canonical smart-room run: discover, consume, observe, exchange, infer,
    decide, dispatch, and observe the effect, every step inspectable.

    Things are discovered from an explicit Directory service; each admitted Thing
    Description identifies a Thing by its own `id`, never by a name-only join.
    Runtime `ConsumedThing` values are built from caller-supplied binding
    profiles, transports and credential ports. A temperature observation and, when
    an energy meter is discovered, a power observation become continuum proposals
    on the channel and one Nx row: temperature is required, power is a filled
    feature whose mask row is `0` without a meter. The room rule raises the target
    by one degree, or lowers it by one when observed power exceeds the budget; a
    filled power value can never trigger the budget. The `setTarget` proposal for
    the actuator then becomes a policy decision that is dispatched at most once at
    the edge. Only the `action_result` travels to the cloud host afterwards: an
    `action_intent` sent to a host is a request to execute, so the edge never
    forwards one for an action it has already dispatched. The effect is read from
    the actuator afterwards. Nothing in this module grants
    authority: the policy does, once, per decision.
    """

    import Nx.Defn

    alias Wotex.{DataSchema, Directory, ThingDescription}
    alias Wotex.Lab.Continuum.{Channel, Wire}
    alias Wotex.Lab.{Error, Telemetry}
    alias Wotex.Lab.SmartRoom.Policy

    alias Wotex.Nx.{
      ActionProposal,
      Decoder,
      Encoder,
      Feature,
      Observation,
      OutputSchema,
      Row,
      Schema
    }

    alias Wotex.Runtime.{ConsumedThing, Context, Result}
    alias WotexContinuum.ExecutionScope

    @doc "Discovers every active Thing Description in the directory and builds ConsumedThings keyed by TD id."
    @spec discover(Directory.Service.t(), Directory.Context.t(), keyword()) ::
            {:ok, %{String.t() => ConsumedThing.t()}} | {:error, term()}
    def discover(service, context, opts) do
      with {:ok, entries} <- entries(service, context, nil, []) do
        Enum.reduce_while(entries, {:ok, %{}}, &consume(&1, &2, opts))
      end
    end

    defp consume(entry, {:ok, acc}, opts) do
      td = entry.thing_description

      case ConsumedThing.new(td,
             profiles: Keyword.fetch!(opts, :profiles),
             transports: Keyword.fetch!(opts, :transports),
             credentials: Keyword.fetch!(opts, :credentials)
           ) do
        {:ok, consumed} -> {:cont, {:ok, Map.put(acc, ThingDescription.id(td), consumed)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end

    @doc """
    The room's target rule: one degree above the observed temperature, or one
    degree below it when observed power exceeds the budget. The power mask row
    gates the comparison, so a filled power value never counts as observed.
    """
    @spec target(
            {{Nx.Tensor.t(), Nx.Tensor.t()}, {Nx.Tensor.t(), Nx.Tensor.t()}, Nx.Tensor.t()},
            Nx.Tensor.t()
          ) :: Nx.Tensor.t()
    defn target({{temperatures, powers}, {_temperature_masks, power_masks}, _quality}, budget) do
      over_budget = power_masks[0] * (powers[0] > budget)
      Nx.select(over_budget, temperatures[0] - 1.0, temperatures[0] + 1.0)
    end

    @doc """
    Runs one control cycle and returns every record.

    Options: `:things` (from `discover/3`), `:thermostat_id`, `:actuator_id`,
    optional `:meter_id` (an MQTT energy meter exposing `power` in watts) and
    `:power_budget` (watts, 2000.0),
    `:channel`, `:edge`, `:cloud`, `:policy`, `:principal`, `:now` (monotonic
    milliseconds), `:epoch` (DateTime anchoring `now`), `:scope`
    (`WotexContinuum.ExecutionScope`), `:watermark`, `:state_revision`, `:ttl`.
    """
    @spec run(keyword()) :: {:ok, map()} | {:error, term()}
    def run(opts) do
      things = Keyword.fetch!(opts, :things)
      now = Keyword.fetch!(opts, :now)

      with {:ok, thermostat} <- fetch_thing(things, Keyword.fetch!(opts, :thermostat_id)),
           {:ok, actuator} <- fetch_thing(things, Keyword.fetch!(opts, :actuator_id)),
           {:ok, reading} <-
             ConsumedThing.read_property(thermostat, "temperature", context("observe", now)),
           {:ok, observation} <- observation(thermostat, reading, "temperature", "Cel", now),
           {:ok, power} <- meter(things, opts, now),
           {:ok, proposal_deliveries} <- exchange(opts, [observation, power]),
           {:ok, action_proposal} <- infer(actuator, observation, power, opts, now),
           {:ok, decision} <-
             Policy.decide(Keyword.fetch!(opts, :policy), action_proposal, decision_context(opts)),
           {:ok, dispatch} <- dispatch(opts, decision, actuator, action_proposal),
           {:ok, records} <- record(opts, action_proposal, dispatch),
           {:ok, effect} <- ConsumedThing.read_property(actuator, "target", context("effect", now)) do
        {:ok,
         %{
           observation: observation,
           power_observation: power,
           proposal_deliveries: proposal_deliveries,
           action_proposal: action_proposal,
           decision: decision,
           dispatch: dispatch,
           records: records,
           effect: effect.payload
         }}
      end
    end

    defp entries(service, context, cursor, acc) do
      options = if cursor, do: [cursor: cursor, limit: 50], else: [limit: 50]

      case Directory.list(service, context, options) do
        {:ok, %{entries: entries, next_cursor: nil}} ->
          {:ok, acc ++ entries}

        {:ok, %{entries: entries, next_cursor: next}} ->
          entries(service, context, next, acc ++ entries)

        {:error, error} ->
          {:error, error}
      end
    end

    defp fetch_thing(things, id) do
      case Map.fetch(things, id) do
        {:ok, consumed} ->
          {:ok, consumed}

        :error ->
          {:error,
           Error.new(:thing_not_discovered, :scenario, "Thing was not discovered",
             details: %{thing_id: id}
           )}
      end
    end

    defp observation(thing, %Result{payload: value}, name, unit, now) do
      Observation.new(
        id: "room-#{name}-#{now}",
        thing_id: ThingDescription.id(ConsumedThing.thing_description(thing)),
        affordance_type: :property,
        affordance_name: name,
        observed_at: now,
        value: value,
        unit: unit,
        quality: :good
      )
    end

    defp meter(things, opts, now) do
      case Keyword.get(opts, :meter_id) do
        nil ->
          {:ok, nil}

        meter_id ->
          with {:ok, meter} <- fetch_thing(things, meter_id),
               {:ok, reading} <- ConsumedThing.read_property(meter, "power", context("meter", now)) do
            observation(meter, reading, "power", "W", now)
          end
      end
    end

    defp exchange(opts, observations) do
      exchanged =
        observations
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce_while({:ok, []}, fn observation, {:ok, acc} ->
          case exchange_one(opts, observation) do
            {:ok, delivery} -> {:cont, {:ok, [delivery | acc]}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)

      with {:ok, deliveries} <- exchanged, do: {:ok, Enum.reverse(deliveries)}
    end

    defp exchange_one(opts, observation) do
      with {:ok, proposal} <-
             Wire.proposal_from_observation(
               observation,
               Keyword.fetch!(opts, :scope),
               Keyword.fetch!(opts, :epoch),
               sequence: Keyword.fetch!(opts, :watermark)
             ) do
        Channel.send_value(
          Keyword.fetch!(opts, :channel),
          Keyword.fetch!(opts, :edge),
          Keyword.fetch!(opts, :cloud),
          proposal
        )
      end
    end

    defp infer(actuator, observation, power, opts, now) do
      actuator_td = ConsumedThing.thing_description(actuator)
      document = ThingDescription.to_map(actuator_td)
      fields = Observation.to_map(observation)
      budget = Nx.tensor(Keyword.get(opts, :power_budget, 2_000.0) * 1.0, type: :f32)

      with {:ok, temperature} <- feature(fields.thing_id, "temperature", "Cel", :error),
           {:ok, power_feature} <-
             feature(meter_id(power, fields.thing_id), "power", "W", {:fill, 0.0}),
           {:ok, schema} <- Schema.new(features: [temperature, power_feature], max_rows: 1),
           {:ok, row} <- Row.new(fields.observed_at, row_values(observation, power)),
           {:ok, encoded} <-
             Telemetry.span(:nx, :encode, %{profile: :smart_room}, fn ->
               Encoder.encode([row], schema)
             end),
           tensor <-
             Telemetry.span(:nx, :inference, %{profile: :smart_room}, fn ->
               Nx.Defn.jit_apply(&target/2, [encoded, budget], compiler: Nx.Defn.Evaluator)
             end),
           {:ok, output_schema} <- DataSchema.new(document["actions"]["setTarget"]["input"]),
           {:ok, output} <-
             OutputSchema.new(
               kind: :action_proposal,
               thing_id: ThingDescription.id(actuator_td),
               affordance_type: :action,
               affordance_name: "setTarget",
               data_schema: output_schema,
               dtype: :f32
             ) do
        Telemetry.span(:nx, :decode, %{profile: :smart_room}, fn ->
          Decoder.decode(tensor, output, id: "room-proposal-#{now}", proposed_at: now)
        end)
      end
    end

    defp feature(thing_id, name, unit, missing) do
      with {:ok, input_schema} <- DataSchema.new(%{"type" => "number", "unit" => unit}) do
        Feature.new(
          name: name,
          thing_id: thing_id,
          affordance_type: :property,
          affordance_name: name,
          data_schema: input_schema,
          accepted_quality: [:good],
          missing: missing
        )
      end
    end

    defp meter_id(nil, fallback), do: fallback
    defp meter_id(power, _), do: Observation.to_map(power).thing_id

    defp row_values(observation, nil), do: %{"temperature" => observation}
    defp row_values(observation, power), do: %{"temperature" => observation, "power" => power}

    defp decision_context(opts) do
      [
        principal: Keyword.fetch!(opts, :principal),
        watermark: Keyword.fetch!(opts, :watermark),
        state_revision: Keyword.fetch!(opts, :state_revision),
        now: Keyword.fetch!(opts, :now),
        ttl: Keyword.get(opts, :ttl, 5_000)
      ]
    end

    defp dispatch(opts, decision, actuator, action_proposal) do
      fields = ActionProposal.to_map(action_proposal)
      now = Keyword.fetch!(opts, :now)

      current = [
        now: now,
        watermark: Keyword.fetch!(opts, :watermark),
        state_revision: Keyword.fetch!(opts, :state_revision)
      ]

      Policy.dispatch(Keyword.fetch!(opts, :policy), decision.id, current, fn ->
        ConsumedThing.invoke_action(
          actuator,
          fields.action_name,
          fields.input,
          context("decision:" <> decision.id, now)
        )
      end)
    end

    defp record(opts, action_proposal, outcome) do
      scope = Keyword.fetch!(opts, :scope)
      epoch = Keyword.fetch!(opts, :epoch)
      channel = Keyword.fetch!(opts, :channel)
      edge = Keyword.fetch!(opts, :edge)
      cloud = Keyword.fetch!(opts, :cloud)
      fields = ActionProposal.to_map(action_proposal)
      at = DateTime.add(epoch, Keyword.fetch!(opts, :now), :millisecond)

      with {:ok, result} <-
             Wire.result_from_runtime(outcome, "room-result-#{fields.id}", fields.id, scope, at),
           {:ok, result_delivery} <- Channel.send_value(channel, edge, cloud, result) do
        {:ok, %{result: result_delivery}}
      end
    end

    defp context(label, now),
      do: Context.new!(request_id: "room:#{label}:#{now}", deadline: now + 5_000)

    @doc false
    @spec scope(String.t(), DateTime.t()) :: ExecutionScope.t()
    def scope(node_id, at) do
      {:ok, mode} = WotexContinuum.Mode.from_map(%{deployment: :hybrid, connectivity: :connected})

      {:ok, scope} =
        ExecutionScope.from_map(%{
          execution_id: "room-#{node_id}",
          node_id: node_id,
          mode: mode,
          observed_at: at
        })

      scope
    end
  end
end
