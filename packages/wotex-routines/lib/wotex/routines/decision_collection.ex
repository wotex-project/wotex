defmodule Wotex.Routines.DecisionCollection do
  @moduledoc false

  alias Wotex.Routines.{
    Collection,
    Compiler,
    DecisionPending,
    Error,
    Event,
    ExecutionPrior,
    Limits,
    Profile,
    Snapshot,
    Time,
    Transition,
    Validation
  }

  @fields ~w(format input profile json_limits transitions proposals proposal_states collection_digest)
  @input ~w(format membership entries time)

  @doc false
  @spec admit(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def admit(value, limits) do
    with {:ok, data, _} <- Validation.admit(value, limits, Collection),
         :ok <- scope(data, "wotex.routines.collection@2"),
         :ok <- Validation.fields(data, @fields) do
      {:ok, data}
    end
  end

  @doc false
  @spec verify(term(), map(), Profile.t(), Limits.t()) :: :ok | {:error, Error.t()}
  def verify(expected, data, profile, limits) do
    with {:ok, input, _} <- Validation.admit(expected, limits, nil),
         :ok <- scope(input, "wotex.routines.collection-input@2"),
         :ok <- Validation.fields(input, @input),
         :ok <- equal(data["input"], input, "/input"),
         :ok <- equal(data["profile"], profile.data, "/profile"),
         :ok <- equal(data["json_limits"], limits.data, "/json_limits"),
         :ok <- membership(input["membership"], profile),
         {:ok, time} <- Time.to_map(input["time"], limits),
         {:ok, entries} <- entries(input["entries"], profile, limits),
         :ok <- complete(entries, input["membership"]),
         :ok <- coherent(entries),
         :ok <- points(entries, data["transitions"], time, profile, limits),
         :ok <- active(entries, data["transitions"], profile),
         :ok <- pending(entries, data, time, profile, limits),
         {:ok, digest} <- Validation.hash(Map.delete(data, "collection_digest"), limits) do
      equal(data["collection_digest"], digest, "/collection_digest")
    end
  end

  defp scope(%{"format" => format}, format), do: :ok
  defp scope(_, _), do: Error.refusal(:unsupported_decision_scope, "/format")

  defp membership(data, profile) do
    with :ok <- Validation.fields(data, ~w(generation programs)),
         :ok <- Validation.text(data["generation"], "/membership/generation"),
         :ok <- Validation.strings(data["programs"], "/membership/programs"),
         :ok <- Validation.each(data["programs"], &Validation.digest(&1, "/membership/programs")) do
      bound(length(data["programs"]), profile.data["active_definitions"], :definition_bound)
    end
  end

  defp entries(list, profile, limits) when is_list(list) do
    with :ok <- bound(length(list), profile.data["active_definitions"], :definition_bound) do
      Enum.reduce_while(list, {:ok, []}, fn raw, {:ok, checked} ->
        case entry(raw, profile, limits) do
          {:ok, item} -> {:cont, {:ok, [item | checked]}}
          error -> {:halt, error}
        end
      end)
      |> sort_entries()
    end
  end

  defp entries(_, _, _), do: Error.refusal(:invalid_type, "/entries")

  defp sort_entries({:ok, entries}),
    do: {:ok, Enum.sort_by(entries, & &1["program"]["ir_digest"])}

  defp sort_entries(error), do: error

  defp entry(raw, profile, limits) do
    with :ok <- Validation.fields(raw, ~w(program event snapshot prior)),
         {:ok, program} <- Compiler.to_map(raw["program"], profile, limits),
         {:ok, snapshot} <- Snapshot.to_map(raw["snapshot"], program, profile, limits),
         {:ok, prior} <- ExecutionPrior.new(raw["prior"], program, profile, limits),
         {:ok, event} <- event(raw["event"], limits),
         :ok <- continuation(prior, event) do
      {:ok, %{"program" => program, "snapshot" => snapshot, "prior" => prior, "event" => event}}
    end
  end

  defp event(nil, _), do: {:ok, nil}
  defp event(raw, limits), do: Event.to_map(raw, limits)

  defp continuation(prior, event) do
    original = prior["original"]
    busy = prior["busy"]
    missing = live?(original) and (event == nil or event["original"] != original["original"])
    displaced = live?(busy) and (busy != original or event == nil)

    if missing or displaced,
      do: Error.refusal(:incomplete_run_continuation),
      else: :ok
  end

  defp live?(nil), do: false
  defp live?(run), do: run["status"] in ~w(running blocked)

  defp complete(entries, membership) do
    ids = Enum.map(entries, & &1["program"]["ir_digest"])

    with :ok <- equal(ids, Enum.sort(membership["programs"]), "/membership/programs") do
      Validation.each(entries, fn entry ->
        snapshot = entry["snapshot"]

        with :ok <- equal(snapshot["active_programs"], membership["programs"], "/membership"),
             do: equal(snapshot["membership_generation"], membership["generation"], "/membership")
      end)
    end
  end

  defp coherent(entries) do
    pairs =
      Enum.flat_map(entries, fn entry ->
        snapshot = entry["snapshot"]

        resources =
          Enum.map(snapshot["resource_revisions"], fn {id, rev} -> {{:resource, id}, rev} end)

        [{:snapshot_id, snapshot["id"]} | resources] ++ observations(entry)
      end)

    Enum.reduce_while(pairs, %{}, fn {key, value}, seen ->
      if Map.has_key?(seen, key) and seen[key] !== value,
        do: {:halt, Error.refusal(:incoherent_collection_snapshot)},
        else: {:cont, Map.put(seen, key, value)}
    end)
    |> coherence_result()
  end

  defp observations(entry) do
    bases = Map.new(entry["program"]["context"]["bases"], &{&1["id"], &1})

    Enum.map(entry["program"]["context"]["bindings"], fn {name, binding} ->
      affordance = bases[binding["basis"]["id"]]["affordance"]
      key = {binding["thing_id"], affordance["type"], affordance["name"], affordance["operation"]}

      value =
        {binding["basis"], entry["snapshot"]["binding_bases"][name],
         entry["snapshot"]["facts"][name]}

      {{:observation, key}, value}
    end)
  end

  defp coherence_result({:error, _} = error), do: error
  defp coherence_result(_), do: :ok

  defp points(entries, transitions, time, profile, limits) when is_list(transitions) do
    with :ok <- equal(length(transitions), length(entries), "/transitions") do
      Enum.zip(entries, transitions)
      |> Validation.each(fn {entry, point} ->
        with :ok <- Validation.fields(point, ~w(program_digest result)),
             :ok <- equal(point["program_digest"], entry["program"]["ir_digest"], "/transitions") do
          point(entry, point["result"], time, profile, limits)
        end
      end)
    end
  end

  defp points(_, _, _, _, _), do: Error.refusal(:invalid_type, "/transitions")

  defp point(%{"event" => nil}, result, _, _, _), do: equal(result, nil, "/transitions/result")

  defp point(entry, result, time, profile, limits),
    do:
      Transition.verify(
        entry["program"],
        entry["event"],
        entry["snapshot"],
        time,
        entry["prior"],
        result,
        profile,
        limits
      )

  defp active(entries, transitions, profile) do
    retained = Enum.flat_map(entries, &[&1["prior"]["original"], &1["prior"]["busy"]])
    advanced = Enum.map(transitions, &(&1["result"] && &1["result"]["run"]))

    count =
      Enum.reduce(retained ++ advanced, %{}, fn
        nil, runs -> runs
        run, runs -> Map.put(runs, {run["program_digest"], run["original"]}, live?(run))
      end)
      |> Map.values()
      |> Enum.count(& &1)

    bound(count, profile.data["active_runs"], :active_run_bound)
  end

  defp pending(entries, data, time, profile, limits) do
    cursor = %{
      proposals: data["proposals"],
      states: data["proposal_states"],
      count: 0,
      maximum: profile.data["pending_work"],
      limits: limits
    }

    with :ok <- lists(cursor.proposals, cursor.states),
         {:ok, rest} <-
           Enum.zip(entries, data["transitions"])
           |> Enum.reduce_while({:ok, cursor}, fn {entry, point}, {:ok, cursor} ->
             case DecisionPending.consume(entry, point["result"], time, cursor) do
               {:ok, cursor} -> {:cont, {:ok, cursor}}
               error -> {:halt, error}
             end
           end),
         :ok <- equal(rest.proposals, [], "/proposals") do
      equal(rest.states, [], "/proposal_states")
    end
  end

  defp lists(a, b) when is_list(a) and is_list(b), do: :ok
  defp lists(_, _), do: Error.refusal(:invalid_type, "/proposals")
  defp bound(count, maximum, _) when count <= maximum, do: :ok
  defp bound(_, _, code), do: Error.refusal(code)
  defp equal(value, value, _), do: :ok
  defp equal(_, _, path), do: Error.refusal(:invalid_collection_decision, path)
end
