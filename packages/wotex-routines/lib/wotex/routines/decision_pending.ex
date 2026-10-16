defmodule Wotex.Routines.DecisionPending do
  @moduledoc false

  alias Wotex.Routines.{Error, ExecutionTree, TransitionObservation, TransitionTree}

  @stopped ~w(completed refused failed unknown cancelled expired partial)

  @doc false
  @spec consume(map(), map() | nil, map(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def consume(_, nil, _, cursor), do: {:ok, cursor}
  def consume(_, %{"run" => nil}, _, cursor), do: {:ok, cursor}

  def consume(entry, %{"run" => run}, time, cursor) do
    program = entry["program"]
    values = TransitionObservation.values(program, entry["snapshot"], time, cursor.limits)

    state = %{
      program: program,
      run: run,
      records: Map.new(run["steps"], &{&1["path"], &1}),
      values: values
    }

    if run["status"] in @stopped or
         TransitionObservation.predicate(program["ir"]["condition"], values) != true,
       do: {:ok, cursor},
       else: visit(program["ir"]["steps"], state, cursor)
  end

  defp visit(node, state, cursor) do
    record = state.records[node["path"]]

    if record["status"] in @stopped or record["started_ms"] == nil,
      do: {:ok, cursor},
      else: instruction(node, record, state, cursor)
  end

  defp instruction(%{"kind" => "effect"} = node, %{"status" => status} = record, state, cursor)
       when status in ~w(proposed reserved) do
    case {cursor.proposals, cursor.states} do
      {[proposal | proposals], [claimed | states]} ->
        expected = %{"step_original" => record["original"], "status" => record["status"]}

        with :ok <- check(claimed == expected),
             :ok <- proposal(state, node, record, proposal),
             :ok <- bound(cursor.count + 1, cursor.maximum) do
          {:ok, %{cursor | proposals: proposals, states: states, count: cursor.count + 1}}
        end

      _ ->
        Error.refusal(:invalid_collection_decision, "/proposal_states")
    end
  end

  defp instruction(%{"kind" => "sequence", "steps" => children}, _, state, cursor) do
    case Enum.find(children, &(state.records[&1["path"]]["status"] != "completed")) do
      nil -> {:ok, cursor}
      child -> visit(child, state, cursor)
    end
  end

  defp instruction(%{"kind" => "parallel"} = node, _, state, cursor) do
    Enum.reduce_while(ExecutionTree.children(node), {:ok, cursor}, fn child, {:ok, cursor} ->
      case visit(child, state, cursor) do
        {:ok, cursor} -> {:cont, {:ok, cursor}}
        error -> {:halt, error}
      end
    end)
  end

  defp instruction(%{"kind" => "if"} = node, %{"branch" => branch}, state, cursor)
       when branch in ~w(then else), do: visit(node[branch], state, cursor)

  defp instruction(%{"kind" => "invoke"} = node, _, state, cursor) do
    if TransitionObservation.predicate(node["condition"], state.values) == true,
      do: visit(node["body"], state, cursor),
      else: {:ok, cursor}
  end

  defp instruction(_, _, _, cursor), do: {:ok, cursor}

  defp proposal(state, node, record, claimed) do
    case TransitionTree.proposal(state.program, state.run, node, record, claimed) do
      :ok -> :ok
      {:error, _} -> Error.refusal(:invalid_collection_decision, "/proposals")
    end
  end

  defp check(true), do: :ok
  defp check(false), do: Error.refusal(:invalid_collection_decision, "/proposal_states")
  defp bound(count, maximum) when count <= maximum, do: :ok
  defp bound(_, _), do: Error.refusal(:pending_work_bound)
end
