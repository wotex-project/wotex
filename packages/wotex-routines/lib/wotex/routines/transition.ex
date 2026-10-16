defmodule Wotex.Routines.Transition do
  @moduledoc """
  Checks a claimed routine transition against its explicit original point inputs.

  `Wotex.Routines.Transition.verify/8` takes program, event, snapshot, time and
  prior state in the same order as `Wotex.Routines.Kernel.advance/7`, followed
  by the claimed result, `Wotex.Routines.Profile` and `Wotex.Routines.Limits`.
  Supply the independently held original inputs, including the complete prior
  `"original"`, `"busy"` and `"edge"` history. The claimed result must have
  exactly `"run"`, `"proposals"`, `"outcome"`, `"edge"` and `"basis"`.

  Success is `:ok` for the supplied before/after relation; no replacement or
  repaired transition is returned. Refusals are `{:error, error}` with a
  payload-free `Wotex.Routines.Error`. A failed claimed relation uses
  `:invalid_transition`; representation, compiler, identity and limit refusals
  retain their own codes and paths.

  The checker regenerates the compiled program and revalidates the complete
  `Wotex.Routines.Event`, `Wotex.Routines.Snapshot`, `Wotex.Routines.Time` and
  retained `Wotex.Routines.Run`/`Wotex.Routines.Edge` values. It compares the normalized
  input basis, record/path changes, receipts, nonrefundable spent references,
  edge state, outcome and complete ordered proposals. Resume, current-state
  satisfaction and both supported time/run/edge representations retain their
  existing correspondence rules. Verification checks the supplied conclusions
  without calling the forward transition engine or generating another result.

  The exact selected Profile and Limits apply throughout. The full argument
  envelope, including the claimed result and every repeated embedded input,
  must fit the JSON bounds; a digest does not replace any required member.
  These pure checks read no clock or filesystem and contact no source owner
  or consumer database.

  Success establishes internal correspondence at that historical point. The
  consumer authenticates its inputs, selects actual original/no-repeat history
  and decides whether an inert point transition may be retained. It must still
  obtain current complete membership, observations, time and authority before
  admitting effects. Verification neither renews deadlines nor resolves an
  uncertain handoff, refunds spend or authorizes repeating physical work.
  """

  alias Wotex.Routines.{
    ClockBasis,
    Compiler,
    Edge,
    Error,
    Event,
    ExecutionPrior,
    Limits,
    Profile,
    Run,
    Snapshot,
    Time,
    TransitionChecks,
    TransitionEdge,
    TransitionObservation,
    TransitionRun,
    Validation
  }

  @doc "Checks the complete claimed point relation without advancing the forward engine."
  @spec verify(term(), term(), term(), term(), term(), term(), Profile.t(), Limits.t()) ::
          :ok | {:error, Error.t()}
  def verify(program, event, snapshot, time, prior, claimed, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, event} <- Event.to_map(event, limits),
         {:ok, snapshot} <- Snapshot.to_map(snapshot, program, profile, limits),
         {:ok, time} <- Time.to_map(time, limits),
         {:ok, prior} <- ExecutionPrior.new(prior, program, profile, limits),
         {:ok, result, _} <- Validation.admit(claimed, limits, nil),
         :ok <- Validation.fields(result, ~w(run proposals outcome edge basis)),
         :ok <- envelope(program, event, snapshot, time, prior, result, profile, limits),
         :ok <- correspondence(program, event, snapshot, time, prior),
         :ok <- result_shape(result, program, profile, limits),
         :ok <- basis(result, program, event, snapshot, time, prior) do
      c = %{
        program: program,
        event: event,
        snapshot: snapshot,
        time: time,
        prior: prior,
        before: prior["original"],
        result: result,
        profile: profile,
        limits: limits,
        values: TransitionObservation.values(program, snapshot, time, limits)
      }

      with {:ok, eligible} <- TransitionEdge.verify(c, result["edge"]),
           do: TransitionRun.verify(c, eligible)
    end
  end

  defp envelope(program, event, snapshot, time, prior, result, profile, limits) do
    Validation.bounded(
      %{
        "program" => program,
        "event" => event,
        "snapshot" => snapshot,
        "time" => time,
        "prior" => prior,
        "claimed_result" => result,
        "profile" => profile.data,
        "json_limits" => limits.data
      },
      limits
    )
  end

  defp correspondence(program, event, snapshot, time, prior) do
    original = prior["original"]

    cond do
      event["program_digest"] != program["ir_digest"] ->
        Error.refusal(:foreign_event)

      original == nil and event["kind"] in ~w(admission handoff result cancel resume satisfied) ->
        Error.refusal(:missing_original)

      original == nil and program["ir_digest"] not in snapshot["active_programs"] ->
        Error.refusal(:inactive_program)

      true ->
        history(original, prior["busy"], event, time)
    end
  end

  defp history(original, busy, event, time) do
    cond do
      original != nil and original["original"] != event["original"] ->
        Error.refusal(:foreign_original)

      original == nil and busy != nil and busy["original"] == event["original"] ->
        Error.refusal(:missing_original)

      original != nil and
          Map.get(original, "time_format", "wotex.routines.time@1") != ClockBasis.format(time) ->
        Error.refusal(:clock_format_mismatch)

      true ->
        :ok
    end
  end

  defp result_shape(result, program, profile, limits) do
    with :ok <- TransitionChecks.condition(is_list(result["proposals"]), "/proposals"),
         :ok <- retained_run(result["run"], program, profile, limits) do
      retained_edge(result["edge"], program, profile, limits)
    end
  end

  defp retained_run(nil, _, _, _), do: :ok

  defp retained_run(run, program, profile, limits) do
    with {:ok, _} <- Run.to_map(run, program, profile, limits), do: :ok
  end

  defp retained_edge(nil, _, _, _), do: :ok

  defp retained_edge(edge, program, profile, limits) do
    with {:ok, _} <- Edge.to_map(edge, program, profile, limits), do: :ok
  end

  defp basis(result, program, event, snapshot, time, prior) do
    TransitionChecks.equal(
      result["basis"],
      %{
        "program_digest" => program["ir_digest"],
        "source_digest" => program["source_digest"],
        "compiler_basis" => program["context"]["compiler_basis"],
        "event" => event,
        "prior" => prior,
        "snapshot" => snapshot,
        "time" => time
      },
      "/basis"
    )
  end
end
