defmodule Wotex.Routines.Arbitration do
  @moduledoc """
  Resolves whole-set constraints, equivalence and resource conflicts before batching.

  `Wotex.Routines.Arbitration.decide/5` takes a complete v1 or v2
  `Wotex.Routines.Collection`, explicit dispositions, a positive batch limit,
  `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. It first regenerates
  the collection through `Wotex.Routines.Collection.to_map/3`. Success returns
  `{:ok, result}`; malformed inputs, stale correspondence and exceeded bounds
  return `{:error, error}` with a `Wotex.Routines.Error`.

  Dispositions have exactly one member per proposal's `"step_original"`.
  Each value contains `"constraint"` selected from `"allowed"`, `"refused"`
  or `"unknown"`, and `"override"` selected from `"none"`, `"selected"` or
  `"suppressed"`. All proposals undergo those checks before equivalent
  proposals are grouped and every eligible group's resource domains are
  compared. A conflict beyond the eventual batch cutoff still affects the
  decision. Only then is the batch limit applied to nonconflicting groups;
  the limit counts groups, must not exceed the Profile's `"pending_work"`
  selection, and cannot replace the collection's full proposal bound.

  The result has exactly `"collection_digest"`, `"dispositions"`,
  `"batch_limit"`, `"selected"` and `"decisions"`. Selected entries are groups
  containing every eligible equivalent original contributor, including
  reserved contributors from Collection@2. Decisions retain one outcome per
  original: `"selected"`, `"coalesced"`, `"conflict"`, `"constraint-refused"`,
  `"constraint-unknown"`, `"override-suppressed"` or `"batch-deferred"`.
  The complete result must fit the supplied JSON limits.

  Retain the complete regenerated collection separately: its digest binds the
  input, transitions, proposals and v2 proposal states, while this result stores
  only that digest. Join by `"step_original"` to reconcile proposed versus
  already reserved contributors. A deferred proposal remains retained and may
  participate in a later complete cut without a new original or trigger.

  Selection is inert. The consumer owns actual membership, current authority,
  durable charges, held resource claims and physical handoff. Reconcile those
  atomically before acting; a selected reserved contributor grants no repeated
  admission charge or handoff. This module performs no I/O, admission,
  persistence or dispatch.
  """

  alias Wotex.Routines.{Collection, Error, Limits, Profile, Validation}

  @equivalence ~w(installed_basis operation input thing_id resource_roles resource_domains completion evidence_contract)

  @doc "Regenerates the supplied collection, resolves every domain conflict, then applies the batch limit."
  @spec decide(term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def decide(collection, dispositions, batch_limit, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, collection} <- Collection.to_map(collection, profile, limits),
         {:ok, dispositions, _} <- Validation.admit(dispositions, limits, nil),
         :ok <- dispositions(dispositions, collection["proposals"]),
         :ok <- batch(batch_limit, profile, limits) do
      proposals = collection["proposals"]
      {eligible, outcomes} = constraints(proposals, dispositions)
      {eligible, outcomes} = overrides(eligible, dispositions, outcomes)
      groups = groups(eligible)
      conflicts = conflicts(groups)
      {selected, outcomes} = select(groups, conflicts, batch_limit, outcomes)

      decisions =
        Enum.map(
          proposals,
          &%{"step_original" => &1["step_original"], "outcome" => outcomes[&1["step_original"]]}
        )

      result = %{
        "collection_digest" => collection["collection_digest"],
        "dispositions" => dispositions,
        "batch_limit" => batch_limit,
        "selected" => selected,
        "decisions" => decisions
      }

      with :ok <- Validation.bounded(result, limits), do: {:ok, result}
    end
  end

  defp dispositions(data, proposals) do
    ids = Enum.map(proposals, & &1["step_original"])

    with :ok <- Validation.fields(data, ids) do
      Validation.each(Map.values(data), fn disposition ->
        with :ok <- Validation.fields(disposition, ~w(constraint override)),
             :ok <-
               Validation.choice(
                 disposition["constraint"],
                 ~w(allowed refused unknown),
                 "/constraint"
               ) do
          Validation.choice(disposition["override"], ~w(none selected suppressed), "/override")
        end
      end)
    end
  end

  defp batch(value, profile, limits) do
    with :ok <- Validation.integer(value, limits, "/batch_limit", 1) do
      if value <= profile.data["pending_work"], do: :ok, else: Error.refusal(:batch_bound)
    end
  end

  defp constraints(proposals, dispositions) do
    Enum.reduce(proposals, {[], %{}}, fn proposal, {eligible, outcomes} ->
      id = proposal["step_original"]

      case dispositions[id]["constraint"] do
        "allowed" -> {[proposal | eligible], outcomes}
        "refused" -> {eligible, Map.put(outcomes, id, "constraint-refused")}
        "unknown" -> {eligible, Map.put(outcomes, id, "constraint-unknown")}
      end
    end)
    |> ordered()
  end

  defp overrides(proposals, dispositions, outcomes) do
    selected =
      Enum.filter(proposals, fn proposal ->
        disposition = dispositions[proposal["step_original"]]
        disposition["override"] == "selected"
      end)

    Enum.reduce(proposals, {[], outcomes}, fn proposal, {eligible, outcomes} ->
      id = proposal["step_original"]
      suppressed = suppressed?(proposal, dispositions[id], selected)

      if suppressed,
        do: {eligible, Map.put(outcomes, id, "override-suppressed")},
        else: {[proposal | eligible], outcomes}
    end)
    |> ordered()
  end

  defp suppressed?(_, %{"override" => "suppressed"}, _), do: true
  defp suppressed?(_, %{"override" => "selected"}, _), do: false
  defp suppressed?(proposal, _, selected), do: Enum.any?(selected, &incompatible?(proposal, &1))
  defp ordered({proposals, outcomes}), do: {Enum.reverse(proposals), outcomes}

  defp groups(proposals) do
    {order, grouped} =
      Enum.reduce(proposals, {[], %{}}, fn proposal, {order, grouped} ->
        key = Map.take(proposal, @equivalence)

        if Map.has_key?(grouped, key),
          do: {order, Map.update!(grouped, key, &[proposal | &1])},
          else: {[key | order], Map.put(grouped, key, [proposal])}
      end)

    order
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse(grouped[&1]))
  end

  defp incompatible?(left, right) do
    Map.take(left, @equivalence) != Map.take(right, @equivalence) and
      Enum.any?(left["resource_domains"], &(&1 in right["resource_domains"]))
  end

  defp conflicts(groups) do
    groups
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {group, index}, conflicts ->
      groups
      |> Enum.drop(index + 1)
      |> Enum.with_index(index + 1)
      |> Enum.reduce(conflicts, fn {other, other_index}, conflicts ->
        if incompatible?(hd(group), hd(other)),
          do: put_conflict(conflicts, index, other_index),
          else: conflicts
      end)
    end)
  end

  defp put_conflict(conflicts, index, other_index) do
    conflicts
    |> MapSet.put(index)
    |> MapSet.put(other_index)
  end

  defp select(groups, conflicts, batch_limit, outcomes) do
    {selected, outcomes, _} =
      groups
      |> Enum.with_index()
      |> Enum.reduce({[], outcomes, 0}, fn {group, index}, {selected, outcomes, count} ->
        cond do
          MapSet.member?(conflicts, index) ->
            {selected, mark(group, outcomes, "conflict"), count}

          count >= batch_limit ->
            {selected, mark(group, outcomes, "batch-deferred"), count}

          true ->
            [first | rest] = group
            outcomes = Map.put(outcomes, first["step_original"], "selected")
            outcomes = mark(rest, outcomes, "coalesced")
            {[group | selected], outcomes, count + 1}
        end
      end)

    {Enum.reverse(selected), outcomes}
  end

  defp mark(proposals, outcomes, outcome),
    do: Enum.reduce(proposals, outcomes, &Map.put(&2, &1["step_original"], outcome))
end
