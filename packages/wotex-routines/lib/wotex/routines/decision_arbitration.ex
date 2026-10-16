defmodule Wotex.Routines.DecisionArbitration do
  @moduledoc false

  alias Wotex.Routines.{Error, Limits, Profile, Validation}

  @signature ~w(installed_basis operation input thing_id resource_roles resource_domains completion evidence_contract)

  @doc false
  @spec verify(map(), map(), Profile.t(), Limits.t()) :: :ok | {:error, Error.t()}
  def verify(collection, context, profile, limits) do
    result = context["arbitration"]
    dispositions = context["dispositions"]
    batch = context["batch_limit"]
    proposals = collection["proposals"]

    with :ok <-
           Validation.fields(
             result,
             ~w(collection_digest dispositions batch_limit selected decisions)
           ),
         :ok <-
           equal(
             result["collection_digest"],
             collection["collection_digest"],
             "/arbitration/collection_digest"
           ),
         :ok <- equal(result["dispositions"], dispositions, "/arbitration/dispositions"),
         :ok <- equal(result["batch_limit"], batch, "/arbitration/batch_limit"),
         :ok <- dispositions(dispositions, proposals),
         :ok <- Validation.integer(batch, limits, "/batch_limit", 1),
         :ok <- batch_bound(batch, profile),
         :ok <- lists(result["selected"], result["decisions"]) do
      indexed = Enum.map(proposals, &{&1, Map.take(&1, @signature)})
      overrides = selected_overrides(indexed, dispositions)
      {eligible, outcomes} = eligibility(indexed, dispositions, overrides)
      groups = groups(eligible)
      domains = domain_index(Enum.map(groups, fn {key, [first | _]} -> {first, key} end))

      with {:ok, outcomes} <- selections(groups, domains, result["selected"], batch, outcomes) do
        decisions(proposals, result["decisions"], outcomes)
      end
    end
  end

  defp dispositions(data, proposals) do
    ids = Enum.map(proposals, & &1["step_original"])

    with :ok <- Validation.fields(data, ids) do
      Validation.each(Map.values(data), fn value ->
        with :ok <- Validation.fields(value, ~w(constraint override)),
             :ok <-
               Validation.choice(value["constraint"], ~w(allowed refused unknown), "/constraint") do
          Validation.choice(value["override"], ~w(none selected suppressed), "/override")
        end
      end)
    end
  end

  defp selected_overrides(indexed, dispositions) do
    indexed
    |> Enum.filter(fn {p, _} ->
      dispositions[p["step_original"]] == %{"constraint" => "allowed", "override" => "selected"}
    end)
    |> domain_index()
  end

  defp domain_index(indexed) do
    Enum.reduce(indexed, %{}, fn {proposal, signature}, domains ->
      Enum.reduce(proposal["resource_domains"], domains, fn domain, domains ->
        Map.update(domains, domain, MapSet.new([signature]), &MapSet.put(&1, signature))
      end)
    end)
  end

  defp eligibility(indexed, dispositions, overrides) do
    {eligible, outcomes} =
      Enum.reduce(indexed, {[], %{}}, fn {proposal, signature} = pair, {eligible, outcomes} ->
        id = proposal["step_original"]
        outcome = disposition_outcome(dispositions[id], proposal, signature, overrides)

        if outcome == nil,
          do: {[pair | eligible], outcomes},
          else: {eligible, Map.put(outcomes, id, outcome)}
      end)

    {Enum.reverse(eligible), outcomes}
  end

  defp disposition_outcome(%{"constraint" => "refused"}, _, _, _), do: "constraint-refused"
  defp disposition_outcome(%{"constraint" => "unknown"}, _, _, _), do: "constraint-unknown"
  defp disposition_outcome(%{"override" => "suppressed"}, _, _, _), do: "override-suppressed"
  defp disposition_outcome(%{"override" => "selected"}, _, _, _), do: nil

  defp disposition_outcome(_, proposal, signature, overrides) do
    if incompatible_domain?(proposal, signature, overrides), do: "override-suppressed"
  end

  defp incompatible_domain?(proposal, signature, domains) do
    Enum.any?(proposal["resource_domains"], fn domain ->
      keys = Map.get(domains, domain, MapSet.new())
      MapSet.size(keys) > if(MapSet.member?(keys, signature), do: 1, else: 0)
    end)
  end

  defp groups(indexed) do
    indexed
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {_, [first | _]} -> {first["program_digest"], first["path"]} end)
  end

  defp selections(groups, domains, selected, batch, outcomes) do
    Enum.reduce_while(groups, {:ok, selected, outcomes, 0}, fn {key, group},
                                                               {:ok, remaining, outcomes, count} ->
      cond do
        incompatible_domain?(hd(group), key, domains) ->
          {:cont, {:ok, remaining, mark(group, outcomes, "conflict"), count}}

        count >= batch ->
          {:cont, {:ok, remaining, mark(group, outcomes, "batch-deferred"), count}}

        true ->
          select_group(group, remaining, outcomes, count)
      end
    end)
    |> remaining_selection()
  end

  defp select_group(group, [claimed | rest], outcomes, count) do
    case equal(claimed, group, "/arbitration/selected") do
      :ok ->
        [first | others] = group
        outcomes = Map.put(outcomes, first["step_original"], "selected")
        {:cont, {:ok, rest, mark(others, outcomes, "coalesced"), count + 1}}

      error ->
        {:halt, error}
    end
  end

  defp select_group(_, _, _, _),
    do: {:halt, Error.refusal(:stale_decision_arbitration, "/arbitration/selected")}

  defp remaining_selection({:ok, [], outcomes, _}), do: {:ok, outcomes}

  defp remaining_selection({:ok, _, _, _}),
    do: Error.refusal(:stale_decision_arbitration, "/arbitration/selected")

  defp remaining_selection(error), do: error

  defp decisions(proposals, claimed, outcomes) do
    with :ok <- equal(length(claimed), length(proposals), "/arbitration/decisions") do
      Enum.zip(proposals, claimed)
      |> Validation.each(fn {proposal, decision} ->
        equal(
          decision,
          %{
            "step_original" => proposal["step_original"],
            "outcome" => outcomes[proposal["step_original"]]
          },
          "/arbitration/decisions"
        )
      end)
    end
  end

  defp mark(group, outcomes, value),
    do: Enum.reduce(group, outcomes, &Map.put(&2, &1["step_original"], value))

  defp batch_bound(value, profile) do
    if value <= profile.data["pending_work"], do: :ok, else: Error.refusal(:batch_bound)
  end

  defp lists(a, b) when is_list(a) and is_list(b), do: :ok
  defp lists(_, _), do: Error.refusal(:invalid_type, "/arbitration")
  defp equal(value, value, _), do: :ok
  defp equal(_, _, path), do: Error.refusal(:stale_decision_arbitration, path)
end
