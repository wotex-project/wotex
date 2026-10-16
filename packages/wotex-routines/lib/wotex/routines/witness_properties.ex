defmodule Wotex.Routines.WitnessProperties do
  @moduledoc false

  @stopped ~w(completed refused failed unknown cancelled expired partial)
  @ranks %{
    "local_queue" => 0,
    "protocol_response" => 1,
    "correlated_report" => 2,
    "reported_match" => 3
  }

  @doc false
  @spec started([map()]) :: MapSet.t()
  def started(runs) do
    runs
    |> Enum.flat_map(& &1["steps"])
    |> Enum.filter(&(&1["kind"] == "effect" and &1["started_ms"] != nil))
    |> MapSet.new(& &1["original"])
  end

  @doc false
  @spec violated?(String.t(), map() | nil, map(), map(), MapSet.t()) :: boolean()
  def violated?("proposal_once", _, transition, _, seen) do
    originals = Enum.map(transition["proposals"], & &1["step_original"])

    Enum.any?(originals, &MapSet.member?(seen, &1)) or
      length(originals) != length(Enum.uniq(originals))
  end

  def violated?("held_spend_retained", nil, _, _, _), do: false

  def violated?("held_spend_retained", previous, transition, _, _) do
    current = if transition["run"], do: transition["run"]["spent"], else: []
    Enum.any?(previous["spent"], &(&1 not in current))
  end

  def violated?("stopped_continuation", nil, _, _, _), do: false

  def violated?("stopped_continuation", previous, transition, _, _),
    do: previous["status"] in @stopped and transition["proposals"] != []

  def violated?("completion_evidence", _, %{"run" => nil}, _, _), do: false

  def violated?("completion_evidence", _, transition, program, _) do
    thresholds = thresholds(program["ir"]["steps"])

    Enum.any?(transition["run"]["steps"], fn record ->
      record["kind"] == "effect" and record["status"] == "completed" and
        missing_evidence?(record, Map.fetch!(thresholds, record["path"]))
    end)
  end

  defp missing_evidence?(record, threshold) do
    not satisfied?(record, threshold) and missing_staged_evidence?(record, threshold)
  end

  defp satisfied?(record, "reported_match") do
    match?(%{"outcome" => "matched"}, record["receipts"]["satisfied"]) and
      record["receipts"]["handoff"] == nil and
      Enum.all?(@ranks, fn {stage, _} -> record["receipts"][stage] == nil end)
  end

  defp satisfied?(_, _), do: false

  defp missing_staged_evidence?(record, threshold) do
    record["receipts"]["handoff"] == nil or
      not Enum.any?(@ranks, fn {stage, rank} ->
        rank >= @ranks[threshold] and
          match?(%{"outcome" => "accepted"}, record["receipts"][stage])
      end)
  end

  defp thresholds(%{"kind" => "effect"} = node), do: %{node["path"] => node["completion"]}

  defp thresholds(node) do
    node
    |> children()
    |> Enum.reduce(%{}, &Map.merge(&2, thresholds(&1)))
  end

  defp children(%{"kind" => "sequence", "steps" => children}), do: children
  defp children(%{"kind" => "parallel", "branches" => children}), do: children
  defp children(%{"kind" => "if", "then" => yes, "else" => no}), do: [yes, no]
  defp children(%{"kind" => "invoke", "body" => body}), do: [body]
  defp children(_), do: []
end
