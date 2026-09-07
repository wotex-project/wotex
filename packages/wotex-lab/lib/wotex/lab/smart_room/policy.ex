defmodule Wotex.Lab.SmartRoom.Policy do
  @moduledoc """
  Decision records that bind a numerical proposal to one authorized dispatch.

  A decision binds the proposal digest, Thing and Action, input, principal,
  observation watermark, simulated state revision and an expiry. `dispatch/3`
  executes the caller's dispatcher at most once for a decision that is still
  granted, unexpired, unrevoked and current with respect to the watermark and
  revision presented at dispatch time. Denied, expired, revoked, stale and
  conflicting attempts dispatch nothing and are recorded separately from the
  dispatch acknowledgement and the observed effect. Grants live only in this
  process: a restart erases them and nothing restores a grant implicitly.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Nx.ActionProposal

  @type decision :: %{
          id: String.t(),
          proposal_digest: String.t(),
          thing_id: String.t(),
          action_name: String.t(),
          input: term(),
          principal: term(),
          watermark: integer(),
          state_revision: integer(),
          expires_at: integer(),
          status: :granted | :dispatched | :revoked,
          attempts: [map()]
        }

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, :default)},
      start: {__MODULE__, :start_link, [opts]},
      restart: Keyword.get(opts, :restart, :transient),
      type: :worker
    }
  end

  @doc "Starts a policy with `:allowed` principals, `:limits` (`min`/`max` per action name) and an optional `:name`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Decides on a proposal for `principal` at `now` with the current watermark and revision.

  The decision is granted when the principal is allowed, the input is inside
  the action's limits, and no granted decision for the same Thing and Action
  is outstanding (a conflicting proposal is refused, not queued).
  """
  @spec decide(GenServer.server(), ActionProposal.t(), keyword()) ::
          {:ok, decision()} | {:error, Error.t()}
  def decide(policy, proposal, opts), do: GenServer.call(policy, {:decide, proposal, Map.new(opts)})

  @doc "Executes `dispatcher` exactly once for a current, granted decision."
  @spec dispatch(GenServer.server(), String.t(), keyword(), (-> term())) ::
          {:ok, term()} | {:error, Error.t()}
  def dispatch(policy, decision_id, opts, dispatcher) when is_function(dispatcher, 0),
    do: GenServer.call(policy, {:dispatch, decision_id, Map.new(opts), dispatcher})

  @doc "Revokes a granted decision."
  @spec revoke(GenServer.server(), String.t()) :: :ok | {:error, Error.t()}
  def revoke(policy, decision_id), do: GenServer.call(policy, {:revoke, decision_id})

  @doc "Returns every decision record and every refused attempt."
  @spec records(GenServer.server()) :: %{decisions: [decision()], refusals: [map()]}
  def records(policy), do: GenServer.call(policy, :records)

  @doc "Computes the canonical digest of a proposal's binding fields."
  @spec proposal_digest(ActionProposal.t()) :: String.t()
  def proposal_digest(proposal) do
    fields = ActionProposal.to_map(proposal)

    canonical =
      [fields.id, fields.thing_id, fields.action_name, fields.input, fields.proposed_at]
      |> :erlang.term_to_binary([:deterministic])

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, canonical), case: :lower)
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       allowed: MapSet.new(Keyword.get(opts, :allowed, [])),
       limits: Keyword.get(opts, :limits, %{}),
       decisions: %{},
       order: [],
       refusals: [],
       sequence: 0
     }}
  end

  @impl GenServer
  def handle_call({:decide, proposal, context}, _from, state) do
    fields = ActionProposal.to_map(proposal)
    limits = Map.get(state.limits, fields.action_name)

    cond do
      not MapSet.member?(state.allowed, context.principal) ->
        refuse(state, :principal_denied, fields.id)

      is_nil(limits) ->
        refuse(state, :action_not_governed, fields.id)

      not inside?(fields.input, limits) ->
        refuse(state, :input_outside_limits, fields.id)

      outstanding?(state, fields.thing_id, fields.action_name) ->
        refuse(state, :conflicting_decision, fields.id)

      true ->
        grant(state, proposal, fields, context)
    end
  end

  def handle_call({:dispatch, decision_id, current, dispatcher}, _from, state) do
    case Map.fetch(state.decisions, decision_id) do
      :error ->
        refuse(state, :unknown_decision, decision_id)

      {:ok, decision} ->
        case dispatchable(decision, current) do
          :ok ->
            outcome = dispatcher.()
            attempt = %{at: current.now, outcome: outcome}
            dispatched = %{decision | status: :dispatched, attempts: [attempt | decision.attempts]}
            {:reply, {:ok, outcome}, put_in(state, [:decisions, decision_id], dispatched)}

          {:error, reason} ->
            refuse(state, reason, decision_id)
        end
    end
  end

  def handle_call({:revoke, decision_id}, _from, state) do
    case Map.fetch(state.decisions, decision_id) do
      {:ok, %{status: :granted} = decision} ->
        {:reply, :ok, put_in(state, [:decisions, decision_id], %{decision | status: :revoked})}

      _other ->
        refuse(state, :not_revocable, %{decision_id: decision_id})
    end
  end

  def handle_call(:records, _from, state) do
    {:reply,
     %{
       decisions: state.order |> Enum.reverse() |> Enum.map(&state.decisions[&1]),
       refusals: Enum.reverse(state.refusals)
     }, state}
  end

  defp grant(state, proposal, fields, context) do
    sequence = state.sequence + 1
    id = "decision-#{sequence}"

    decision = %{
      id: id,
      proposal_digest: proposal_digest(proposal),
      thing_id: fields.thing_id,
      action_name: fields.action_name,
      input: fields.input,
      principal: context.principal,
      watermark: context.watermark,
      state_revision: context.state_revision,
      expires_at: context.now + Map.get(context, :ttl, 5_000),
      status: :granted,
      attempts: []
    }

    state = %{
      state
      | sequence: sequence,
        decisions: Map.put(state.decisions, id, decision),
        order: [id | state.order]
    }

    {:reply, {:ok, decision}, state}
  end

  defp dispatchable(decision, current) do
    cond do
      decision.status == :dispatched -> {:error, :already_dispatched}
      decision.status == :revoked -> {:error, :revoked}
      current.now > decision.expires_at -> {:error, :expired}
      current.watermark != decision.watermark -> {:error, :stale_observation}
      current.state_revision != decision.state_revision -> {:error, :stale_state}
      true -> :ok
    end
  end

  defp outstanding?(state, thing_id, action_name) do
    Enum.any?(state.decisions, fn {_id, decision} ->
      decision.status == :granted and decision.thing_id == thing_id and
        decision.action_name == action_name
    end)
  end

  defp inside?(input, %{min: min, max: max}) when is_number(input),
    do: input >= min and input <= max

  defp inside?(_input, _limits), do: false

  defp refuse(state, reason, subject) do
    refusal = %{reason: reason, subject: subject}
    error = Error.new(reason, :policy, "decision refused", details: %{subject: subject})
    {:reply, {:error, error}, %{state | refusals: [refusal | state.refusals]}}
  end
end
