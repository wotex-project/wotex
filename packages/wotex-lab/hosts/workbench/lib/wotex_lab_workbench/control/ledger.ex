defmodule WotexLabWorkbench.Control.Ledger do
  @moduledoc """
  The bounded idempotency identities of one room's HTTP control mutations.

  A room keeps one ledger in its own state, so the ledger lives and ends with
  the session room. An identity binds a caller-chosen `Idempotency-Key` to the
  SHA-256 fingerprint of the admitted operation and to the retained outcome of
  the room command that ran under it. `check/3` classifies a dequeued mutation
  as new, a replay of the retained outcome, or a refused key reuse; `retain/4`
  records an executed outcome. The ledger never evicts an identity: once it
  holds `capacity/0` identities, `check/3` refuses every new key, so an old key
  can never be accepted a second time while the room lives.

  A retained successful outcome keeps only the run identifier. Replays read the
  run again from the room and therefore report its current state. The
  `WotexLabWorkbench.Control` module owns admission and projection; the room
  owns execution. This module performs no I/O and starts no process.
  """

  alias Wotex.Lab.Error

  @capacity 64

  @typedoc "A retained command outcome: a run identifier or the room's refusal."
  @type outcome :: {:ok, String.t()} | {:error, Error.t()}

  @typedoc "Identities keyed by idempotency key."
  @type t :: %{optional(String.t()) => {binary(), outcome()}}

  @doc "The maximum number of identities one room retains."
  @spec capacity() :: pos_integer()
  def capacity, do: @capacity

  @doc "An empty ledger."
  @spec new() :: t()
  def new, do: %{}

  @doc "Classifies a dequeued mutation by its key and fingerprint."
  @spec check(t(), String.t(), binary()) :: :new | {:replay, outcome()} | {:error, Error.t()}
  def check(ledger, key, fingerprint) when is_map(ledger) do
    case Map.fetch(ledger, key) do
      {:ok, {^fingerprint, outcome}} ->
        {:replay, outcome}

      {:ok, {_, _}} ->
        {:error,
         Error.new(
           :idempotency_key_reused,
           :control_api,
           "idempotency key was used for a different request"
         )}

      :error when map_size(ledger) >= @capacity ->
        {:error,
         Error.new(:idempotency_capacity, :control_api, "room retains no more mutation keys")}

      :error ->
        :new
    end
  end

  @doc "Retains the outcome of a command executed under a new key."
  @spec retain(t(), String.t(), binary(), outcome()) :: t()
  def retain(ledger, key, fingerprint, {:ok, run_id} = outcome)
      when is_map(ledger) and is_binary(run_id),
      do: Map.put(ledger, key, {fingerprint, outcome})

  def retain(ledger, key, fingerprint, {:error, %Error{}} = outcome) when is_map(ledger),
    do: Map.put(ledger, key, {fingerprint, outcome})
end
