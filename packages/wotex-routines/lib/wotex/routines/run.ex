defmodule Wotex.Routines.Run do
  @moduledoc "Closed retained execution state. Validation establishes correspondence, not durable custody."

  alias Wotex.Routines.{Compiler, Error, Event, ExecutionTree, Limits, Profile, Validation}

  @fields ~w(format original program_digest source_digest compiler_basis epoch clock_generation start_ms last_ms deadline_ms status steps spent window reason)
  @statuses ~w(running blocked partial completed refused failed unknown cancelled expired)
  @step_statuses ~w(unsent proposed reserved handed_off waiting completed refused failed unknown cancelled)
  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)
  @reasons ~w(condition_blocked child_condition_blocked receipt_refused effect_failed effect_unknown wait_timeout clock_changed clock_regressed deadline_elapsed window_closed cancelled)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Regenerates every node identity and checks receipts, spend and elapsed-coordinate coherence."
  @spec new(term(), term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, program, profile, limits) do
    with {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- header(data, program, limits),
         {:ok, expected} <- ExecutionTree.records(program, data["original"], limits),
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

  defp header(data, program, limits) do
    with :ok <- Validation.choice(data["format"], ["wotex.routines.run@1"], "/format"),
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
        record(record, expected, node, data, limits)
      end)
    else
      Error.refusal(:invalid_run_paths)
    end
  end

  defp record(record, expected, node, run, limits) do
    with :ok <- Validation.fields(record, Map.keys(expected)),
         true <-
           Map.take(record, ~w(path original kind)) == Map.take(expected, ~w(path original kind)),
         :ok <- Validation.choice(record["status"], @step_statuses, "/steps/status"),
         :ok <- step_time(record, run, limits),
         :ok <- branch(record),
         :ok <- receipts(record["receipts"]) do
      coherence(record, node, run)
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

  defp receipts(data) do
    with :ok <- Validation.fields(data, @slots) do
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
        _ -> ~w(accepted failed unknown)
      end

    with :ok <- Validation.fields(receipt, ~w(ref digest outcome)),
         :ok <- Validation.text(receipt["ref"], "/steps/receipts/ref"),
         :ok <- Validation.digest(receipt["digest"], "/steps/receipts/digest") do
      Validation.choice(receipt["outcome"], outcomes, "/steps/receipts/outcome")
    end
  end

  defp coherence(%{"kind" => "effect"} = record, node, run) do
    receipts = record["receipts"]
    admission = receipts["admission"]
    held = is_map(admission) and admission["outcome"] == "held"
    handoff = receipts["handoff"] != nil

    stages =
      Enum.map(~w(local_queue protocol_response correlated_report reported_match), &receipts[&1])

    valid =
      (not handoff or held) and
        (not Enum.any?(stages, &(&1 != nil)) or handoff) and
        effect_status(record, node, held, handoff, run) and terminal_matches(receipts)

    if valid, do: :ok, else: Error.refusal(:incoherent_receipts)
  end

  defp coherence(record, _, _) do
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
