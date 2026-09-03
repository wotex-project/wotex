defmodule WotexContinuum.Lifecycle do
  @moduledoc """
  Pure lifecycle state and transition validation for a continuum subject.

  The explicit transition graph prevents impossible state changes, while
  generation and normalized change time make updates deterministic and
  replayable. A transition returns a new value only; it never starts, drains,
  stops, or removes the represented runtime.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, Validation}

  @kind "lifecycle"
  @states [:staged, :ready, :active, :degraded, :draining, :stopped, :removed]
  @transitions %{
    staged: [:ready, :removed],
    ready: [:active, :stopped, :removed],
    active: [:degraded, :draining, :stopped],
    degraded: [:active, :draining, :stopped],
    draining: [:stopped],
    stopped: [:ready, :removed],
    removed: []
  }

  @enforce_keys [:subject_id, :state, :generation, :changed_at]
  defstruct [:subject_id, :state, :generation, :changed_at, :reason, extensions: %{}]

  @type state :: :staged | :ready | :active | :degraded | :draining | :stopped | :removed
  @type t :: %__MODULE__{
          subject_id: String.t(),
          state: state(),
          generation: non_neg_integer(),
          changed_at: String.t(),
          reason: String.t() | nil,
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @doc "Returns lifecycle states in contract order."
  @spec states() :: nonempty_list(state())
  def states, do: @states

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:subject_id, :state, :generation, :changed_at, :reason, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, subject_id} <- Validation.required(data, :subject_id),
         {:ok, subject_id} <- Validation.string(subject_id, ["subject_id"]),
         {:ok, state} <- Validation.required(data, :state),
         {:ok, state} <- Validation.enum(state, ["state"], @states),
         {:ok, generation} <- Validation.required(data, :generation),
         {:ok, generation} <- Validation.non_negative_integer(generation, ["generation"]),
         {:ok, changed_at} <- Validation.required(data, :changed_at),
         {:ok, changed_at} <- Validation.timestamp(changed_at, ["changed_at"]),
         {:ok, reason} <- Validation.optional_string(Map.get(data, :reason), ["reason"], max: 2_048),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         subject_id: subject_id,
         state: state,
         generation: generation,
         changed_at: changed_at,
         reason: reason,
         extensions: extensions
       }}
    end
  end

  @doc "Validates and applies one lifecycle transition."
  @spec transition(t(), state() | String.t(), DateTime.t() | String.t(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def transition(%__MODULE__{} = lifecycle, next_state, changed_at, options \\ []) do
    with {:ok, next_state} <- Validation.enum(next_state, ["state"], @states),
         :ok <- allowed_transition(lifecycle.state, next_state),
         {:ok, changed_at} <- Validation.timestamp(changed_at, ["changed_at"]),
         :ok <- chronological(lifecycle.changed_at, changed_at),
         {:ok, reason} <-
           Validation.optional_string(Keyword.get(options, :reason), ["reason"], max: 2_048) do
      {:ok,
       %__MODULE__{
         lifecycle
         | state: next_state,
           generation: lifecycle.generation + 1,
           changed_at: changed_at,
           reason: reason
       }}
    end
  end

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("subject_id", value.subject_id)
    |> Map.put("state", Atom.to_string(value.state))
    |> Map.put("generation", value.generation)
    |> Map.put("changed_at", value.changed_at)
    |> maybe_put("reason", value.reason)
    |> Map.put("extensions", value.extensions)
  end

  defp invalid_transition(from, to) do
    Error.error(:invalid_transition, ["state"], "lifecycle transition is not allowed", %{
      from: from,
      to: to
    })
  end

  defp allowed_transition(from, to) do
    if to in Map.fetch!(@transitions, from), do: :ok, else: invalid_transition(from, to)
  end

  defp chronological(previous, next) do
    if Validation.compare_timestamps(previous, next) in [:lt, :eq],
      do: :ok,
      else:
        Error.error(:invalid_time_order, ["changed_at"], "transition time precedes current state")
  end

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
