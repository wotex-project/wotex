defmodule Wotex.Runtime.Implementation.Lifecycle do
  @moduledoc """
  Immutable admitted instance lifecycle with explicit cleanup outcomes.

  The consumer serializes routing and supplies verified observations. These
  values start no process, authenticate no observation and prove no cleanup.
  A stopped generation is terminal; replacement requires a new admitted Plan.
  """

  alias Wotex.Runtime.Implementation.{Error, Grammar, InstanceKey, Plan}

  @fields [:instance_key, :admission_sha256, :state, :reason, :cleanup_outcome]
  @events [:type, :instance_key, :reason, :cleanup_outcome]
  @states ~w(admitted starting ready draining failed stopped rejected)a
  @types ~w(start ready drain cancel revoke expire failure owner_lost transport_lost cleanup_confirmed cleanup_failed)a
  @reasons ~w(invalid_descriptor limit_exceeded unsupported_schema registration_missing
    duplicate_registration incompatible_api incompatible_binding unsupported_requirement
    unsupported_cell artifact_unverified target_mismatch identity_mismatch deployment_mutable
    trust_unavailable trust_expired trust_revoked rollback_denied permission_denied security_denied
    enforcement_unavailable invalid_configuration invalid_admission_inputs stale_admission
    invalid_transition invalid_instance instance_not_ready instance_draining stale_generation
    startup_failed deadline_exceeded overloaded protocol_fault correlation_failed owner_lost
    session_lost effect_unknown cleanup_unconfirmed state_incompatible)a

  @type t :: %__MODULE__{
          instance_key: InstanceKey.t(),
          admission_sha256: String.t(),
          state: atom(),
          reason: atom() | nil,
          cleanup_outcome: atom() | nil
        }
  defstruct @fields

  @doc "Constructs a passive admitted lifecycle from a revalidated implementation Plan."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(plan) do
    with :ok <- Plan.validate(plan) do
      {:ok,
       %__MODULE__{
         instance_key: plan.instance_key,
         admission_sha256: plan.admission.sha256,
         state: :admitted
       }}
    end
  end

  @doc "Applies one closed, generation-bound consumer or binding observation."
  @spec transition(term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def transition(lifecycle, event) do
    with :ok <- validate(lifecycle),
         :ok <- event_shape(event),
         :ok <- correlation(lifecycle.instance_key, event.instance_key),
         {:ok, state, cleanup} <- next(lifecycle.state, event) do
      {:ok,
       %{
         lifecycle
         | state: state,
           cleanup_outcome: cleanup,
           reason: event.reason || lifecycle.reason
       }}
    end
  end

  @doc "Returns the five validated fields as JSON-compatible labels and identity."
  @spec to_map(term()) :: map() | {:error, Error.t()}
  def to_map(lifecycle) do
    with :ok <- validate(lifecycle) do
      %{
        "instance_key" => %{
          "consumer_scope" => lifecycle.instance_key.consumer_scope,
          "instance_id" => lifecycle.instance_key.instance_id,
          "generation" => lifecycle.instance_key.generation
        },
        "admission_sha256" => lifecycle.admission_sha256,
        "state" => Atom.to_string(lifecycle.state),
        "reason" => label(lifecycle.reason),
        "cleanup_outcome" => label(lifecycle.cleanup_outcome)
      }
    end
  end

  @doc false
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = value) do
    if Grammar.closed?(Map.from_struct(value), @fields) and
         InstanceKey.valid?(value.instance_key) and Grammar.digest?(value.admission_sha256) and
         value.state in @states and reason?(value.reason) and outcome?(value) do
      :ok
    else
      failure(:invalid_instance)
    end
  end

  def validate(_), do: failure(:invalid_instance)

  defp event_shape(event) do
    cond do
      not Grammar.closed?(event, @events) ->
        failure(:invalid_transition)

      not InstanceKey.valid?(event.instance_key) ->
        failure(:invalid_instance)

      event.type not in @types or not reason?(event.reason) ->
        failure(:invalid_transition)

      event.cleanup_outcome not in [nil, :pending, :confirmed_local, :unconfirmed] ->
        failure(:invalid_transition)

      true ->
        :ok
    end
  end

  defp correlation(key, key), do: :ok

  defp correlation(key, other) do
    if key.consumer_scope == other.consumer_scope and key.instance_id == other.instance_id,
      do: failure(:stale_generation),
      else: failure(:invalid_instance)
  end

  defp next(:admitted, %{type: :start, reason: nil, cleanup_outcome: nil}),
    do: {:ok, :starting, nil}

  defp next(:admitted, %{type: type, cleanup_outcome: nil}) when type in [:revoke, :expire],
    do: {:ok, :rejected, nil}

  defp next(:starting, %{type: :ready, reason: nil, cleanup_outcome: nil}),
    do: {:ok, :ready, nil}

  defp next(:starting, %{type: type, cleanup_outcome: nil}) when type in [:cancel, :revoke],
    do: {:ok, :draining, nil}

  defp next(:starting, %{type: :expire, cleanup_outcome: nil}),
    do: {:ok, :failed, :pending}

  defp next(:ready, %{type: type, cleanup_outcome: nil}) when type in [:drain, :revoke, :expire],
    do: {:ok, :draining, nil}

  defp next(state, %{type: type, reason: reason, cleanup_outcome: cleanup})
       when state in [:starting, :ready, :draining] and
              type in [:failure, :owner_lost, :transport_lost] and not is_nil(reason) and
              cleanup in [:pending, :unconfirmed],
       do: {:ok, :failed, cleanup}

  defp next(state, %{type: :cleanup_confirmed, cleanup_outcome: :confirmed_local})
       when state in [:draining, :failed], do: {:ok, :stopped, :confirmed_local}

  defp next(state, %{type: :cleanup_failed, cleanup_outcome: :unconfirmed})
       when state in [:draining, :failed], do: {:ok, :failed, :unconfirmed}

  defp next(_, _), do: failure(:invalid_transition)

  defp reason?(reason), do: is_nil(reason) or reason in @reasons

  defp outcome?(%{state: :failed, cleanup_outcome: outcome}),
    do: outcome in [:pending, :confirmed_local, :unconfirmed]

  defp outcome?(%{state: :stopped, cleanup_outcome: outcome}), do: outcome == :confirmed_local
  defp outcome?(%{cleanup_outcome: outcome}), do: is_nil(outcome)
  defp label(nil), do: nil
  defp label(value), do: Atom.to_string(value)
  defp failure(code), do: {:error, Error.new(code, :construction, %{})}
end
