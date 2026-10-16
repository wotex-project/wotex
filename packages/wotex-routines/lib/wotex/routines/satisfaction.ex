defmodule Wotex.Routines.Satisfaction do
  @moduledoc false

  alias Wotex.Routines.{Error, ExecutionTree, Limits, Pending, Profile, Validation}

  @empty ~w(handoff local_queue protocol_response correlated_report reported_match terminal)

  @doc false
  @spec classify(map(), map(), Limits.t()) ::
          {:ok, :duplicate | :fresh} | {:error, Error.t()}
  def classify(run, event, limits) do
    record = Enum.find(run["steps"], &(&1["path"] == event["path"]))

    with true <- is_map(record),
         {:ok, receipt} <- receipt(event, limits) do
      case record["receipts"]["satisfied"] do
        ^receipt -> {:ok, :duplicate}
        nil -> {:ok, :fresh}
        _ -> Error.refusal(:conflicting_receipt)
      end
    else
      false -> Error.refusal(:invalid_receipt_path)
      error -> error
    end
  end

  @doc false
  @spec apply(map(), map(), map(), map(), map(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def apply(run, event, program, snapshot, values, profile, limits) do
    record = Enum.find(run["steps"], &(&1["path"] == event["path"]))
    node = Enum.find(ExecutionTree.nodes(program["ir"]["steps"]), &(&1["path"] == event["path"]))

    with :ok <- eligible_kind(node, program),
         :ok <- order(record),
         :ok <- contract(event, node),
         {:ok, paths} <- Pending.paths(program, run, values, profile, limits),
         true <- event["path"] in paths and matches?(event, node, snapshot, values),
         {:ok, receipt} <- receipt(event, limits) do
      run = promote(run)

      steps =
        Enum.map(run["steps"], fn old ->
          if old["path"] == event["path"] do
            old
            |> Map.put("status", "completed")
            |> put_in(["receipts", "satisfied"], receipt)
          else
            old
          end
        end)

      {:ok, %{run | "steps" => steps}}
    else
      false -> Error.refusal(:invalid_satisfaction)
      error -> error
    end
  end

  defp eligible_kind(%{"kind" => "effect", "completion" => "reported_match"} = node, program) do
    affordance = ExecutionTree.basis(program, node)["affordance"]

    if Map.take(affordance, ~w(type operation)) ==
         %{"type" => "property", "operation" => "writeproperty"},
       do: :ok,
       else: Error.refusal(:invalid_satisfaction)
  end

  defp eligible_kind(_, _), do: Error.refusal(:invalid_satisfaction)

  defp order(record) do
    if record["status"] in ~w(proposed reserved) and
         Enum.all?(@empty, &(record["receipts"][&1] == nil)),
       do: :ok,
       else: Error.refusal(:out_of_order_receipt)
  end

  defp contract(event, node) do
    if event["report_contract"] == node["evidence_contract"],
      do: :ok,
      else: Error.refusal(:stale_report_contract)
  end

  defp matches?(event, node, snapshot, values) do
    fact = snapshot["facts"][node["binding"]]

    is_map(fact) and fact["id"] == event["fact_id"] and
      Map.get(values, node["binding"]) === {:known, node["input"]}
  end

  defp receipt(event, limits) do
    with {:ok, digest} <- Validation.hash(event, limits),
         do: {:ok, %{"ref" => event["ref"], "digest" => digest, "outcome" => "matched"}}
  end

  defp promote(%{"format" => "wotex.routines.run@1"} = run) do
    steps = Enum.map(run["steps"], &put_in(&1, ["receipts", "satisfied"], nil))

    Map.merge(run, %{
      "format" => "wotex.routines.run@2",
      "time_format" => "wotex.routines.time@1",
      "steps" => steps
    })
  end

  defp promote(run), do: run
end
