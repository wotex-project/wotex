defmodule Wotex.Routines.Decision do
  @moduledoc """
  Checks complete pending decisions and their reuse within explicit time cells.

  `Wotex.Routines.Decision.verify_point/4` takes an independently held complete
  Collection@2 input, the claimed `Wotex.Routines.Collection`,
  `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. It returns `:ok` only
  after checking input equality, every point transition, pending proposal,
  proposed/reserved state and collection digest. `Wotex.Routines.Decision.new/3`
  checks the collection against its own retained input, derives the canonical
  elapsed/UTC cell and returns `{:ok, decision}` with a
  `t:Wotex.Routines.Decision.t/0`.

  The decision's plain data has exactly `"format"`, `"collection"`, `"cell"`
  and `"decision_digest"`; its format is `"wotex.routines.decision@1"`.
  `Wotex.Routines.Decision.to_map/3` accepts a native or plain decision and
  rechecks the complete point, canonical cell and digest before returning
  `{:ok, data}`. Rehashing altered members does not establish correspondence.
  Collection@1 refuses `:unsupported_decision_scope`.

  Integration sketch with consumer-supplied point/current inputs, policy and
  arbitration claim:

      :ok = Wotex.Routines.Decision.verify_point(point_input, collection, profile, limits)
      {:ok, decision} = Wotex.Routines.Decision.new(collection, profile, limits)

      current = %{
        "input" => current_input,
        "dispositions" => dispositions,
        "batch_limit" => batch_limit,
        "arbitration" => arbitration
      }

      {:ok, checked} = Wotex.Routines.Decision.check(decision, current, profile, limits)

  `Wotex.Routines.Decision.check/4` accepts exactly those four current-context
  members. Obtain actual current input independently: every non-time member,
  including full membership, programs, events, snapshots and prior history,
  must equal the point input. The complete current `Wotex.Routines.Time` must
  match the relevant clock identities and remain inside every canonical cell
  axis. Cell thresholds include members with no proposal; crossing any boundary
  refuses the whole decision. All constraints, overrides, domain conflicts and
  equivalent contributors are checked before the arbitration batch cutoff,
  without calling the forward transition or arbitration engine.

  Success is `{:ok, checked}` with exactly `"format"`, `"scope"`,
  `"decision_digest"`, `"collection_digest"`, `"point_time"`, `"checked_time"`,
  `"transitions"`, `"proposal_states"` and `"arbitration"`. Its format is
  `"wotex.routines.checked-decision@1"` and scope is
  `"provided_membership_time_cell_only"`. Both complete Times are retained;
  historical point transitions and states are never retimestamped.

  Refusals are `{:error, error}` with a payload-free `Wotex.Routines.Error`.
  Changed non-time input refuses `:stale_decision_input`; an incompatible
  clock basis or cell crossing refuses `:stale_decision_time`; inconsistent or
  forged arbitration refuses `:stale_decision_arbitration`. No partial or
  repaired decision is returned.
  The exact selected Profile and Limits must match the collection's embedded
  selections and bound every complete argument envelope and output, including
  repeated nested copies. No defaults or automatic increases are introduced.

  These pure operations read no clock, device, process state or filesystem.
  Point verification may establish inert historical correspondence after its
  time cell has expired; it grants no current effect admission. The consumer
  authenticates inputs and owns actual complete membership, source/clock and
  artifact qualification, durable originals, transactions, reservations and
  physical authority. Neither a decision nor a checked result discovers omitted
  members, proves nil history is new, refunds spend or permits repeated charge
  or handoff. Each later mutable boundary still needs fresh current inputs and
  external authority checks.
  """

  alias Wotex.Routines.{
    DecisionArbitration,
    DecisionCell,
    DecisionCollection,
    Error,
    Limits,
    Profile,
    Time,
    Validation
  }

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks the full claimed collection against independently supplied point input."
  @spec verify_point(term(), term(), Profile.t(), Limits.t()) :: :ok | {:error, Error.t()}
  def verify_point(input, claimed, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, collection} <- DecisionCollection.admit(claimed, limits),
         :ok <- envelope(%{"input" => input, "collection" => collection}, profile, limits) do
      DecisionCollection.verify(input, collection, profile, limits)
    end
  end

  @doc "Independently verifies a complete Collection@2 and derives its canonical time cell."
  @spec new(term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(claimed, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, collection} <- DecisionCollection.admit(claimed, limits),
         :ok <- envelope(%{"collection" => collection}, profile, limits),
         :ok <- DecisionCollection.verify(collection["input"], collection, profile, limits),
         {:ok, cell} <- DecisionCell.derive(collection, limits) do
      body = %{"format" => "wotex.routines.decision@1", "collection" => collection, "cell" => cell}

      with {:ok, digest} <- Validation.hash(body, limits),
           data = Map.put(body, "decision_digest", digest),
           :ok <- Validation.bounded(data, limits) do
        {:ok, %__MODULE__{data: data}}
      end
    end
  end

  @doc "Rechecks the complete point, canonical cell and digest before returning plain data."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- admit(value, limits),
         :ok <- envelope(%{"decision" => data}, profile, limits),
         :ok <- canonical(data, profile, limits) do
      {:ok, data}
    end
  end

  @doc "Checks actual current input/time and complete arbitration without changing point data."
  @spec check(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def check(value, current, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, data} <- admit(value, limits),
         {:ok, context, _} <- Validation.admit(current, limits, nil),
         :ok <- Validation.fields(context, ~w(input dispositions batch_limit arbitration)),
         :ok <- Validation.fields(context["input"], ~w(format membership entries time)),
         :ok <- envelope(%{"decision" => data, "context" => context}, profile, limits),
         :ok <- canonical(data, profile, limits),
         :ok <- current_input(data["collection"]["input"], context["input"]),
         {:ok, time} <- Time.to_map(context["input"]["time"], limits),
         :ok <- DecisionCell.check(data["cell"], time),
         :ok <- DecisionArbitration.verify(data["collection"], context, profile, limits) do
      checked(data, context, time, limits)
    end
  end

  defp admit(value, limits) do
    with {:ok, data, _} <- Validation.admit(value, limits, __MODULE__),
         :ok <- Validation.fields(data, ~w(format collection cell decision_digest)),
         :ok <- format(data["format"]) do
      {:ok, data}
    end
  end

  defp format("wotex.routines.decision@1"), do: :ok
  defp format(_), do: Error.refusal(:unsupported_decision_scope, "/format")

  defp envelope(body, profile, limits),
    do:
      Validation.bounded(
        Map.merge(body, %{"profile" => profile.data, "json_limits" => limits.data}),
        limits
      )

  defp canonical(data, profile, limits) do
    with {:ok, collection} <- DecisionCollection.admit(data["collection"], limits),
         :ok <- DecisionCollection.verify(collection["input"], collection, profile, limits),
         {:ok, cell} <- DecisionCell.derive(collection, limits),
         :ok <- equal(data["cell"], cell, "/cell"),
         {:ok, digest} <- Validation.hash(Map.delete(data, "decision_digest"), limits) do
      equal(data["decision_digest"], digest, "/decision_digest")
    end
  end

  defp current_input(point, current) do
    if Map.delete(point, "time") === Map.delete(current, "time"),
      do: :ok,
      else: Error.refusal(:stale_decision_input, "/input")
  end

  defp checked(data, context, time, limits) do
    collection = data["collection"]

    result = %{
      "format" => "wotex.routines.checked-decision@1",
      "scope" => "provided_membership_time_cell_only",
      "decision_digest" => data["decision_digest"],
      "collection_digest" => collection["collection_digest"],
      "point_time" => collection["input"]["time"],
      "checked_time" => time,
      "transitions" => collection["transitions"],
      "proposal_states" => collection["proposal_states"],
      "arbitration" => context["arbitration"]
    }

    with :ok <- Validation.bounded(result, limits), do: {:ok, result}
  end

  defp equal(value, value, _), do: :ok
  defp equal(_, _, path), do: Error.refusal(:invalid_collection_decision, path)
end
