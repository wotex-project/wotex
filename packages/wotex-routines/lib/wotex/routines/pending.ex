defmodule Wotex.Routines.Pending do
  @moduledoc false

  alias Wotex.Routines.{Error, ExecutionTree, Limits, PredicateMachine, Profile}

  @stopped ~w(completed refused failed unknown cancelled expired partial)

  @doc false
  @spec paths(map(), map(), map(), Profile.t(), Limits.t()) ::
          {:ok, [[non_neg_integer()]]} | {:error, Error.t()}
  def paths(program, run, values, profile, limits) do
    state = %{
      records: Map.new(run["steps"], &{&1["path"], &1}),
      values: values,
      profile: profile,
      limits: limits
    }

    if run["status"] in @stopped,
      do: {:ok, []},
      else: gate(program["ir"]["condition"], program["ir"]["steps"], state)
  end

  defp gate(code, node, state) do
    with {:ok, truth} <- PredicateMachine.run(code, state.values, state.profile, state.limits) do
      if truth == true, do: visit(node, state), else: {:ok, []}
    end
  end

  defp visit(node, state) do
    record = state.records[node["path"]]

    if record["status"] in @stopped or record["started_ms"] == nil,
      do: {:ok, []},
      else: eligible(node, record, state)
  end

  defp eligible(%{"kind" => "effect", "path" => path}, %{"status" => status}, _)
       when status in ~w(proposed reserved), do: {:ok, [path]}

  defp eligible(%{"kind" => "sequence", "steps" => children}, _, state) do
    case Enum.find(children, &(state.records[&1["path"]]["status"] != "completed")) do
      nil -> {:ok, []}
      child -> visit(child, state)
    end
  end

  defp eligible(%{"kind" => "parallel"} = node, _, state) do
    node
    |> ExecutionTree.children()
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, paths} ->
      case visit(child, state) do
        {:ok, child_paths} -> {:cont, {:ok, paths ++ child_paths}}
        error -> {:halt, error}
      end
    end)
  end

  defp eligible(%{"kind" => "if"} = node, %{"branch" => branch}, state)
       when branch in ~w(then else), do: visit(node[branch], state)

  defp eligible(%{"kind" => "invoke"} = node, _, state),
    do: gate(node["condition"], node["body"], state)

  defp eligible(_, _, _), do: {:ok, []}
end
