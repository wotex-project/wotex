defmodule Wotex.Routines.ExecutionTree do
  @moduledoc false

  alias Wotex.Routines.{Limits, Validation}

  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)

  @spec nodes(map()) :: [map()]
  def nodes(node), do: [node | Enum.flat_map(children(node), &nodes/1)]

  @spec children(map()) :: [map()]
  def children(%{"kind" => "sequence", "steps" => children}), do: children
  def children(%{"kind" => "parallel", "branches" => children}), do: children
  def children(%{"kind" => "if", "then" => yes, "else" => no}), do: [yes, no]
  def children(%{"kind" => "invoke", "body" => body}), do: [body]
  def children(_), do: []

  @spec basis(map(), map()) :: map() | nil
  def basis(program, %{"kind" => "effect", "binding" => name}) do
    ref = program["context"]["bindings"][name]["basis"]
    Enum.find(program["context"]["bases"], &(Map.take(&1, ~w(id version semantic_digest)) == ref))
  end

  def basis(_, _), do: nil

  @spec identity(map(), String.t(), [non_neg_integer()], Limits.t()) ::
          {:ok, String.t()} | {:error, Wotex.Routines.Error.t()}
  def identity(program, original, path, limits) do
    Validation.hash(
      %{"program_digest" => program["ir_digest"], "original" => original, "path" => path},
      limits
    )
  end

  @spec records(map(), String.t(), Limits.t()) ::
          {:ok, [map()]} | {:error, Wotex.Routines.Error.t()}
  def records(program, original, limits) do
    program["ir"]["steps"]
    |> nodes()
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, records} ->
      case identity(program, original, node["path"], limits) do
        {:ok, identity} ->
          record = %{
            "path" => node["path"],
            "original" => identity,
            "kind" => node["kind"],
            "status" => "unsent",
            "started_ms" => nil,
            "deadline_ms" => nil,
            "branch" => nil,
            "receipts" => Map.new(@slots, &{&1, nil})
          }

          {:cont, {:ok, [record | records]}}

        error ->
          {:halt, error}
      end
    end)
    |> ordered()
  end

  defp ordered({:ok, records}), do: {:ok, Enum.reverse(records)}
  defp ordered(error), do: error
end
