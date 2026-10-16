defmodule Wotex.Routines.Collection do
  @moduledoc """
  Evaluates the complete supplied membership before arbitration or batching.

  `Wotex.Routines.Collection.evaluate/3` takes a closed string-keyed input,
  `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. Success is
  `{:ok, collection}` with a `t:Wotex.Routines.Collection.t/0`; validation,
  correspondence and bound failures return `{:error, error}` with a
  `Wotex.Routines.Error`, without a partial collection.

  The original input has exactly `"membership"`, `"entries"` and `"time"`.
  It returns `"wotex.routines.collection@1"`, collecting newly emitted kernel
  proposals. To select complete pending continuation, add exactly
  `"format" => "wotex.routines.collection-input@2"`. That input returns
  `"wotex.routines.collection@2"`. Membership contains `"generation"` and
  `"programs"`; each program has one entry with `"program"`, `"event"`,
  `"snapshot"` and `"prior"`. Entries share the explicit Time and coherent
  snapshot membership, identity, observations and resource revisions.

  In v2, each live retained run must appear as prior `"original"` with a
  continuation or receipt event naming that original. `"resume"` is the neutral
  continuation. A live prior `"busy"` must equal that complete original run;
  it cannot replace missing history or be displaced by a new trigger. A nil
  event with live history refuses `:incomplete_run_continuation`. Terminal or
  absent history may use nil and produces no transition.

  After evaluating entries through `Wotex.Routines.Kernel.advance/7`, v2
  regenerates each currently eligible proposed or reserved effect, including
  work retained from earlier calls. Eligibility uses this call's explicit
  snapshot/Time, current root and invoked-child conditions, fixed selected
  paths, membership, original windows and inherited/effect deadlines. False or
  unknown conditions preserve state while excluding the step from this cut.
  Terminal, handed-off, satisfied and unselected steps contribute no proposal.

  Both results retain the complete input, profile, JSON limits, transitions,
  proposals and `"collection_digest"`. V2 additionally has `"proposal_states"`,
  a parallel ordered array of exact `"step_original"`/`"status"` records with
  status `"proposed"` or `"reserved"`, in one-to-one correspondence with
  proposals. Proposals and states are ordered by
  program digest and compiled path. The entire eligible set counts against
  `"pending_work"` before equivalence or batch selection; full nested inputs
  and outputs must also fit the selected JSON limits.

  `Wotex.Routines.Collection.to_map/3` regenerates every transition, proposal,
  state and digest from the retained input before returning `{:ok, data}`.
  If regeneration differs, it refuses `:stale_or_forged_collection` even with
  a recalculated digest. Retain the complete collection for
  `Wotex.Routines.Arbitration.decide/5`.
  The consumer owns actual active membership, current facts/clocks, durable
  originals and atomic authority checks. A collection cannot discover omitted
  host membership or authorize a charge, handoff or physical effect.
  """

  alias Wotex.Routines.{
    Compiler,
    Error,
    Event,
    ExecutionPrior,
    ExecutionTree,
    Kernel,
    Limits,
    ObservationView,
    Pending,
    Profile,
    Proposal,
    Snapshot,
    Time,
    Validation
  }

  @fields ~w(format input profile json_limits transitions proposals collection_digest)
  @input_fields ~w(membership entries time)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks full supplied membership and shared snapshot coherence, then evaluates every entry."
  @spec evaluate(term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def evaluate(input, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, input, limits} <- Validation.admit(input, limits, nil),
         :ok <- input_fields(input),
         :ok <- membership(input["membership"], profile),
         {:ok, time} <- Time.to_map(input["time"], limits),
         {:ok, entries} <- entries(input["entries"], profile, limits),
         :ok <- complete(entries, input["membership"]),
         :ok <- coherent(entries),
         :ok <- continuations(entries, input, limits),
         {:ok, transitions} <- transitions(entries, time, profile, limits),
         :ok <- active_runs(entries, transitions, profile),
         {:ok, proposals, states} <-
           proposals(entries, transitions, input, time, profile, limits) do
      data = %{
        "format" =>
          if(complete_pending?(input),
            do: "wotex.routines.collection@2",
            else: "wotex.routines.collection@1"
          ),
        "input" => input,
        "profile" => profile.data,
        "json_limits" => limits.data,
        "transitions" => transitions,
        "proposals" => proposals
      }

      data = if states == nil, do: data, else: Map.put(data, "proposal_states", states)

      with :ok <- Validation.bounded(data, limits),
           {:ok, digest} <- Validation.hash(data, limits),
           :ok <- Validation.bounded(Map.put(data, "collection_digest", digest), limits) do
        {:ok, %__MODULE__{data: Map.put(data, "collection_digest", digest)}}
      end
    end
  end

  @doc "Regenerates the entire collection; recomputed digests cannot validate altered proposals or membership."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(collection, profile, limits) do
    with {:ok, data, _} <- Validation.admit(collection, limits, __MODULE__),
         :ok <- output_fields(data),
         {:ok, rebuilt} <- evaluate(data["input"], profile, limits) do
      if data == rebuilt.data, do: {:ok, data}, else: Error.refusal(:stale_or_forged_collection)
    end
  end

  defp complete_pending?(input),
    do: input["format"] == "wotex.routines.collection-input@2"

  defp input_fields(%{"format" => "wotex.routines.collection-input@2"} = input),
    do: Validation.fields(input, ["format" | @input_fields])

  defp input_fields(input), do: Validation.fields(input, @input_fields)

  defp output_fields(%{"format" => "wotex.routines.collection@2"} = data),
    do: Validation.fields(data, ["proposal_states" | @fields])

  defp output_fields(data), do: Validation.fields(data, @fields)

  defp continuations(entries, input, limits) do
    if complete_pending?(input),
      do: Validation.each(entries, &continuation(&1, limits)),
      else: :ok
  end

  defp continuation(entry, limits) do
    with {:ok, event} <- checked_event(entry["event"], limits) do
      original = entry["prior"]["original"]
      busy = entry["prior"]["busy"]

      incomplete =
        (live?(original) and (event == nil or event["original"] != original["original"])) or
          (live?(busy) and (busy != original or event == nil))

      if incomplete, do: Error.refusal(:incomplete_run_continuation), else: :ok
    end
  end

  defp checked_event(nil, _), do: {:ok, nil}
  defp checked_event(event, limits), do: Event.to_map(event, limits)
  defp live?(nil), do: false
  defp live?(run), do: run["status"] in ~w(running blocked)

  defp membership(data, profile) do
    with :ok <- Validation.fields(data, ~w(generation programs)),
         :ok <- Validation.text(data["generation"], "/membership/generation"),
         :ok <- Validation.strings(data["programs"], "/membership/programs"),
         :ok <- Validation.each(data["programs"], &Validation.digest(&1, "/membership/programs")) do
      if length(data["programs"]) <= profile.data["active_definitions"],
        do: :ok,
        else: Error.refusal(:definition_bound)
    end
  end

  defp entries(values, profile, limits) when is_list(values) do
    if length(values) <= profile.data["active_definitions"] do
      Enum.reduce_while(values, {:ok, []}, fn entry, {:ok, entries} ->
        case entry(entry, profile, limits) do
          {:ok, checked} -> {:cont, {:ok, [checked | entries]}}
          error -> {:halt, error}
        end
      end)
    else
      Error.refusal(:definition_bound)
    end
  end

  defp entries(_, _, _), do: Error.refusal(:invalid_type, "/entries")

  defp entry(data, profile, limits) do
    with :ok <- Validation.fields(data, ~w(program event snapshot prior)),
         {:ok, program} <- Compiler.to_map(data["program"], profile, limits),
         {:ok, snapshot} <- Snapshot.to_map(data["snapshot"], program, profile, limits),
         {:ok, prior} <- ExecutionPrior.new(data["prior"], program, profile, limits) do
      {:ok, %{data | "program" => program, "snapshot" => snapshot, "prior" => prior}}
    end
  end

  defp complete(entries, membership) do
    digests = Enum.map(entries, & &1["program"]["ir_digest"])
    snapshots = Enum.map(entries, & &1["snapshot"])

    valid =
      Enum.sort(digests) == Enum.sort(membership["programs"]) and
        length(Enum.uniq(digests)) == length(digests) and
        Enum.all?(
          snapshots,
          &(&1["membership_generation"] == membership["generation"] and
              &1["active_programs"] == membership["programs"])
        )

    if valid, do: :ok, else: Error.refusal(:incomplete_collection)
  end

  defp coherent([]), do: :ok

  defp coherent(entries) do
    ids =
      entries
      |> Enum.map(& &1["snapshot"]["id"])
      |> Enum.uniq()

    with true <- length(ids) == 1,
         :ok <- shared_resources(entries) do
      shared_observations(entries)
    else
      false -> Error.refusal(:incoherent_collection_snapshot)
      error -> error
    end
  end

  defp shared_resources(entries) do
    pairs = Enum.flat_map(entries, &Map.to_list(&1["snapshot"]["resource_revisions"]))
    consistent(pairs)
  end

  defp shared_observations(entries) do
    pairs =
      Enum.flat_map(entries, fn entry ->
        Enum.map(entry["program"]["context"]["bindings"], fn {name, binding} ->
          basis =
            Enum.find(
              entry["program"]["context"]["bases"],
              &(Map.take(&1, ~w(id version semantic_digest)) == binding["basis"])
            )

          affordance = basis["affordance"]

          key =
            {binding["thing_id"], affordance["type"], affordance["name"], affordance["operation"]}

          {key,
           {binding["basis"], entry["snapshot"]["binding_bases"][name],
            entry["snapshot"]["facts"][name]}}
        end)
      end)

    consistent(pairs)
  end

  defp consistent(pairs) do
    Enum.reduce_while(pairs, %{}, fn {key, value}, seen ->
      if Map.has_key?(seen, key) and seen[key] != value,
        do: {:halt, :incoherent},
        else: {:cont, Map.put(seen, key, value)}
    end)
    |> consistency_result()
  end

  defp consistency_result(:incoherent), do: Error.refusal(:incoherent_collection_snapshot)
  defp consistency_result(_), do: :ok

  defp transitions(entries, time, profile, limits) do
    entries
    |> Enum.sort_by(& &1["program"]["ir_digest"])
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, transitions} ->
      case transition(entry, time, profile, limits) do
        {:ok, result} ->
          record = %{"program_digest" => entry["program"]["ir_digest"], "result" => result}
          {:cont, {:ok, [record | transitions]}}

        error ->
          {:halt, error}
      end
    end)
    |> ordered()
  end

  defp transition(%{"event" => nil}, _, _, _), do: {:ok, nil}

  defp transition(entry, time, profile, limits),
    do:
      Kernel.advance(
        entry["program"],
        entry["event"],
        entry["snapshot"],
        time,
        entry["prior"],
        profile,
        limits
      )

  defp ordered({:ok, records}), do: {:ok, Enum.reverse(records)}
  defp ordered(error), do: error

  defp active_runs(entries, transitions, profile) do
    retained = Enum.flat_map(entries, &[&1["prior"]["original"], &1["prior"]["busy"]])

    advanced =
      Enum.map(transitions, fn
        %{"result" => nil} -> nil
        %{"result" => result} -> result["run"]
      end)

    count =
      retained
      |> Enum.concat(advanced)
      |> Enum.filter(&is_map/1)
      |> Map.new(&{{&1["program_digest"], &1["original"]}, &1})
      |> Map.values()
      |> Enum.count(&(&1["status"] in ~w(running blocked)))

    if count <= profile.data["active_runs"], do: :ok, else: Error.refusal(:active_run_bound)
  end

  defp proposals(entries, transitions, input, time, profile, limits) do
    if complete_pending?(input) do
      entries
      |> Enum.sort_by(& &1["program"]["ir_digest"])
      |> Enum.zip(transitions)
      |> Enum.reduce_while({:ok, [], []}, fn {entry, transition}, {:ok, proposals, states} ->
        case pending(entry, transition["result"], time, profile, limits) do
          {:ok, next, next_states} -> {:cont, {:ok, proposals ++ next, states ++ next_states}}
          error -> {:halt, error}
        end
      end)
      |> pending_bound(profile)
    else
      with {:ok, proposals} <- emitted_proposals(transitions, profile),
           do: {:ok, proposals, nil}
    end
  end

  defp pending(_, nil, _, _, _), do: {:ok, [], []}
  defp pending(_, %{"run" => nil}, _, _, _), do: {:ok, [], []}

  defp pending(entry, %{"run" => run}, time, profile, limits) do
    program = entry["program"]
    values = ObservationView.values(program, entry["snapshot"], time, limits)

    with {:ok, paths} <- Pending.paths(program, run, values, profile, limits) do
      nodes = Map.new(ExecutionTree.nodes(program["ir"]["steps"]), &{&1["path"], &1})
      records = Map.new(run["steps"], &{&1["path"], &1})
      proposals = Enum.map(paths, &Proposal.from_step(program, run, nodes[&1], records[&1]))

      states =
        Enum.map(
          paths,
          &%{"step_original" => records[&1]["original"], "status" => records[&1]["status"]}
        )

      {:ok, proposals, states}
    end
  end

  defp pending_bound({:ok, proposals, states}, profile) do
    if length(proposals) <= profile.data["pending_work"],
      do: {:ok, proposals, states},
      else: Error.refusal(:pending_work_bound)
  end

  defp pending_bound(error, _), do: error

  defp emitted_proposals(transitions, profile) do
    proposals =
      Enum.flat_map(transitions, fn
        %{"result" => nil} -> []
        %{"result" => result} -> result["proposals"]
      end)

    if length(proposals) <= profile.data["pending_work"],
      do: {:ok, proposals},
      else: Error.refusal(:pending_work_bound)
  end
end
