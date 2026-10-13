defmodule Wotex.Routines.Model do
  @moduledoc """
  Inert, source-bound projections with explicit assumptions and omissions.

  The supported profiles model one Boolean manual proposal prefix or staged
  software-receipt prefix under frozen time. They do not model device behaviour
  or prove execution safety. Unsupported source or scope refuses before generation.
  Compilation starts no worker and reads no filesystem, clock or configuration.
  """

  alias Wotex.Routines.{Compiler, Error, Limits, Profile, ReceiptModel, Validation}

  @scope %{
    "profile" => "proposal-prefix@1",
    "purpose" => "proposal_generation_only",
    "initial_history" => "no_existing_run",
    "time_policy" => "frozen_before_deadline",
    "environment" => "manual_and_cancel_one_original",
    "claims" => ~w(proposal_once fixed_absolute_proposal),
    "omissions" =>
      ~w(admission handoff receipts time_progress fact_changes multi_original_overlap authority complete_set_arbitration physical_effects)
  }
  @receipt_scope %{
    "profile" => "receipt-prefix@1",
    "purpose" => "software_receipt_transitions_only",
    "initial_history" => "no_existing_run",
    "time_policy" => "frozen_before_deadline",
    "environment" => "manual_staged_receipts_one_original",
    "claims" => ~w(proposal_once held_spend_retained completion_evidence stopped_continuation),
    "omissions" =>
      ~w(authority time_progress fact_changes multi_original_overlap complete_set_arbitration historical_receipts physical_effects)
  }
  @fields ~w(format program scope scope_digest model_bytes model_digest)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Regenerates a current Program and compiles only the explicitly supported proposal scope."
  @spec compile(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def compile(program, scope, profile, limits) do
    with {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, scope, limits} <- Validation.admit(scope, limits, nil),
         :ok <- scope(scope),
         {:ok, value} <- supported(program),
         :ok <- receipt_threshold(program, scope),
         {:ok, scope_digest} <- Validation.hash(scope, limits) do
      bytes =
        if scope["profile"] == "receipt-prefix@1", do: ReceiptModel.bytes(value), else: bytes(value)

      data = %{
        "format" => "wotex.routines.model@1",
        "program" => program,
        "scope" => scope,
        "scope_digest" => scope_digest,
        "model_bytes" => bytes,
        "model_digest" => digest(bytes)
      }

      with :ok <- Validation.bounded(data, limits), do: {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Checks the complete artifact by regenerating its retained Program/scope and model bytes."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(model, profile, limits) do
    with {:ok, data, _} <- Validation.admit(model, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         {:ok, current} <- compile(data["program"], data["scope"], profile, limits) do
      if current.data == data, do: {:ok, data}, else: Error.refusal(:stale_or_forged_model)
    end
  end

  @doc "Compares a regenerated artifact against the complete current Program and assumption scope."
  @spec current(term(), term(), term(), Profile.t(), Limits.t()) :: :ok | {:error, Error.t()}
  def current(model, program, scope, profile, limits) do
    with {:ok, existing} <- to_map(model, profile, limits),
         {:ok, current} <- compile(program, scope, profile, limits) do
      if current.data == existing, do: :ok, else: Error.refusal(:stale_model_binding)
    end
  end

  defp scope(data) do
    with :ok <- Validation.fields(data, ["policy_digest" | Map.keys(@scope)]),
         :ok <- Validation.digest(data["policy_digest"], "/policy_digest") do
      if Map.drop(data, ["policy_digest"]) in [@scope, @receipt_scope],
        do: :ok,
        else: Error.refusal(:unsupported_model_scope, "/scope")
    end
  end

  defp receipt_threshold(program, %{"profile" => "receipt-prefix@1"}) do
    if program["ir"]["steps"]["completion"] == "reported_match",
      do: :ok,
      else: Error.refusal(:unsupported_model_scope, "/program")
  end

  defp receipt_threshold(_, _), do: :ok

  defp supported(program) do
    source = program["source"]
    ir = program["ir"]
    effect = ir["steps"]
    context = program["context"]

    with true <- source["parameters"] == %{} and context["definitions"] == [],
         true <- length(source["bindings"]) == 1 and map_size(context["bindings"]) == 1,
         true <- ir["trigger"] == %{"kind" => "manual"} and ir["condition"] == [["literal", true]],
         %{"kind" => "effect", "path" => [], "input" => value, "binding" => binding} <- effect,
         true <- is_boolean(value),
         reference = context["bindings"][binding]["basis"],
         basis =
           Enum.find(context["bases"], &(Map.take(&1, ~w(id version semantic_digest)) == reference)),
         true <-
           basis["value"]["type"] == "boolean" and
             basis["affordance"]["operation"] == "writeproperty" do
      {:ok, value}
    else
      _ -> Error.refusal(:unsupported_model_scope, "/program")
    end
  end

  defp bytes(value) do
    literal = if value, do: "true", else: "false"

    """
    mod ROUTINE-PROPOSAL-PREFIX is
      protecting NAT .
      protecting BOOL .
      sorts Phase State .
      ops fresh proposed cancelled : -> Phase [ctor] .
      op state : Phase Nat -> State [ctor] .
      op requested : -> Bool .
      eq requested = #{literal} .
      rl [manual-first] : state(fresh, 0) => state(proposed, 1) .
      rl [manual-repeat] : state(proposed, 1) => state(proposed, 1) .
      rl [cancel] : state(proposed, 1) => state(cancelled, 1) .
      rl [manual-stopped] : state(cancelled, 1) => state(cancelled, 1) .
      rl [cancel-repeat] : state(cancelled, 1) => state(cancelled, 1) .
    endm
    """
  end

  defp digest(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
