defmodule Wotex.Routines.Test.DecisionReference do
  @moduledoc false

  # A deliberately all-pairs oracle over raw proposals. No production checker,
  # grouping, qualification, pending traversal or arbitration helper is used.
  @spec decide(map(), map(), pos_integer()) :: map()
  def decide(collection, dispositions, batch) do
    proposals = collection["proposals"]
    labelled = label(proposals, dispositions)
    eligible = for {p, nil} <- labelled, do: p
    groups = group(eligible)
    {chosen, group_outcomes} = classify(groups, batch)

    outcomes =
      Enum.reduce(labelled, group_outcomes, fn {p, outcome}, acc ->
        if outcome, do: Map.put(acc, p["step_original"], outcome), else: acc
      end)

    %{
      "collection_digest" => collection["collection_digest"],
      "dispositions" => dispositions,
      "batch_limit" => batch,
      "selected" => chosen,
      "decisions" =>
        Enum.map(
          proposals,
          &%{"step_original" => &1["step_original"], "outcome" => outcomes[&1["step_original"]]}
        )
    }
  end

  defp label(proposals, dispositions) do
    selected =
      Enum.filter(
        proposals,
        &(dispositions[&1["step_original"]] ==
            %{"constraint" => "allowed", "override" => "selected"})
      )

    Enum.map(proposals, fn p ->
      d = dispositions[p["step_original"]]

      outcome =
        cond do
          d["constraint"] == "refused" ->
            "constraint-refused"

          d["constraint"] == "unknown" ->
            "constraint-unknown"

          d["override"] == "suppressed" ->
            "override-suppressed"

          d["override"] != "selected" and Enum.any?(selected, &incompatible?(p, &1)) ->
            "override-suppressed"

          true ->
            nil
        end

      {p, outcome}
    end)
  end

  defp group(eligible) do
    eligible
    |> Enum.reduce([], fn p, groups ->
      case Enum.find_index(groups, &(signature(hd(&1)) === signature(p))) do
        nil -> [[p] | groups]
        index -> List.update_at(groups, index, &[p | &1])
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  defp classify(groups, batch) do
    {chosen, outcomes, _} =
      Enum.reduce(groups, {[], %{}, 0}, fn group, {chosen, outcomes, count} ->
        conflict = Enum.any?(groups, &incompatible?(hd(group), hd(&1)))

        {label, next} =
          cond do
            conflict -> {"conflict", count}
            count >= batch -> {"batch-deferred", count}
            true -> {"selected", count + 1}
          end

        outcomes = label_group(group, outcomes, label)
        {if(label == "selected", do: [group | chosen], else: chosen), outcomes, next}
      end)

    {Enum.reverse(chosen), outcomes}
  end

  defp label_group(group, outcomes, label) do
    group
    |> Enum.with_index()
    |> Enum.reduce(outcomes, fn {p, i}, acc ->
      value = if label == "selected" and i > 0, do: "coalesced", else: label
      Map.put(acc, p["step_original"], value)
    end)
  end

  defp signature(p),
    do:
      {p["installed_basis"], p["operation"], p["input"], p["thing_id"], p["resource_roles"],
       p["resource_domains"], p["completion"], p["evidence_contract"]}

  defp incompatible?(a, b),
    do:
      signature(a) !== signature(b) and
        Enum.any?(a["resource_domains"], fn left ->
          Enum.any?(b["resource_domains"], &(&1 === left))
        end)
end
