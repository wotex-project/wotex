defmodule Wotex.Routines.Run do
  @moduledoc """
  Validates retained execution state for one original and program revision.

  `Wotex.Routines.Run.new/4` takes a complete run map or native value, its
  compiled program, `Wotex.Routines.Profile` and `Wotex.Routines.Limits`.
  It returns `{:ok, run}` or `{:error, error}` with a `Wotex.Routines.Error`.
  `Wotex.Routines.Run.to_map/4` repeats these checks before returning the
  complete retained representation.

  Validation regenerates every expanded node's path and original, then checks
  program/source/compiler identities, elapsed coordinates and deadlines,
  selected branches, sequence/join coherence, receipt stages and spent admission
  references. Missing or altered records cannot be repaired by updating only a
  digest. Admission, handoff, local queue, protocol response and qualified report
  receipts remain separate slots with distinct completion meanings.

  The original `"wotex.routines.run@1"` representation retains its exact outer
  members and seven receipt slots. `"wotex.routines.run@2"` adds a required
  `"time_format"`, selected as `"wotex.routines.time@1"` or
  `"wotex.routines.time@2"`, and an eighth `"satisfied"` receipt slot on every
  step. That slot is `nil` or a closed `"ref"`/`"digest"`/`"outcome"` record
  with outcome `"matched"`. The kernel hashes the complete satisfied Event for
  that digest. A satisfied effect must be completed, target an absolute
  Property write requiring
  `"reported_match"`, and have no handoff or result-stage receipts. Admission
  is absent or held, with its exact retained spend. Mixed receipt stages,
  satisfied non-effect nodes and missing held spend refuse coherence checks.
  Construction preserves the supplied format and never upgrades history.

  A new kernel run under Time@2 is Run@2 with Time@2 correspondence. A new run
  under the original five-member Time remains Run@1. Continuation must use the
  run's retained time grammar; `Wotex.Routines.Kernel.advance/7` refuses
  `:clock_format_mismatch` before changing history when the grammar differs.
  A generation replacement within that grammar follows ordinary clock expiry.
  Only an accepted current-state satisfaction promotes a kernel Run@1 to
  Run@2 with `"time_format" => "wotex.routines.time@1"`. It adds nil satisfied
  slots to the other steps and preserves their identities, receipts, branches
  and spent references; resume and ordinary receipts do not promote a run.

  Obtain transitions from `Wotex.Routines.Kernel.advance/7`, retain the returned
  run data, and supply it in the next call's original/busy prior state as
  appropriate. Retain the returned edge baseline separately. These constructors
  validate correspondence; they do not select the correct original from history
  or establish that receipts were committed by a trusted consumer.

  The consumer owns durable custody, no-repeat indexes and receipt qualification.
  Retained spent references and handed-off uncertainty do not become refundable
  or safe to repeat because a run is cancelled, expired, restored or revalidated.
  """

  alias Wotex.Routines.{Compiler, Error, Event, ExecutionTree, Limits, Profile, Validation}

  @fields ~w(format original program_digest source_digest compiler_basis epoch clock_generation start_ms last_ms deadline_ms status steps spent window reason)
  @statuses ~w(running blocked partial completed refused failed unknown cancelled expired)
  @step_statuses ~w(unsent proposed reserved handed_off waiting completed refused failed unknown cancelled)
  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)
  @reasons ~w(condition_blocked child_condition_blocked receipt_refused effect_failed effect_unknown wait_timeout clock_changed clock_regressed deadline_elapsed window_closed cancelled inactive_program)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Regenerates every node identity and checks receipts, spend and elapsed-coordinate coherence."
  @spec new(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, program, profile, limits) do
    with {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- fields(data),
         :ok <- header(data, program, limits),
         {:ok, expected} <- ExecutionTree.records(program, data["original"], limits, data["format"]),
         :ok <- steps(data, expected, program, limits),
         :ok <- spent(data),
         :ok <- tree_coherence(data, program),
         :ok <- window(data, program, limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates retained state before returning its complete representation."
  @spec to_map(term(), term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(run, program, profile, limits) do
    with {:ok, run} <- new(run, program, profile, limits), do: {:ok, run.data}
  end

  defp fields(%{"format" => "wotex.routines.run@2"} = data) do
    with :ok <- Validation.fields(data, ["time_format" | @fields]) do
      Validation.choice(
        data["time_format"],
        ~w(wotex.routines.time@1 wotex.routines.time@2),
        "/time_format"
      )
    end
  end

  defp fields(data), do: Validation.fields(data, @fields)

  defp header(data, program, limits) do
    with :ok <-
           Validation.choice(
             data["format"],
             ~w(wotex.routines.run@1 wotex.routines.run@2),
             "/format"
           ),
         :ok <- Validation.text(data["original"], "/original"),
         :ok <- Validation.text(data["epoch"], "/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/clock_generation"),
         :ok <- Validation.choice(data["status"], @statuses, "/status"),
         :ok <- nullable_reason(data["reason"]),
         :ok <- coordinates(data, limits),
         true <- data["deadline_ms"] == data["start_ms"] + program["ir"]["run_ms"] do
      matching =
        data["program_digest"] == program["ir_digest"] and
          data["source_digest"] == program["source_digest"] and
          data["compiler_basis"] == program["context"]["compiler_basis"]

      if matching, do: :ok, else: Error.refusal(:stale_run)
    else
      false -> Error.refusal(:incoherent_run_time)
      error -> error
    end
  end

  defp nullable_reason(nil), do: :ok
  defp nullable_reason(reason), do: Validation.choice(reason, @reasons, "/reason")

  defp coordinates(data, limits) do
    with :ok <- Validation.integer(data["start_ms"], limits, "/start_ms", 0),
         :ok <- Validation.integer(data["last_ms"], limits, "/last_ms", 0),
         :ok <- Validation.integer(data["deadline_ms"], limits, "/deadline_ms", 1) do
      if data["start_ms"] <= data["last_ms"] and data["start_ms"] < data["deadline_ms"],
        do: :ok,
        else: Error.refusal(:incoherent_run_time)
    end
  end

  defp steps(data, expected, program, limits) do
    actual = data["steps"]

    if is_list(actual) and length(actual) == length(expected) do
      nodes = ExecutionTree.nodes(program["ir"]["steps"])

      Validation.each(Enum.zip([actual, expected, nodes]), fn {record, expected, node} ->
        record(record, expected, node, data, program, limits)
      end)
    else
      Error.refusal(:invalid_run_paths)
    end
  end

  defp record(record, expected, node, run, program, limits) do
    with :ok <- Validation.fields(record, Map.keys(expected)),
         true <-
           Map.take(record, ~w(path original kind)) == Map.take(expected, ~w(path original kind)),
         :ok <- Validation.choice(record["status"], @step_statuses, "/steps/status"),
         :ok <- step_time(record, run, limits),
         :ok <- branch(record),
         :ok <- receipts(record["receipts"], run) do
      coherence(record, node, run, program)
    else
      false -> Error.refusal(:invalid_run_paths)
      error -> error
    end
  end

  defp step_time(%{"started_ms" => nil, "deadline_ms" => nil, "status" => status}, _, _)
       when status in ~w(unsent cancelled), do: :ok

  defp step_time(record, run, limits) do
    with :ok <- Validation.integer(record["started_ms"], limits, "/steps/started_ms", 0),
         :ok <- Validation.integer(record["deadline_ms"], limits, "/steps/deadline_ms", 1) do
      if record["started_ms"] >= run["start_ms"] and record["started_ms"] <= run["last_ms"] and
           record["deadline_ms"] > record["started_ms"] and
           record["deadline_ms"] <= run["deadline_ms"],
         do: :ok,
         else: Error.refusal(:incoherent_step_time)
    end
  end

  defp branch(%{"kind" => "if", "branch" => branch}) when branch in [nil, "then", "else"],
    do: :ok

  defp branch(%{"kind" => kind, "branch" => nil}) when kind != "if", do: :ok
  defp branch(_), do: Error.refusal(:incoherent_branch)

  defp receipts(data, run) do
    slots = if run["format"] == "wotex.routines.run@2", do: ["satisfied" | @slots], else: @slots

    with :ok <- Validation.fields(data, slots) do
      Validation.each(Map.to_list(data), &receipt/1)
    end
  end

  defp receipt({_, nil}), do: :ok

  defp receipt({slot, receipt}) do
    outcomes =
      case slot do
        "admission" -> ~w(held refused)
        "handoff" -> ["marked"]
        "terminal" -> ~w(failed unknown)
        "satisfied" -> ["matched"]
        _ -> ~w(accepted failed unknown)
      end

    with :ok <- Validation.fields(receipt, ~w(ref digest outcome)),
         :ok <- Validation.text(receipt["ref"], "/steps/receipts/ref"),
         :ok <- Validation.digest(receipt["digest"], "/steps/receipts/digest") do
      Validation.choice(receipt["outcome"], outcomes, "/steps/receipts/outcome")
    end
  end

  defp coherence(
         %{"kind" => "effect", "receipts" => %{"satisfied" => receipt}} = record,
         node,
         run,
         program
       )
       when is_map(receipt) do
    admission = record["receipts"]["admission"]
    affordance = ExecutionTree.basis(program, node)["affordance"]

    valid =
      run["format"] == "wotex.routines.run@2" and record["status"] == "completed" and
        node["completion"] == "reported_match" and
        Map.take(affordance, ~w(type operation)) == %{
          "type" => "property",
          "operation" => "writeproperty"
        } and
        (admission == nil or admission["outcome"] == "held") and
        Enum.all?(
          ~w(handoff local_queue protocol_response correlated_report reported_match terminal),
          &(record["receipts"][&1] == nil)
        )

    if valid, do: :ok, else: Error.refusal(:incoherent_receipts)
  end

  defp coherence(%{"kind" => "effect"} = record, node, run, _) do
    receipts = record["receipts"]
    admission = receipts["admission"]
    held = is_map(admission) and admission["outcome"] == "held"
    handoff = receipts["handoff"] != nil

    stages =
      Enum.map(~w(local_queue protocol_response correlated_report reported_match), &receipts[&1])

    valid =
      receipts["satisfied"] == nil and
        (not handoff or held) and
        (not Enum.any?(stages, &(&1 != nil)) or handoff) and
        effect_status(record, node, held, handoff, run) and terminal_matches(receipts)

    if valid, do: :ok, else: Error.refusal(:incoherent_receipts)
  end

  defp coherence(record, _, _, _) do
    if Enum.all?(Map.values(record["receipts"]), &is_nil/1) and
         record["status"] not in ~w(proposed reserved handed_off refused),
       do: :ok,
       else: Error.refusal(:incoherent_receipts)
  end

  defp effect_status(%{"status" => "unsent"} = record, _, _, _, _),
    do: record["started_ms"] == nil and Enum.all?(Map.values(record["receipts"]), &is_nil/1)

  defp effect_status(%{"status" => "proposed"} = record, _, _, _, _),
    do: record["started_ms"] != nil and record["receipts"]["admission"] == nil

  defp effect_status(%{"status" => "reserved"}, _, held, handoff, _), do: held and not handoff

  defp effect_status(%{"status" => "handed_off"} = record, _, _, handoff, _),
    do: handoff and record["receipts"]["terminal"] == nil

  defp effect_status(%{"status" => "completed"} = record, node, _, handoff, _),
    do:
      handoff and record["receipts"]["terminal"] == nil and
        accepted_stage?(record["receipts"], node)

  defp effect_status(%{"status" => "refused"} = record, _, held, handoff, _),
    do: record["receipts"]["admission"] != nil and not held and not handoff

  defp effect_status(%{"status" => "failed"} = record, _, _, handoff, _),
    do: handoff and match?(%{"outcome" => "failed"}, record["receipts"]["terminal"])

  defp effect_status(%{"status" => "unknown"} = record, _, _, handoff, run),
    do:
      handoff and
        (match?(%{"outcome" => "unknown"}, record["receipts"]["terminal"]) or run["reason"] != nil)

  defp effect_status(%{"status" => "cancelled"}, _, _, handoff, _), do: not handoff
  defp effect_status(_, _, _, _, _), do: false

  defp accepted_stage?(receipts, node) do
    stages = ~w(local_queue protocol_response correlated_report reported_match)
    rank = Enum.find_index(stages, &(&1 == node["completion"]))

    stages
    |> Enum.drop(rank)
    |> Enum.any?(&match?(%{"outcome" => "accepted"}, receipts[&1]))
  end

  defp terminal_matches(%{"terminal" => nil}), do: true

  defp terminal_matches(receipts) do
    Enum.any?(~w(local_queue protocol_response correlated_report reported_match), fn slot ->
      receipts[slot] == receipts["terminal"]
    end)
  end

  defp spent(data) do
    expected =
      Enum.flat_map(data["steps"], fn record ->
        case record["receipts"]["admission"] do
          %{"outcome" => "held", "ref" => ref} ->
            [%{"original" => record["original"], "ref" => ref}]

          _ ->
            []
        end
      end)

    if data["spent"] == expected, do: :ok, else: Error.refusal(:incoherent_spend)
  end

  defp tree_coherence(run, program) do
    records = Map.new(run["steps"], &{&1["path"], &1})
    root = program["ir"]["steps"]

    if run["status"] != "completed" or records[root["path"]]["status"] == "completed",
      do: tree(root, run["deadline_ms"], records, run, program),
      else: Error.refusal(:incoherent_run_status)
  end

  defp tree(node, inherited, records, run, program) do
    record = records[node["path"]]
    children = ExecutionTree.children(node)
    deadline = node_deadline(node, record, inherited, program)

    with true <- record["started_ms"] == nil or record["deadline_ms"] == deadline,
         :ok <- completion(node, record, children, records, run),
         :ok <- order(node, children, records) do
      Validation.each(children, &tree(&1, deadline, records, run, program))
    else
      false -> Error.refusal(:incoherent_step_time)
      error -> error
    end
  end

  defp node_deadline(%{"kind" => "effect"} = node, %{"started_ms" => started}, inherited, program)
       when is_integer(started),
       do: min(inherited, started + ExecutionTree.basis(program, node)["timing"]["deadline_ms"])

  defp node_deadline(%{"kind" => kind} = node, %{"started_ms" => started}, inherited, _)
       when kind in ~w(invoke wait) and is_integer(started) do
    budget = if kind == "invoke", do: node["run_ms"], else: node["timeout_ms"]
    min(inherited, started + budget)
  end

  defp node_deadline(_, _, inherited, _), do: inherited

  defp completion(_, %{"status" => status}, _, _, _) when status != "completed", do: :ok

  defp completion(%{"kind" => "delay", "duration_ms" => duration}, record, _, _, run) do
    if record["started_ms"] + duration <= run["last_ms"],
      do: :ok,
      else: Error.refusal(:premature_delay)
  end

  defp completion(%{"kind" => "if"}, record, children, records, _) do
    index = if record["branch"] == "then", do: 0, else: 1

    if record["branch"] != nil and
         records[Enum.at(children, index)["path"]]["status"] == "completed",
       do: :ok,
       else: Error.refusal(:incoherent_join)
  end

  defp completion(_, _, children, records, _) do
    if Enum.all?(children, &(records[&1["path"]]["status"] == "completed")),
      do: :ok,
      else: Error.refusal(:incoherent_join)
  end

  defp order(%{"kind" => "sequence"}, children, records) do
    children
    |> Enum.chunk_every(2, 1, :discard)
    |> Validation.each(fn [left, right] ->
      if records[right["path"]]["started_ms"] == nil or
           records[left["path"]]["status"] == "completed",
         do: :ok,
         else: Error.refusal(:incoherent_sequence)
    end)
  end

  defp order(%{"kind" => "if", "path" => path}, children, records) do
    branch = records[path]["branch"]
    index = if branch == "then", do: 1, else: 0
    excluded = if branch == nil, do: children, else: [Enum.at(children, index)]
    nodes = Enum.flat_map(excluded, &ExecutionTree.nodes/1)

    if Enum.all?(nodes, &(records[&1["path"]]["started_ms"] == nil)),
      do: :ok,
      else: Error.refusal(:incoherent_branch)
  end

  defp order(_, _, _), do: :ok

  defp window(%{"window" => nil}, %{"ir" => %{"trigger" => %{"kind" => kind}}}, _)
       when kind not in ~w(due countdown), do: :ok

  defp window(
         %{"window" => window} = data,
         %{"ir" => %{"trigger" => %{"kind" => kind} = trigger}},
         limits
       )
       when is_map(window) and kind in ~w(due countdown) do
    event = Map.merge(window, Map.take(data, ~w(original program_digest)))
    event = Map.put(event, "kind", if(kind == "due", do: "due", else: "elapsed_due"))

    with {:ok, event} <- Event.new(event, limits),
         true <-
           event.data["schedule_id"] == trigger["schedule_id"] and
             event.data["schedule_basis"] == trigger["schedule_basis"] do
      :ok
    else
      false -> Error.refusal(:stale_due_window)
      error -> error
    end
  end

  defp window(_, _, _), do: Error.refusal(:invalid_run_window)
end
