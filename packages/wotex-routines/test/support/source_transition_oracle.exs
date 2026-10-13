defmodule Wotex.Routines.SourceTransitionOracle do
  @moduledoc false

  alias Wotex.Routines.SourceTruthOracle

  @stages ~w(local_queue protocol_response correlated_report reported_match)
  @stopped ~w(completed refused failed unknown cancelled expired partial)

  @spec new(map(), [map()], map()) :: map()
  def new(source, definitions, deadlines) do
    %{
      source: source,
      tree: tree(source["steps"], [], definitions),
      deadlines: deadlines,
      start: nil,
      last: nil,
      epoch: nil,
      generation: nil,
      status: "running",
      reason: nil
    }
  end

  @spec advance(map(), map(), map(), map(), boolean()) ::
          {:ok, map(), [map()]} | {:error, atom()}
  def advance(state, event, time, values, active \\ true) do
    state = initialize(state, time)

    with {:ok, tree} <- receipt(state.tree, event) do
      state = %{state | tree: tree}
      reason = expiry(state, time)

      cond do
        event["kind"] == "cancel" ->
          {:ok, stop(state, "cancelled", "cancelled"), []}

        not active and state.status not in @stopped ->
          {:ok, stop(state, "cancelled", "inactive_program"), []}

        reason != nil and state.status not in @stopped ->
          {:ok, stop(state, "expired", reason), []}

        state.status in @stopped ->
          {:ok, state, []}

        true ->
          run(%{state | last: time["elapsed_ms"]}, time, values)
      end
    end
  end

  @spec view(map(), [map()]) :: map()
  def view(state, proposals) do
    records = flatten(state.tree)

    %{
      "outcome" => state.status,
      "reason" => state.reason,
      "steps" => Enum.map(records, &record/1),
      "spent" => Enum.flat_map(records, &spent/1),
      "proposals" => proposals
    }
  end

  defp initialize(%{start: nil} = state, time),
    do: %{
      state
      | start: time["elapsed_ms"],
        last: time["elapsed_ms"],
        epoch: time["epoch"],
        generation: time["clock_generation"]
    }

  defp initialize(state, _), do: state

  defp tree(source, path, definitions) do
    {source, children} = children(source, definitions)

    %{
      source: source,
      path: path,
      status: "unsent",
      started: nil,
      deadline: nil,
      branch: nil,
      receipts: %{},
      children:
        Enum.map(Enum.with_index(children), fn {child, index} ->
          tree(child, Enum.concat(path, [index]), definitions)
        end)
    }
  end

  defp children(%{"kind" => "sequence", "steps" => nodes} = source, _), do: {source, nodes}
  defp children(%{"kind" => "parallel", "branches" => nodes} = source, _), do: {source, nodes}
  defp children(%{"kind" => "if"} = source, _), do: {source, [source["then"], source["else"]]}

  defp children(%{"kind" => "invoke", "arguments" => arguments} = source, definitions)
       when map_size(arguments) == 0 do
    child =
      Enum.find(
        definitions,
        &(&1["id"] == source["routine_id"] and
            &1["revision"] == source["revision"])
      ) || raise "missing oracle definition"

    {Map.merge(source, Map.take(child, ~w(condition run_ms))), [child["steps"]]}
  end

  defp children(%{"kind" => kind} = source, _) when kind in ~w(effect noop wait delay),
    do: {source, []}

  defp children(_, _), do: raise("unsupported oracle construct")

  defp expiry(state, time) do
    cond do
      state.epoch != time["epoch"] or state.generation != time["clock_generation"] ->
        "clock_changed"

      time["elapsed_ms"] < state.last ->
        "clock_regressed"

      time["elapsed_ms"] >= state.start + state.source["run_ms"] ->
        "deadline_elapsed"

      Enum.any?(flatten(state.tree), &expired?(&1, time["elapsed_ms"])) ->
        "deadline_elapsed"

      true ->
        nil
    end
  end

  defp expired?(node, now),
    do:
      node.source["kind"] in ~w(effect invoke) and
        node.status not in ~w(completed refused failed unknown cancelled) and
        is_integer(node.deadline) and now >= node.deadline

  defp run(state, time, values) do
    environment = %{now: time["elapsed_ms"], values: values, deadlines: state.deadlines}
    truth = SourceTruthOracle.evaluate(state.source["condition"], values)

    {tree, proposals, blocked} =
      gated(state.tree, truth, state.start + state.source["run_ms"], environment)

    state = %{state | tree: tree}
    records = flatten(tree)

    failure =
      Enum.find(~w(unknown failed refused), fn status ->
        Enum.any?(records, &(&1.status == status))
      end)

    finish(state, failure, proposals, blocked)
  end

  defp finish(state, nil, proposals, blocked) do
    cond do
      state.tree.status == "completed" ->
        {:ok, %{state | status: "completed", reason: nil}, proposals}

      blocked ->
        {:ok, %{state | status: "blocked", reason: "condition_blocked"}, proposals}

      true ->
        {:ok, %{state | status: "running", reason: nil}, proposals}
    end
  end

  defp finish(state, failure, _, _) do
    records = flatten(state.tree)
    handed = Enum.any?(records, &Map.has_key?(&1.receipts, "handoff"))

    reason =
      cond do
        failure == "unknown" ->
          "effect_unknown"

        failure == "refused" ->
          "receipt_refused"

        Enum.any?(records, &(&1.source["kind"] == "wait" and &1.status == "failed")) ->
          "wait_timeout"

        true ->
          "effect_failed"
      end

    status = if handed and failure != "unknown", do: "partial", else: failure
    {:ok, stop(state, status, reason), []}
  end

  defp gated(node, true, deadline, environment), do: visit(node, deadline, environment)
  defp gated(node, _, _, _), do: {node, [], true}

  defp visit(node, deadline, environment) do
    cond do
      node.status in ~w(completed refused failed unknown cancelled) -> {node, [], false}
      environment.now >= deadline -> {%{node | status: "failed"}, [], false}
      true -> execute(start(node, deadline, environment), deadline, environment)
    end
  end

  defp start(%{started: nil} = node, deadline, environment) do
    budget =
      if node.source["kind"] == "effect",
        do:
          min(deadline, environment.now + Map.fetch!(environment.deadlines, node.source["binding"])),
        else: deadline

    %{node | started: environment.now, deadline: budget}
  end

  defp start(node, _, _), do: node

  defp execute(%{source: %{"kind" => "noop"}} = node, _, _),
    do: {%{node | status: "completed"}, [], false}

  defp execute(%{source: %{"kind" => "effect"}, status: "unsent"} = node, _, _) do
    proposal = Map.take(node.source, ~w(binding input completion)) |> Map.put("path", node.path)
    {%{node | status: "proposed"}, [proposal], false}
  end

  defp execute(%{source: %{"kind" => "effect"}} = node, _, _), do: {node, [], false}

  defp execute(%{source: %{"kind" => kind}} = node, deadline, environment)
       when kind in ~w(sequence parallel) do
    {children, proposals, blocked, _} =
      Enum.reduce(node.children, {[], [], false, true}, fn child, accumulated ->
        {children, proposals, blocked, eligible} = accumulated

        {child, added, child_blocked} =
          if kind == "parallel" or eligible,
            do: visit(child, deadline, environment),
            else: {child, [], false}

        {[child | children], proposals ++ added, blocked or child_blocked,
         eligible and child.status == "completed"}
      end)

    children = Enum.reverse(children)
    {join(%{node | children: children}, children), proposals, blocked}
  end

  defp execute(%{source: %{"kind" => "if"}} = node, deadline, environment) do
    branch =
      node.branch ||
        choice(SourceTruthOracle.evaluate(node.source["condition"], environment.values))

    if branch == nil do
      {node, [], true}
    else
      index = if branch == "then", do: 0, else: 1
      {child, proposals, blocked} = visit(Enum.at(node.children, index), deadline, environment)
      node = %{node | branch: branch, children: List.replace_at(node.children, index, child)}
      {join(node, [child]), proposals, blocked}
    end
  end

  defp execute(%{source: %{"kind" => "invoke"}} = node, deadline, environment) do
    deadline = min(deadline, node.started + node.source["run_ms"])
    [child] = node.children
    truth = SourceTruthOracle.evaluate(node.source["condition"], environment.values)
    {child, proposals, blocked} = gated(child, truth, deadline, environment)
    node = %{node | children: [child], deadline: deadline}
    {join(node, [child]), proposals, blocked}
  end

  defp execute(%{source: %{"kind" => "wait"}} = node, deadline, environment) do
    deadline = min(deadline, node.started + node.source["timeout_ms"])

    status =
      cond do
        environment.now >= deadline ->
          "failed"

        SourceTruthOracle.evaluate(node.source["condition"], environment.values) == true ->
          "completed"

        true ->
          "waiting"
      end

    {%{node | status: status, deadline: deadline}, [], false}
  end

  defp execute(%{source: %{"kind" => "delay"}} = node, _, environment) do
    status =
      if environment.now >= node.started + node.source["duration_ms"],
        do: "completed",
        else: "waiting"

    {%{node | status: status}, [], false}
  end

  defp choice(true), do: "then"
  defp choice(false), do: "else"
  defp choice("unknown"), do: nil

  defp join(node, children) do
    statuses = Enum.map(children, & &1.status)

    status =
      cond do
        Enum.all?(statuses, &(&1 == "completed")) -> "completed"
        "unknown" in statuses -> "unknown"
        "failed" in statuses or "refused" in statuses -> "failed"
        true -> "waiting"
      end

    %{node | status: status}
  end

  defp receipt(tree, %{"kind" => kind, "path" => path} = event)
       when kind in ~w(admission handoff result) do
    if tree.path == path do
      update(tree, event)
    else
      updated = Enum.map(tree.children, &receipt(&1, event))

      case Enum.find(updated, &match?({:error, _}, &1)) do
        nil -> {:ok, %{tree | children: Enum.map(updated, &elem(&1, 1))}}
        error -> error
      end
    end
  end

  defp receipt(tree, _), do: {:ok, tree}

  defp update(node, event) do
    slot = if event["kind"] == "result", do: event["stage"], else: event["kind"]

    case Map.fetch(node.receipts, slot) do
      {:ok, ^event} -> {:ok, node}
      {:ok, _} -> {:error, :conflicting_receipt}
      :error -> fresh(node, event, slot)
    end
  end

  defp fresh(%{status: "proposed"} = node, %{"kind" => "admission"} = event, slot),
    do: store(node, event, slot, if(event["outcome"] == "held", do: "reserved", else: "refused"))

  defp fresh(%{status: "reserved"} = node, %{"kind" => "handoff"} = event, slot),
    do: store(node, event, slot, "handed_off")

  defp fresh(%{status: "completed"}, _, _), do: {:error, :out_of_order_receipt}

  defp fresh(node, %{"kind" => "result"} = event, slot) do
    rank = Enum.find_index(@stages, &(&1 == slot))

    cond do
      not Map.has_key?(node.receipts, "handoff") or Map.has_key?(node.receipts, "terminal") ->
        {:error, :out_of_order_receipt}

      Enum.any?(Enum.drop(@stages, rank + 1), &Map.has_key?(node.receipts, &1)) ->
        {:error, :out_of_order_receipt}

      true ->
        result(node, event, slot, rank)
    end
  end

  defp fresh(_, _, _), do: {:error, :out_of_order_receipt}

  defp result(node, event, slot, rank) do
    status =
      if event["outcome"] in ~w(failed unknown),
        do: event["outcome"],
        else:
          if(rank >= Enum.find_index(@stages, &(&1 == node.source["completion"])),
            do: "completed",
            else: node.status
          )

    {:ok, node} = store(node, event, slot, status)

    receipts =
      if status in ~w(failed unknown),
        do: Map.put(node.receipts, "terminal", event),
        else: node.receipts

    {:ok, %{node | receipts: receipts}}
  end

  defp store(node, event, slot, status),
    do: {:ok, %{node | receipts: Map.put(node.receipts, slot, event), status: status}}

  defp stop(state, status, reason),
    do: %{state | tree: stop_tree(state.tree), status: status, reason: reason}

  defp stop_tree(node) do
    status =
      cond do
        node.status in ~w(unsent proposed reserved waiting) -> "cancelled"
        node.status == "handed_off" -> "unknown"
        true -> node.status
      end

    %{node | status: status, children: Enum.map(node.children, &stop_tree/1)}
  end

  defp flatten(node), do: [node | Enum.flat_map(node.children, &flatten/1)]

  defp record(node) do
    receipts =
      Map.new(
        ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal),
        fn slot -> {slot, receipt_view(node.receipts[slot])} end
      )

    %{
      "path" => node.path,
      "kind" => node.source["kind"],
      "status" => node.status,
      "started_ms" => node.started,
      "deadline_ms" => node.deadline,
      "branch" => node.branch,
      "receipts" => receipts
    }
  end

  defp receipt_view(nil), do: nil

  defp receipt_view(event),
    do: %{
      "ref" => event["ref"],
      "outcome" => if(event["kind"] == "handoff", do: "marked", else: event["outcome"])
    }

  defp spent(node) do
    case node.receipts["admission"] do
      %{"outcome" => "held", "ref" => ref} -> [%{"path" => node.path, "ref" => ref}]
      _ -> []
    end
  end
end
