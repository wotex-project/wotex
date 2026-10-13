defmodule Wotex.Routines.Execution do
  @moduledoc false

  alias Wotex.Routines.{Error, ExecutionTree, Limits, PredicateMachine, Profile}

  @terminal ~w(completed refused failed unknown cancelled)
  @stopped ~w(completed refused failed unknown cancelled expired partial)

  @doc false
  @spec advance(map(), map(), map(), map(), Profile.t(), Limits.t()) ::
          {:ok, map(), [map()]} | {:error, Error.t()}
  def advance(run, program, values, time, profile, limits) do
    state = %{
      run: run,
      program: program,
      values: values,
      time: time,
      profile: profile,
      limits: limits,
      records: Map.new(run["steps"], &{&1["path"], &1}),
      proposals: [],
      blocked: false
    }

    cond do
      run["status"] in @stopped ->
        {:ok, run, []}

      expired_step?(run, time) ->
        {:ok, halt(run, "expired", "deadline_elapsed"), []}

      true ->
        with {:ok, truth} <- predicate(program["ir"]["condition"], state),
             {:ok, state} <- gate(truth, program["ir"]["steps"], run["deadline_ms"], state) do
          finish(state)
        end
    end
  end

  defp expired_step?(run, time) do
    Enum.any?(run["steps"], fn record ->
      record["kind"] in ~w(effect invoke) and record["status"] not in @terminal and
        is_integer(record["deadline_ms"]) and time["elapsed_ms"] >= record["deadline_ms"]
    end)
  end

  @doc false
  @spec halt(map(), String.t(), String.t()) :: map()
  def halt(run, status, reason) do
    steps = Enum.map(run["steps"], &stop_record/1)
    %{run | "steps" => steps, "status" => status, "reason" => reason}
  end

  defp stop_record(%{"status" => status} = record)
       when status in ~w(unsent proposed reserved waiting),
       do: %{record | "status" => "cancelled"}

  defp stop_record(%{"status" => "handed_off"} = record), do: %{record | "status" => "unknown"}
  defp stop_record(record), do: record

  defp gate(true, node, deadline, state), do: visit(node, deadline, state)
  defp gate(_, _, _, state), do: {:ok, %{state | blocked: true}}

  defp visit(node, deadline, state) do
    record = state.records[node["path"]]

    cond do
      record["status"] in @terminal -> {:ok, state}
      state.time["elapsed_ms"] >= deadline -> {:ok, fail(node, state)}
      true -> execute(node, deadline, start(node, deadline, state))
    end
  end

  defp start(node, deadline, state) do
    record = state.records[node["path"]]

    if record["started_ms"] == nil do
      budget = effect_deadline(node, deadline, state)

      put(state, node, %{
        record
        | "started_ms" => state.time["elapsed_ms"],
          "deadline_ms" => budget
      })
    else
      state
    end
  end

  defp effect_deadline(%{"kind" => "effect"} = node, inherited, state) do
    basis = ExecutionTree.basis(state.program, node)
    min(inherited, state.time["elapsed_ms"] + basis["timing"]["deadline_ms"])
  end

  defp effect_deadline(_, inherited, _), do: inherited

  defp execute(%{"kind" => "noop"} = node, _, state), do: {:ok, status(state, node, "completed")}

  defp execute(%{"kind" => "effect"} = node, _, state) do
    case state.records[node["path"]]["status"] do
      "unsent" ->
        proposal = proposal(node, state)
        state = status(state, node, "proposed")
        {:ok, %{state | proposals: [proposal | state.proposals]}}

      _ ->
        {:ok, state}
    end
  end

  defp execute(%{"kind" => "sequence", "steps" => children} = node, deadline, state) do
    with {:ok, state} <- sequence(children, deadline, state), do: {:ok, join(node, children, state)}
  end

  defp execute(%{"kind" => "parallel", "branches" => children} = node, deadline, state) do
    result =
      Enum.reduce_while(children, {:ok, state}, fn child, {:ok, state} ->
        case visit(child, deadline, state) do
          {:ok, state} -> {:cont, {:ok, state}}
          error -> {:halt, error}
        end
      end)

    with {:ok, state} <- result, do: {:ok, join(node, children, state)}
  end

  defp execute(%{"kind" => "if"} = node, deadline, state) do
    with {:ok, state} <- select(node, state) do
      case state.records[node["path"]]["branch"] do
        nil ->
          {:ok, %{state | blocked: true}}

        branch ->
          child = node[branch]
          with {:ok, state} <- visit(child, deadline, state), do: {:ok, join(node, [child], state)}
      end
    end
  end

  defp execute(%{"kind" => "invoke"} = node, deadline, state) do
    record = state.records[node["path"]]
    deadline = min(deadline, record["started_ms"] + node["run_ms"])
    state = put(state, node, %{record | "deadline_ms" => deadline})

    with {:ok, truth} <- predicate(node["condition"], state),
         {:ok, state} <- gate(truth, node["body"], deadline, state) do
      {:ok, join(node, [node["body"]], state)}
    end
  end

  defp execute(%{"kind" => "wait"} = node, deadline, state) do
    record = state.records[node["path"]]
    deadline = min(deadline, record["started_ms"] + node["timeout_ms"])
    state = put(state, node, %{record | "deadline_ms" => deadline})

    if state.time["elapsed_ms"] >= deadline do
      {:ok, fail(node, state)}
    else
      with {:ok, truth} <- predicate(node["condition"], state) do
        {:ok, status(state, node, if(truth == true, do: "completed", else: "waiting"))}
      end
    end
  end

  defp execute(%{"kind" => "delay"} = node, _, state) do
    ready = state.records[node["path"]]["started_ms"] + node["duration_ms"]
    status = if state.time["elapsed_ms"] >= ready, do: "completed", else: "waiting"
    {:ok, status(state, node, status)}
  end

  defp sequence([], _, state), do: {:ok, state}

  defp sequence([child | rest], deadline, state) do
    with {:ok, state} <- visit(child, deadline, state) do
      if state.records[child["path"]]["status"] == "completed",
        do: sequence(rest, deadline, state),
        else: {:ok, state}
    end
  end

  defp select(node, state) do
    record = state.records[node["path"]]

    if record["branch"] == nil do
      with {:ok, truth} <- predicate(node["condition"], state) do
        branch =
          case truth do
            true -> "then"
            false -> "else"
            _ -> nil
          end

        {:ok, put(state, node, %{record | "branch" => branch})}
      end
    else
      {:ok, state}
    end
  end

  defp join(node, children, state) do
    statuses = Enum.map(children, &state.records[&1["path"]]["status"])

    status =
      cond do
        Enum.all?(statuses, &(&1 == "completed")) -> "completed"
        "unknown" in statuses -> "unknown"
        "failed" in statuses -> "failed"
        "refused" in statuses -> "failed"
        true -> "waiting"
      end

    status(state, node, status)
  end

  defp predicate(code, state),
    do: PredicateMachine.run(code, state.values, state.profile, state.limits)

  defp put(state, node, record),
    do: %{state | records: Map.put(state.records, node["path"], record)}

  defp status(state, node, status),
    do: put(state, node, %{state.records[node["path"]] | "status" => status})

  defp fail(node, state), do: status(state, node, "failed")

  defp proposal(node, state) do
    binding = state.program["context"]["bindings"][node["binding"]]
    ref = binding["basis"]

    basis = ExecutionTree.basis(state.program, node)

    %{
      "original" => state.run["original"],
      "step_original" => state.records[node["path"]]["original"],
      "program_digest" => state.program["ir_digest"],
      "path" => node["path"],
      "binding" => node["binding"],
      "installed_basis" => ref,
      "thing_id" => binding["thing_id"],
      "resource_roles" => binding["resource_roles"],
      "resource_domains" => domains(binding),
      "operation" => basis["affordance"]["operation"],
      "input" => node["input"],
      "completion" => node["completion"],
      "evidence_contract" => node["evidence_contract"]
    }
  end

  defp domains(binding) do
    [binding["thing_id"] | Map.values(binding["resource_roles"])]
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp finish(state) do
    steps = Enum.map(state.run["steps"], &state.records[&1["path"]])
    root = state.records[state.program["ir"]["steps"]["path"]]

    failure =
      Enum.find(~w(unknown failed refused), fn status ->
        Enum.any?(steps, &(&1["status"] == status))
      end)

    {status, reason} = aggregate(failure || root["status"], state.blocked, steps)
    run = %{state.run | "steps" => steps, "status" => status, "reason" => reason}
    run = if status in ~w(failed unknown refused partial), do: halt(run, status, reason), else: run

    proposals =
      if status in ~w(failed unknown refused partial), do: [], else: Enum.reverse(state.proposals)

    {:ok, run, proposals}
  end

  defp aggregate(status, _, steps) when status in ~w(failed refused unknown) do
    started = Enum.any?(steps, &(&1["receipts"]["handoff"] != nil))

    reason =
      case status do
        "refused" ->
          "receipt_refused"

        "unknown" ->
          "effect_unknown"

        _ ->
          if(Enum.any?(steps, &(&1["kind"] == "wait" and &1["status"] == "failed")),
            do: "wait_timeout",
            else: "effect_failed"
          )
      end

    {if(started and status != "unknown", do: "partial", else: status), reason}
  end

  defp aggregate("completed", _, _), do: {"completed", nil}
  defp aggregate(_, true, _), do: {"blocked", "condition_blocked"}
  defp aggregate(_, false, _), do: {"running", nil}
end
