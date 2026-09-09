defmodule Wotex.Lab.Formal.Replay do
  @moduledoc """
  Replays a model trace as an ordered, finite simulator run under WLB.05.

  Each step of a `show path` trace names the rule that fired and the model
  state it produced. The replay executes the concrete counterpart of every
  rule against the Lab decision policy and a simulated actuator: ticks
  advance time, band rules change the reading and the observation watermark,
  energy rules change the state revision, proposals go through
  `Wotex.Lab.SmartRoom.Policy.decide/3`, and dispatches go through
  `Policy.dispatch/4` so that the policy, not the trace, decides whether an
  effect happens. After every step the concrete room is abstracted and
  compared with the trace; the first mismatch is recorded as a divergence
  and the replay stops. A divergence is an abstraction or replay finding,
  never an authorization; a converged replay proves only that the simulator
  can follow that trace.
  """

  alias Wotex.DataSchema
  alias Wotex.Lab.Error
  alias Wotex.Lab.Formal.Abstraction
  alias Wotex.Lab.SmartRoom.Policy
  alias Wotex.Nx.{Decoder, OutputSchema}

  @thing_id "urn:wotex:lab:formal:room"
  @second 1_000
  @readings %{cold: 17.0, comfort: 21.0, hot: 25.0}

  @type outcome :: %{
          status: :converged | :diverged,
          steps: non_neg_integer(),
          divergence:
            %{
              step: non_neg_integer(),
              rule: String.t() | nil,
              expected: Abstraction.t(),
              observed: Abstraction.t()
            }
            | nil,
          refusals: [%{step: non_neg_integer(), rule: String.t(), code: atom()}],
          effects: non_neg_integer()
        }

  @doc "The policy limits a replay needs: both model actions with a unit input range."
  @spec policy_limits() :: map()
  def policy_limits, do: %{"heat" => %{min: 0, max: 1}, "cool" => %{min: 0, max: 1}}

  @doc "Replays trace steps against `policy`; `:budget` (2000.0) and `:max_age` (3) are the model bounds."
  @spec run(GenServer.server(), [map()], keyword()) :: {:ok, outcome()} | {:error, Error.t()}
  def run(policy, steps, opts \\ [])

  def run(policy, [%{state: _, term: term} | rest], opts) when is_list(rest) do
    max_age = Keyword.get(opts, :max_age, 3)

    concrete = %{
      temperature: @readings.comfort,
      heater: :off,
      cooler: :off,
      power: 0.0,
      budget: Keyword.get(opts, :budget, 2_000.0),
      decision: :no_decision,
      age_ms: 0,
      grants: 0,
      effects: 0,
      now: 0,
      watermark: 1,
      state_revision: 1,
      decision_id: nil,
      max_age: max_age
    }

    with {:ok, expected} <- Abstraction.from_term(term),
         :ok <- compare(concrete, expected, 0, nil) do
      walk(rest, policy, concrete, 1, [])
    else
      {:diverged, divergence} ->
        {:ok, %{status: :diverged, steps: 0, divergence: divergence, refusals: [], effects: 0}}

      {:error, error} ->
        {:error, error}
    end
  end

  def run(_, _, _),
    do: {:error, Error.new(:invalid_trace, :replay, "a trace needs at least its initial state")}

  defp walk([], _, concrete, index, refusals),
    do:
      {:ok,
       %{
         status: :converged,
         steps: index - 1,
         divergence: nil,
         refusals: Enum.reverse(refusals),
         effects: concrete.effects
       }}

  defp walk([%{rule: rule, term: term} | rest], policy, concrete, index, refusals) do
    with {:ok, expected} <- Abstraction.from_term(term),
         {:ok, concrete, refusal} <- apply_rule(rule, policy, concrete) do
      refusals =
        if refusal, do: [%{step: index, rule: rule, code: refusal} | refusals], else: refusals

      case compare(concrete, expected, index, rule) do
        :ok ->
          walk(rest, policy, concrete, index + 1, refusals)

        {:diverged, divergence} ->
          {:ok,
           %{
             status: :diverged,
             steps: index,
             divergence: divergence,
             refusals: Enum.reverse(refusals),
             effects: concrete.effects
           }}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp apply_rule(rule, _, concrete) when rule in ["tick", "age"],
    do: {:ok, %{concrete | now: concrete.now + @second, age_ms: concrete.age_ms + @second}, nil}

  defp apply_rule("warm", _, concrete), do: {:ok, reading(concrete, :comfort), nil}
  defp apply_rule("heatUp", _, concrete), do: {:ok, reading(concrete, :hot), nil}
  defp apply_rule("chill", _, concrete), do: {:ok, reading(concrete, :comfort), nil}
  defp apply_rule("coolDown", _, concrete), do: {:ok, reading(concrete, :cold), nil}

  defp apply_rule("energyOver", _, concrete),
    do:
      {:ok,
       %{
         concrete
         | power: concrete.budget + 500.0,
           heater: :off,
           state_revision: concrete.state_revision + 1
       }, nil}

  defp apply_rule("energyWithin", _, concrete),
    do: {:ok, %{concrete | power: 0.0, state_revision: concrete.state_revision + 1}, nil}

  defp apply_rule("proposeHeat", policy, concrete), do: propose(policy, concrete, :heat)
  defp apply_rule("proposeCool", policy, concrete), do: propose(policy, concrete, :cool)
  defp apply_rule("dispatchHeat", policy, concrete), do: dispatch(policy, concrete, :heat)
  defp apply_rule("dispatchCool", policy, concrete), do: dispatch(policy, concrete, :cool)
  defp apply_rule("redeliver", policy, concrete), do: redeliver(policy, concrete)

  defp apply_rule("dispatchWithoutDecision", _, concrete),
    do: {:ok, concrete, :no_decision_to_dispatch}

  defp apply_rule("expire", policy, concrete) do
    case Policy.dispatch(policy, concrete.decision_id, current(concrete), fn ->
           raise "expired decision must not dispatch"
         end) do
      {:error, %Error{code: :expired}} ->
        {:ok, %{concrete | decision: :no_decision, decision_id: nil}, :expired}

      {:error, %Error{code: code}} ->
        {:ok, concrete, code}

      {:ok, _} ->
        {:error, Error.new(:replay_error, :replay, "policy dispatched an expired decision")}
    end
  end

  defp apply_rule("complete", _, concrete),
    do: {:ok, %{concrete | decision: :no_decision, decision_id: nil}, nil}

  defp apply_rule(rule, _, _),
    do:
      {:error,
       Error.new(:unknown_rule, :replay, "trace rule has no simulator counterpart",
         details: %{rule: rule}
       )}

  defp reading(concrete, band),
    do: %{concrete | temperature: Map.fetch!(@readings, band), watermark: concrete.watermark + 1}

  defp propose(policy, concrete, action) do
    with {:ok, proposal} <- proposal(action, concrete) do
      decide = [
        principal: :operator,
        watermark: concrete.watermark,
        state_revision: concrete.state_revision,
        now: concrete.now,
        ttl: concrete.max_age * @second
      ]

      case Policy.decide(policy, proposal, decide) do
        {:ok, decision} ->
          {:ok,
           %{
             concrete
             | decision: {:granted, action, concrete.age_ms},
               decision_id: decision.id,
               grants: concrete.grants + 1
           }, nil}

        {:error, %Error{code: code}} ->
          {:ok, concrete, code}
      end
    end
  end

  defp dispatch(_, %{decision_id: nil} = concrete, _),
    do: {:ok, concrete, :unknown_decision}

  defp dispatch(policy, concrete, action) do
    effect = fn -> {:ok, action} end

    case Policy.dispatch(policy, concrete.decision_id, current(concrete), effect) do
      {:ok, {:ok, ^action}} ->
        switched =
          if action == :heat, do: %{heater: :on, cooler: :off}, else: %{heater: :off, cooler: :on}

        {:ok,
         Map.merge(
           concrete,
           Map.merge(switched, %{
             decision: {:dispatched, action, concrete.age_ms},
             effects: concrete.effects + 1,
             age_ms: 0
           })
         ), nil}

      {:error, %Error{code: code}} ->
        {:ok, concrete, code}
    end
  end

  defp redeliver(_, %{decision_id: nil} = concrete), do: {:ok, concrete, :unknown_decision}

  defp redeliver(policy, concrete) do
    case Policy.dispatch(policy, concrete.decision_id, current(concrete), fn ->
           raise "duplicate delivery must not dispatch"
         end) do
      {:error, %Error{code: code}} ->
        {:ok, concrete, code}

      {:ok, _} ->
        {:error, Error.new(:replay_error, :replay, "policy dispatched a duplicate delivery")}
    end
  end

  defp current(concrete),
    do: [now: concrete.now, watermark: concrete.watermark, state_revision: concrete.state_revision]

  defp proposal(action, concrete) do
    with {:ok, data_schema} <- DataSchema.new(%{"type" => "number", "minimum" => 0, "maximum" => 1}),
         {:ok, schema} <-
           OutputSchema.new(
             kind: :action_proposal,
             thing_id: @thing_id,
             affordance_type: :action,
             affordance_name: Atom.to_string(action),
             data_schema: data_schema,
             dtype: :f32
           ) do
      Decoder.decode(Nx.tensor(1.0, type: :f32), schema,
        id: "replay-#{action}-#{concrete.now}-#{concrete.grants}",
        proposed_at: concrete.now
      )
    end
  end

  defp compare(concrete, expected, index, rule) do
    case Abstraction.room(
           Map.take(concrete, [
             :temperature,
             :heater,
             :cooler,
             :power,
             :budget,
             :decision,
             :age_ms,
             :grants,
             :effects
           ]),
           %{max_age: concrete.max_age, max_grants: 2}
         ) do
      {:ok, ^expected, _} ->
        :ok

      {:ok, observed, _} ->
        {:diverged, %{step: index, rule: rule, expected: expected, observed: observed}}

      {:error, error} ->
        {:error, error}
    end
  end
end
