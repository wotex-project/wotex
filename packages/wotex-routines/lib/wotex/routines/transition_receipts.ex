defmodule Wotex.Routines.TransitionReceipts do
  @moduledoc false

  alias Wotex.Routines.{ExecutionTree, Limits, TransitionChecks, Validation}

  @stages ~w(local_queue protocol_response correlated_report reported_match)
  @slots ~w(admission handoff local_queue protocol_response correlated_report reported_match terminal)

  # Receipt conclusions are checked separately from execution statuses. The
  # returned status premises describe the input to the tree relation, never an
  # alternate Run or a repaired transition.
  @doc false
  @spec verify(map(), map() | nil, map(), map(), atom(), Limits.t()) ::
          {:ok, map()} | {:error, Wotex.Routines.Error.t()}
  def verify(program, before, after_run, event, satisfaction, limits) do
    old = if before, do: Map.new(before["steps"], &{&1["path"], &1}), else: %{}
    nodes = Map.new(ExecutionTree.nodes(program["ir"]["steps"]), &{&1["path"], &1})

    with {:ok, delta} <- delta(event, old, nodes, satisfaction, limits),
         {:ok, statuses} <- records(after_run, old, delta),
         :ok <- spending(after_run) do
      {:ok, statuses}
    end
  end

  @doc false
  @spec satisfaction(map(), map(), Limits.t()) ::
          {:ok, :fresh | :duplicate} | {:error, Wotex.Routines.Error.t()}
  def satisfaction(before, event, limits) do
    record = Enum.find(before["steps"], &(&1["path"] == event["path"]))

    with :ok <- TransitionChecks.condition(is_map(record), "/event/path"),
         {:ok, receipt} <- fingerprint(event, limits) do
      case record["receipts"]["satisfied"] do
        nil -> {:ok, :fresh}
        ^receipt -> {:ok, :duplicate}
        _ -> TransitionChecks.refuse("/event/ref")
      end
    end
  end

  defp delta(%{"kind" => kind} = event, old, nodes, _, limits)
       when kind in ~w(admission handoff result) do
    record = old[event["path"]]
    node = nodes[event["path"]]

    with :ok <-
           TransitionChecks.condition(is_map(record) and record["kind"] == "effect", "/event/path"),
         {:ok, receipt} <- fingerprint(event, limits) do
      slot = slot(event)

      case record["receipts"][slot] do
        ^receipt -> {:ok, nil}
        nil -> fresh(record, node, event, slot, receipt)
        _ -> TransitionChecks.refuse("/event/ref")
      end
    end
  end

  defp delta(%{"kind" => "satisfied"} = event, old, _, :apply, limits) do
    record = old[event["path"]]

    with :ok <- TransitionChecks.condition(record["status"] in ~w(proposed reserved), "/event/path"),
         :ok <-
           TransitionChecks.condition(
             Enum.all?(
               ~w(handoff local_queue protocol_response correlated_report reported_match terminal),
               &(record["receipts"][&1] == nil)
             ),
             "/run/steps/receipts"
           ),
         {:ok, receipt} <- fingerprint(event, limits) do
      {:ok,
       %{
         path: event["path"],
         slot: "satisfied",
         receipt: receipt,
         status: "completed",
         terminal: false
       }}
    end
  end

  defp delta(_, _, _, _, _), do: {:ok, nil}

  defp fresh(record, _, %{"kind" => "admission"}, slot, receipt) do
    with :ok <- TransitionChecks.equal(record["status"], "proposed", "/event/path"),
         do:
           change(
             record,
             slot,
             receipt,
             if(receipt["outcome"] == "held", do: "reserved", else: "refused")
           )
  end

  defp fresh(record, _, %{"kind" => "handoff"}, slot, receipt) do
    with :ok <- TransitionChecks.equal(record["status"], "reserved", "/event/path"),
         do: change(record, slot, receipt, "handed_off")
  end

  defp fresh(record, node, event, slot, receipt) do
    receipts = record["receipts"]
    later = Enum.drop(@stages, Enum.find_index(@stages, &(&1 == slot)) + 1)

    contract =
      event["stage"] not in ~w(correlated_report reported_match) or
        event["report_contract"] == node["evidence_contract"]

    with :ok <- TransitionChecks.condition(record["status"] != "completed", "/event/path"),
         :ok <-
           TransitionChecks.condition(
             receipts["handoff"] != nil and receipts["terminal"] == nil,
             "/event/path"
           ),
         :ok <- TransitionChecks.condition(contract, "/event/report_contract"),
         :ok <- TransitionChecks.condition(Enum.all?(later, &(receipts[&1] == nil)), "/event/stage") do
      status =
        cond do
          event["outcome"] in ~w(failed unknown) -> event["outcome"]
          rank(slot) >= rank(node["completion"]) -> "completed"
          true -> record["status"]
        end

      change(record, slot, receipt, status)
    end
  end

  defp change(record, slot, receipt, status),
    do:
      {:ok,
       %{
         path: record["path"],
         slot: slot,
         receipt: receipt,
         status: status,
         terminal: slot in @stages and status in ~w(failed unknown)
       }}

  defp records(after_run, old, delta) do
    Enum.reduce_while(after_run["steps"], {:ok, %{}}, fn record, {:ok, statuses} ->
      previous = old[record["path"]]
      receipts = if previous, do: previous["receipts"], else: Map.new(@slots, &{&1, nil})

      receipts =
        if after_run["format"] == "wotex.routines.run@2",
          do: Map.put_new(receipts, "satisfied", nil),
          else: receipts

      status = if previous, do: previous["status"], else: "unsent"
      {receipts, status} = target(receipts, status, record["path"], delta)

      case TransitionChecks.equal(record["receipts"], receipts, "/run/steps/receipts") do
        :ok -> {:cont, {:ok, Map.put(statuses, record["path"], status)}}
        error -> {:halt, error}
      end
    end)
  end

  defp target(receipts, _, path, %{path: path} = delta) do
    receipts = Map.put(receipts, delta.slot, delta.receipt)
    receipts = if delta.terminal, do: Map.put(receipts, "terminal", delta.receipt), else: receipts
    {receipts, delta.status}
  end

  defp target(receipts, status, _, _), do: {receipts, status}

  defp spending(run) do
    held =
      Enum.flat_map(run["steps"], fn record ->
        case record["receipts"]["admission"] do
          %{"outcome" => "held", "ref" => ref} ->
            [%{"original" => record["original"], "ref" => ref}]

          _ ->
            []
        end
      end)

    TransitionChecks.equal(run["spent"], held, "/run/spent")
  end

  defp fingerprint(event, limits) do
    outcome =
      case event["kind"] do
        "handoff" -> "marked"
        "satisfied" -> "matched"
        _ -> event["outcome"]
      end

    with {:ok, digest} <- Validation.hash(event, limits),
         do: {:ok, %{"ref" => event["ref"], "digest" => digest, "outcome" => outcome}}
  end

  defp slot(%{"kind" => "admission"}), do: "admission"
  defp slot(%{"kind" => "handoff"}), do: "handoff"
  defp slot(event), do: event["stage"]
  defp rank(stage), do: Enum.find_index(@stages, &(&1 == stage))
end
