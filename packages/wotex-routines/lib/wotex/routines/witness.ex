defmodule Wotex.Routines.Witness do
  @moduledoc """
  Replays a finite supplied counterexample through the pure routine kernel.

  `Wotex.Routines.Witness.replay/4` takes a compiled program, closed witness
  map, `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. The witness binds
  the exact program/source/compiler identities, selects a software property,
  and supplies initial retained runs/edge plus complete event/snapshot/time
  frames. It selects at most 256 frames and 1,024 originals, further bounded
  by the caller's Limits. Initial state may contain at most one live run.

  Replay retains an original ledger, calls `Wotex.Routines.Kernel.advance/7`
  for each frame and checks `"proposal_once"`, `"held_spend_retained"`,
  `"stopped_continuation"` or `"completion_evidence"`. Success returns
  `{:ok, result}` with the trace/program identities, complete transitions,
  `"reproduced"` and the first zero-based `"violation_step"` or `nil`.
  Invalid inputs or failed transition correspondence return `{:error, error}`
  with a `Wotex.Routines.Error`; full nested results must fit the supplied
  limits without truncation.

  The completion-evidence property accepts a coherent satisfied receipt for an
  unsent absolute Property write requiring `"reported_match"`, as well as the
  existing qualified handoff/result stages. `Wotex.Routines.Run` still checks
  receipt, path and held-spend coherence, and a fresh satisfaction frame must
  pass the kernel's current Fact qualification. A retained receipt is history;
  replay does not manufacture handoff or refund admission spend. This concrete
  replay support does not broaden `Wotex.Routines.Model`'s frozen model scopes.

  The consumer supplies the finite environment, authentic originals, qualified
  observations and clock bases. Replay performs no model search, persistence
  or physical effect. A nonviolating trace proves no universal safety claim,
  and neither result authenticates history or grants execution authority.
  """

  alias Wotex.Routines.{
    Compiler,
    Edge,
    Error,
    Kernel,
    Limits,
    Profile,
    Run,
    Validation,
    WitnessProperties
  }

  @fields ~w(format property program_digest source_digest compiler_basis max_steps max_originals initial frames)
  @properties ~w(proposal_once held_spend_retained stopped_continuation completion_evidence)
  @terminal ~w(completed refused failed unknown cancelled expired partial)

  @doc "Replays a closed finite Witness under a fully regenerated current Program."
  @spec replay(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def replay(program, witness, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, witness, limits} <- Validation.admit(witness, limits, nil),
         :ok <- check(witness, program, limits),
         {:ok, initial} <- initial(witness, program, profile, limits),
         {:ok, trace_digest} <- Validation.hash(witness, limits),
         {:ok, state} <- replay_frames(witness, program, initial, profile, limits) do
      result = %{
        "format" => "wotex.routines.replay@1",
        "property" => witness["property"],
        "trace_digest" => trace_digest,
        "program_digest" => program["ir_digest"],
        "source_digest" => program["source_digest"],
        "compiler_basis" => program["context"]["compiler_basis"],
        "reproduced" => state.violation != nil,
        "violation_step" => state.violation,
        "transitions" => Enum.reverse(state.transitions)
      }

      with :ok <- Validation.bounded(result, limits), do: {:ok, result}
    end
  end

  defp check(witness, program, limits) do
    with :ok <- Validation.fields(witness, @fields),
         :ok <- Validation.choice(witness["format"], ["wotex.routines.witness@1"], "/format"),
         :ok <- Validation.choice(witness["property"], @properties, "/property"),
         :ok <- selection(witness["max_steps"], 256, limits, "/max_steps"),
         :ok <- selection(witness["max_originals"], 1024, limits, "/max_originals"),
         :ok <- correspondence(witness, program) do
      case witness["frames"] do
        frames when is_list(frames) and frames != [] ->
          if length(frames) <= witness["max_steps"],
            do: :ok,
            else: Error.refusal(:witness_step_bound, "/frames")

        _ ->
          Error.refusal(:invalid_type, "/frames")
      end
    end
  end

  defp selection(value, maximum, limits, path) do
    with :ok <- Validation.integer(value, limits, path, 1) do
      if value <= maximum and value <= limits.data["max_collection_size"],
        do: :ok,
        else: Error.refusal(:witness_bound, path)
    end
  end

  defp correspondence(witness, program) do
    subjects = %{
      "program_digest" => program["ir_digest"],
      "source_digest" => program["source_digest"],
      "compiler_basis" => program["context"]["compiler_basis"]
    }

    Validation.each(Map.to_list(subjects), fn {key, expected} ->
      if witness[key] == expected, do: :ok, else: Error.refusal(:stale_witness, "/" <> key)
    end)
  end

  defp initial(witness, program, profile, limits) do
    initial = witness["initial"]

    with :ok <- Validation.fields(initial, ~w(runs edge), [], "/initial"),
         {:ok, runs} <- runs(initial["runs"], witness["max_originals"], program, profile, limits),
         {:ok, edge} <- edge(initial["edge"], program, profile, limits) do
      {:ok,
       %{
         runs: Map.new(runs, &{&1["original"], &1}),
         edge: edge,
         seen: WitnessProperties.started(runs),
         transitions: [],
         violation: nil
       }}
    end
  end

  defp runs(values, maximum, program, profile, limits) when is_list(values) do
    if length(values) > maximum,
      do: Error.refusal(:witness_original_bound, "/initial/runs"),
      else: checked_runs(values, program, profile, limits)
  end

  defp runs(_, _, _, _, _), do: Error.refusal(:invalid_type, "/initial/runs")

  defp checked_runs(values, program, profile, limits) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, runs} ->
        case Run.to_map(value, program, profile, limits) do
          {:ok, run} -> {:cont, {:ok, [run | runs]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, runs} <- result,
         true <- length(runs) == length(Enum.uniq_by(runs, & &1["original"])),
         true <- Enum.count(runs, &(&1["status"] not in @terminal)) <= 1 do
      {:ok, Enum.reverse(runs)}
    else
      false -> Error.refusal(:incoherent_witness_history, "/initial/runs")
      error -> error
    end
  end

  defp edge(nil, _, _, _), do: {:ok, nil}
  defp edge(value, program, profile, limits), do: Edge.to_map(value, program, profile, limits)

  defp replay_frames(witness, program, initial, profile, limits) do
    Enum.reduce_while(Enum.with_index(witness["frames"]), {:ok, initial}, fn {frame, index},
                                                                             {:ok, state} ->
      case frame(frame, index, state, witness, program, profile, limits) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp frame(frame, index, state, witness, program, profile, limits) do
    with :ok <- Validation.fields(frame, ~w(event snapshot time), [], "/frames/#{index}"),
         prior = prior(state, frame["event"]),
         {:ok, transition} <-
           Kernel.advance(
             program,
             frame["event"],
             frame["snapshot"],
             frame["time"],
             prior,
             profile,
             limits
           ),
         {:ok, runs} <- retain(state.runs, transition["run"], witness["max_originals"]),
         transitions = [transition | state.transitions],
         :ok <- Validation.bounded(transitions, limits) do
      violated =
        WitnessProperties.violated?(
          witness["property"],
          prior["original"],
          transition,
          program,
          state.seen
        )

      seen = Enum.reduce(transition["proposals"], state.seen, &MapSet.put(&2, &1["step_original"]))

      {:ok,
       %{
         state
         | runs: runs,
           edge: transition["edge"],
           seen: seen,
           transitions: transitions,
           violation: if(state.violation == nil and violated, do: index, else: state.violation)
       }}
    end
  end

  defp prior(state, event) do
    original = if is_map(event), do: Map.get(state.runs, event["original"]), else: nil

    busy =
      Enum.find_value(state.runs, fn {_, run} ->
        if run["status"] not in @terminal, do: run
      end)

    %{"original" => original, "busy" => busy, "edge" => state.edge}
  end

  defp retain(runs, nil, _), do: {:ok, runs}

  defp retain(runs, run, maximum) do
    runs = Map.put(runs, run["original"], run)

    if map_size(runs) <= maximum,
      do: {:ok, runs},
      else: Error.refusal(:witness_original_bound, "/frames")
  end
end
