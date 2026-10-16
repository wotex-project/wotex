defmodule Wotex.Routines.TransitionTree do
  @moduledoc false

  alias Wotex.Routines.{ExecutionTree, TransitionChecks, TransitionObservation, Validation}

  @terminal ~w(completed refused failed unknown cancelled)
  @stopped ~w(completed refused failed unknown cancelled expired partial)
  @failure ~w(failed unknown refused partial)

  @doc false
  @spec verify(map(), map(), map(), atom()) ::
          :ok | {:error, Wotex.Routines.Error.t()}
  def verify(c, run, statuses, mode) when mode in [:halt, :stopped] do
    old = records(c.before)

    with :ok <-
           Validation.each(run["steps"], fn record ->
             previous = Map.get(old, record["path"], empty())
             status = statuses[record["path"]]
             status = if mode == :halt, do: stopped(status), else: status

             motion(
               record,
               previous["started_ms"],
               previous["deadline_ms"],
               previous["branch"],
               status
             )
           end) do
      TransitionChecks.equal(c.result["proposals"], [], "/proposals")
    end
  end

  def verify(c, run, statuses, :execute) do
    state = %{
      c: c,
      run: run,
      before: records(c.before),
      after: records(run),
      nodes: Map.new(ExecutionTree.nodes(c.program["ir"]["steps"]), &{&1["path"], &1}),
      logical: statuses,
      seen: MapSet.new(),
      blocked: false,
      emissions: [],
      halt: run["status"] in @failure
    }

    root = c.program["ir"]["steps"]

    visited =
      if truth(c.program["ir"]["condition"], state) == true,
        do: visit(root, run["deadline_ms"], state),
        else: {:ok, %{state | blocked: true}}

    with {:ok, state} <- visited,
         :ok <- untouched(state),
         :ok <- aggregate(state, root) do
      proposals(state)
    end
  end

  @doc false
  @spec eligible?(map(), map(), map(), list()) :: boolean()
  def eligible?(program, run, values, path) do
    run["status"] not in @stopped and
      TransitionObservation.predicate(program["ir"]["condition"], values) == true and
      eligible_node(program["ir"]["steps"], records(run), values, path)
  end

  defp eligible_node(node, records, values, path) do
    record = records[node["path"]]

    if record["status"] in @stopped or record["started_ms"] == nil do
      false
    else
      eligible_child(node, record, records, values, path)
    end
  end

  defp eligible_child(%{"kind" => "effect", "path" => path}, record, _, _, target),
    do: path == target and record["status"] in ~w(proposed reserved)

  defp eligible_child(%{"kind" => "sequence", "steps" => steps}, _, records, values, path) do
    case Enum.find(steps, &(records[&1["path"]]["status"] != "completed")) do
      nil -> false
      node -> eligible_node(node, records, values, path)
    end
  end

  defp eligible_child(%{"kind" => "parallel", "branches" => children}, _, records, values, path),
    do: Enum.any?(children, &eligible_node(&1, records, values, path))

  defp eligible_child(%{"kind" => "if"} = node, %{"branch" => branch}, records, values, path)
       when branch in ~w(then else), do: eligible_node(node[branch], records, values, path)

  defp eligible_child(%{"kind" => "invoke"} = node, _, records, values, path),
    do:
      TransitionObservation.predicate(node["condition"], values) == true and
        eligible_node(node["body"], records, values, path)

  defp eligible_child(_, _, _, _, _), do: false

  defp visit(node, inherited, state) do
    path = node["path"]
    previous = Map.get(state.before, path, empty())
    status = state.logical[path]

    cond do
      status in @terminal ->
        conclusion(
          node,
          previous["started_ms"],
          previous["deadline_ms"],
          previous["branch"],
          status,
          state
        )

      state.c.time["elapsed_ms"] >= inherited ->
        conclusion(
          node,
          previous["started_ms"],
          previous["deadline_ms"],
          previous["branch"],
          "failed",
          state
        )

      true ->
        start = previous["started_ms"] || state.c.time["elapsed_ms"]
        deadline = initial_deadline(node, inherited, previous, state)
        instruction(node, inherited, start, deadline, previous["branch"], state)
    end
  end

  defp initial_deadline(node, inherited, %{"started_ms" => nil}, state) do
    if node["kind"] == "effect" do
      basis = ExecutionTree.basis(state.c.program, node)
      min(inherited, state.c.time["elapsed_ms"] + basis["timing"]["deadline_ms"])
    else
      inherited
    end
  end

  defp initial_deadline(_, _, previous, _), do: previous["deadline_ms"]

  defp instruction(%{"kind" => "noop"} = node, _, start, deadline, branch, state),
    do: conclusion(node, start, deadline, branch, "completed", state)

  defp instruction(%{"kind" => "effect"} = node, _, start, deadline, branch, state) do
    fresh = state.logical[node["path"]] == "unsent"
    status = if fresh, do: "proposed", else: state.logical[node["path"]]

    with {:ok, state} <- conclusion(node, start, deadline, branch, status, state) do
      if fresh,
        do: {:ok, %{state | emissions: [node["path"] | state.emissions]}},
        else: {:ok, state}
    end
  end

  defp instruction(%{"kind" => "delay"} = node, _, start, deadline, branch, state) do
    status =
      if state.c.time["elapsed_ms"] >= start + node["duration_ms"], do: "completed", else: "waiting"

    conclusion(node, start, deadline, branch, status, state)
  end

  defp instruction(%{"kind" => "wait"} = node, inherited, start, _, branch, state) do
    deadline = min(inherited, start + node["timeout_ms"])

    status =
      cond do
        state.c.time["elapsed_ms"] >= deadline -> "failed"
        truth(node["condition"], state) == true -> "completed"
        true -> "waiting"
      end

    conclusion(node, start, deadline, branch, status, state)
  end

  defp instruction(
         %{"kind" => "sequence", "steps" => children} = node,
         inherited,
         start,
         deadline,
         branch,
         state
       ) do
    with {:ok, state} <- prefix(children, inherited, state),
         do: joined(node, children, start, deadline, branch, state)
  end

  defp instruction(
         %{"kind" => "parallel", "branches" => children} = node,
         inherited,
         start,
         deadline,
         branch,
         state
       ) do
    with {:ok, state} <- all(children, inherited, state),
         do: joined(node, children, start, deadline, branch, state)
  end

  defp instruction(%{"kind" => "if"} = node, inherited, start, deadline, branch, state) do
    selected = branch || selection(truth(node["condition"], state))

    if selected == nil do
      conclusion(node, start, deadline, nil, state.logical[node["path"]], %{state | blocked: true})
    else
      child = node[selected]

      with {:ok, state} <- visit(child, inherited, state),
           do: joined(node, [child], start, deadline, selected, state)
    end
  end

  defp instruction(%{"kind" => "invoke"} = node, inherited, start, _, branch, state) do
    deadline = min(inherited, start + node["run_ms"])
    child = node["body"]

    gated =
      if truth(node["condition"], state) == true,
        do: visit(child, deadline, state),
        else: {:ok, %{state | blocked: true}}

    with {:ok, state} <- gated, do: joined(node, [child], start, deadline, branch, state)
  end

  defp prefix([], _, state), do: {:ok, state}

  defp prefix([child | rest], deadline, state) do
    with {:ok, state} <- visit(child, deadline, state) do
      if state.logical[child["path"]] == "completed",
        do: prefix(rest, deadline, state),
        else: {:ok, state}
    end
  end

  defp all(children, deadline, state) do
    Enum.reduce_while(children, {:ok, state}, fn child, {:ok, state} ->
      case visit(child, deadline, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp joined(node, children, start, deadline, branch, state) do
    statuses = Enum.map(children, &state.logical[&1["path"]])

    status =
      cond do
        Enum.all?(statuses, &(&1 == "completed")) -> "completed"
        "unknown" in statuses -> "unknown"
        "failed" in statuses or "refused" in statuses -> "failed"
        true -> "waiting"
      end

    conclusion(node, start, deadline, branch, status, state)
  end

  defp conclusion(node, start, deadline, branch, logical, state) do
    status = if state.halt, do: stopped(logical), else: logical

    with :ok <- motion(state.after[node["path"]], start, deadline, branch, status) do
      {:ok,
       %{
         state
         | logical: Map.put(state.logical, node["path"], logical),
           seen: MapSet.put(state.seen, node["path"])
       }}
    end
  end

  defp untouched(state) do
    Validation.each(state.run["steps"], fn record ->
      if MapSet.member?(state.seen, record["path"]) do
        :ok
      else
        previous = Map.get(state.before, record["path"], empty())
        logical = state.logical[record["path"]]
        status = if state.halt, do: stopped(logical), else: logical
        motion(record, previous["started_ms"], previous["deadline_ms"], previous["branch"], status)
      end
    end)
  end

  defp aggregate(state, root) do
    failure = Enum.find(~w(unknown failed refused), &(&1 in Map.values(state.logical)))
    status = failure || state.logical[root["path"]]
    {status, reason} = root_outcome(status, state)
    TransitionChecks.fields(state.run, %{"status" => status, "reason" => reason}, "/run")
  end

  defp root_outcome(status, state) when status in ~w(failed refused unknown) do
    handoff = Enum.any?(state.run["steps"], &(&1["receipts"]["handoff"] != nil))

    reason =
      case status do
        "refused" ->
          "receipt_refused"

        "unknown" ->
          "effect_unknown"

        "failed" ->
          if Enum.any?(
               state.run["steps"],
               &(&1["kind"] == "wait" and state.logical[&1["path"]] == "failed")
             ), do: "wait_timeout", else: "effect_failed"
      end

    {if(handoff and status != "unknown", do: "partial", else: status), reason}
  end

  defp root_outcome("completed", _), do: {"completed", nil}
  defp root_outcome(_, %{blocked: true}), do: {"blocked", "condition_blocked"}
  defp root_outcome(_, _), do: {"running", nil}

  defp proposals(state) do
    paths = if state.halt, do: [], else: Enum.reverse(state.emissions)
    actual = state.c.result["proposals"]

    with :ok <- TransitionChecks.condition(length(actual) == length(paths), "/proposals") do
      Enum.zip(actual, paths)
      |> Validation.each(fn {proposal, path} ->
        proposal(state.c.program, state.run, state.nodes[path], state.after[path], proposal)
      end)
    end
  end

  @doc false
  @spec proposal(map(), map(), map(), map(), map()) :: :ok | {:error, Wotex.Routines.Error.t()}
  def proposal(program, run, node, record, claimed) do
    binding = program["context"]["bindings"][node["binding"]]
    basis = ExecutionTree.basis(program, node)
    domains = Enum.sort(Enum.uniq([binding["thing_id"] | Map.values(binding["resource_roles"])]))

    TransitionChecks.equal(
      claimed,
      %{
        "original" => run["original"],
        "step_original" => record["original"],
        "program_digest" => program["ir_digest"],
        "path" => node["path"],
        "binding" => node["binding"],
        "installed_basis" => binding["basis"],
        "thing_id" => binding["thing_id"],
        "resource_roles" => binding["resource_roles"],
        "resource_domains" => domains,
        "operation" => basis["affordance"]["operation"],
        "input" => node["input"],
        "completion" => node["completion"],
        "evidence_contract" => node["evidence_contract"]
      },
      "/proposals"
    )
  end

  defp motion(record, start, deadline, branch, status),
    do:
      TransitionChecks.fields(
        record,
        %{"started_ms" => start, "deadline_ms" => deadline, "branch" => branch, "status" => status},
        "/run/steps"
      )

  defp truth(code, state), do: TransitionObservation.predicate(code, state.c.values)
  defp records(nil), do: %{}
  defp records(run), do: Map.new(run["steps"], &{&1["path"], &1})
  defp empty, do: %{"started_ms" => nil, "deadline_ms" => nil, "branch" => nil}
  defp selection(true), do: "then"
  defp selection(false), do: "else"
  defp selection("unknown"), do: nil
  defp stopped(status) when status in ~w(unsent proposed reserved waiting), do: "cancelled"
  defp stopped("handed_off"), do: "unknown"
  defp stopped(status), do: status
end
