defmodule Wotex.Routines.Receipt do
  @moduledoc false

  alias Wotex.Routines.{Error, ExecutionTree, Limits, Validation}

  @stages ~w(local_queue protocol_response correlated_report reported_match)

  @doc false
  @spec apply(map(), map(), map(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def apply(run, %{"kind" => kind} = event, program, limits)
      when kind in ~w(admission handoff result) do
    path = event["path"]
    record = Enum.find(run["steps"], &(&1["path"] == path))
    node = Enum.find(ExecutionTree.nodes(program["ir"]["steps"]), &(&1["path"] == path))

    with true <- is_map(record) and record["kind"] == "effect",
         {:ok, digest} <- Validation.hash(event, limits),
         {:ok, changed} <- update(record, node, event, digest) do
      steps = Enum.map(run["steps"], fn old -> if old["path"] == path, do: changed, else: old end)
      {:ok, %{run | "steps" => steps, "spent" => spending(steps)}}
    else
      false -> Error.refusal(:invalid_receipt_path)
      error -> error
    end
  end

  def apply(run, _, _, _), do: {:ok, run}

  defp update(record, node, event, digest) do
    slot = slot(event)
    receipt = %{"ref" => event["ref"], "digest" => digest, "outcome" => outcome(event)}

    case record["receipts"][slot] do
      ^receipt -> {:ok, record}
      nil -> fresh(record, node, event, slot, receipt)
      _ -> Error.refusal(:conflicting_receipt)
    end
  end

  defp slot(%{"kind" => "admission"}), do: "admission"
  defp slot(%{"kind" => "handoff"}), do: "handoff"
  defp slot(%{"stage" => stage}), do: stage
  defp outcome(%{"kind" => "handoff"}), do: "marked"
  defp outcome(event), do: event["outcome"]

  defp fresh(%{"status" => "proposed"} = record, _, %{"kind" => "admission"}, slot, receipt) do
    status = if receipt["outcome"] == "held", do: "reserved", else: "refused"
    {:ok, put_receipt(record, slot, receipt, status)}
  end

  defp fresh(%{"status" => "reserved"} = record, _, %{"kind" => "handoff"}, slot, receipt),
    do: {:ok, put_receipt(record, slot, receipt, "handed_off")}

  defp fresh(%{"status" => "completed"}, _, _, _, _),
    do: Error.refusal(:out_of_order_receipt)

  defp fresh(record, node, %{"kind" => "result"} = event, slot, receipt) do
    receipts = record["receipts"]

    with true <- receipts["handoff"] != nil and receipts["terminal"] == nil,
         :ok <- report_contract(event, node),
         :ok <- stage_order(receipts, slot) do
      status = result_status(event, node, record)
      changed = put_receipt(record, slot, receipt, status)

      changed =
        if status in ~w(failed unknown),
          do: put_in(changed, ["receipts", "terminal"], receipt),
          else: changed

      {:ok, changed}
    else
      false -> Error.refusal(:out_of_order_receipt)
      error -> error
    end
  end

  defp fresh(_, _, _, _, _), do: Error.refusal(:out_of_order_receipt)

  defp report_contract(%{"stage" => stage, "report_contract" => ref}, node)
       when stage in ~w(correlated_report reported_match) do
    if ref == node["evidence_contract"], do: :ok, else: Error.refusal(:stale_report_contract)
  end

  defp report_contract(_, _), do: :ok

  defp stage_order(receipts, slot) do
    rank = Enum.find_index(@stages, &(&1 == slot))
    later = Enum.drop(@stages, rank + 1)
    if Enum.any?(later, &(receipts[&1] != nil)), do: Error.refusal(:out_of_order_receipt), else: :ok
  end

  defp result_status(%{"outcome" => outcome}, _, _) when outcome in ~w(failed unknown), do: outcome

  defp result_status(event, node, record) do
    rank = Enum.find_index(@stages, &(&1 == event["stage"]))
    threshold = Enum.find_index(@stages, &(&1 == node["completion"]))
    if rank >= threshold, do: "completed", else: record["status"]
  end

  defp put_receipt(record, slot, receipt, status) do
    record
    |> Map.put("status", status)
    |> put_in(["receipts", slot], receipt)
  end

  defp spending(steps) do
    Enum.flat_map(steps, fn record ->
      case record["receipts"]["admission"] do
        %{"outcome" => "held", "ref" => ref} -> [%{"original" => record["original"], "ref" => ref}]
        _ -> []
      end
    end)
  end
end
