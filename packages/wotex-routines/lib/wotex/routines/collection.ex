defmodule Wotex.Routines.Collection do
  @moduledoc "Complete provided-set evaluation before batching. Only the consumer establishes actual active membership."

  alias Wotex.Routines.{
    Compiler,
    Error,
    ExecutionPrior,
    Kernel,
    Limits,
    Profile,
    Snapshot,
    Time,
    Validation
  }

  @fields ~w(format input profile json_limits transitions proposals collection_digest)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks full supplied membership and shared snapshot coherence, then evaluates every entry."
  @spec evaluate(term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def evaluate(input, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, input, limits} <- Validation.admit(input, limits, nil),
         :ok <- Validation.fields(input, ~w(membership entries time)),
         :ok <- membership(input["membership"], profile),
         {:ok, time} <- Time.to_map(input["time"], limits),
         {:ok, entries} <- entries(input["entries"], profile, limits),
         :ok <- complete(entries, input["membership"]),
         :ok <- coherent(entries),
         {:ok, transitions} <- transitions(entries, time, profile, limits),
         :ok <- active_runs(entries, transitions, profile),
         {:ok, proposals} <- proposals(transitions, profile) do
      data = %{
        "format" => "wotex.routines.collection@1",
        "input" => input,
        "profile" => profile.data,
        "json_limits" => limits.data,
        "transitions" => transitions,
        "proposals" => proposals
      }

      with :ok <- Validation.bounded(data, limits),
           {:ok, digest} <- Validation.hash(data, limits),
           :ok <- Validation.bounded(Map.put(data, "collection_digest", digest), limits) do
        {:ok, %__MODULE__{data: Map.put(data, "collection_digest", digest)}}
      end
    end
  end

  @doc "Regenerates the entire collection; recomputed digests cannot validate altered proposals or membership."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(collection, profile, limits) do
    with {:ok, data, _} <- Validation.admit(collection, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         {:ok, rebuilt} <- evaluate(data["input"], profile, limits) do
      if data == rebuilt.data, do: {:ok, data}, else: Error.refusal(:stale_or_forged_collection)
    end
  end

  defp membership(data, profile) do
    with :ok <- Validation.fields(data, ~w(generation programs)),
         :ok <- Validation.text(data["generation"], "/membership/generation"),
         :ok <- Validation.strings(data["programs"], "/membership/programs"),
         :ok <- Validation.each(data["programs"], &Validation.digest(&1, "/membership/programs")) do
      if length(data["programs"]) <= profile.data["active_definitions"],
        do: :ok,
        else: Error.refusal(:definition_bound)
    end
  end

  defp entries(values, profile, limits) when is_list(values) do
    if length(values) <= profile.data["active_definitions"] do
      Enum.reduce_while(values, {:ok, []}, fn entry, {:ok, entries} ->
        case entry(entry, profile, limits) do
          {:ok, checked} -> {:cont, {:ok, [checked | entries]}}
          error -> {:halt, error}
        end
      end)
    else
      Error.refusal(:definition_bound)
    end
  end

  defp entries(_, _, _), do: Error.refusal(:invalid_type, "/entries")

  defp entry(data, profile, limits) do
    with :ok <- Validation.fields(data, ~w(program event snapshot prior)),
         {:ok, program} <- Compiler.to_map(data["program"], profile, limits),
         {:ok, snapshot} <- Snapshot.to_map(data["snapshot"], program, profile, limits),
         {:ok, prior} <- ExecutionPrior.new(data["prior"], program, profile, limits) do
      {:ok, %{data | "program" => program, "snapshot" => snapshot, "prior" => prior}}
    end
  end

  defp complete(entries, membership) do
    digests = Enum.map(entries, & &1["program"]["ir_digest"])
    snapshots = Enum.map(entries, & &1["snapshot"])

    valid =
      Enum.sort(digests) == Enum.sort(membership["programs"]) and
        length(Enum.uniq(digests)) == length(digests) and
        Enum.all?(
          snapshots,
          &(&1["membership_generation"] == membership["generation"] and
              &1["active_programs"] == membership["programs"])
        )

    if valid, do: :ok, else: Error.refusal(:incomplete_collection)
  end

  defp coherent([]), do: :ok

  defp coherent(entries) do
    ids =
      entries
      |> Enum.map(& &1["snapshot"]["id"])
      |> Enum.uniq()

    with true <- length(ids) == 1,
         :ok <- shared_resources(entries) do
      shared_observations(entries)
    else
      false -> Error.refusal(:incoherent_collection_snapshot)
      error -> error
    end
  end

  defp shared_resources(entries) do
    pairs = Enum.flat_map(entries, &Map.to_list(&1["snapshot"]["resource_revisions"]))
    consistent(pairs)
  end

  defp shared_observations(entries) do
    pairs =
      Enum.flat_map(entries, fn entry ->
        Enum.map(entry["program"]["context"]["bindings"], fn {name, binding} ->
          basis =
            Enum.find(
              entry["program"]["context"]["bases"],
              &(Map.take(&1, ~w(id version semantic_digest)) == binding["basis"])
            )

          affordance = basis["affordance"]

          key =
            {binding["thing_id"], affordance["type"], affordance["name"], affordance["operation"]}

          {key,
           {binding["basis"], entry["snapshot"]["binding_bases"][name],
            entry["snapshot"]["facts"][name]}}
        end)
      end)

    consistent(pairs)
  end

  defp consistent(pairs) do
    Enum.reduce_while(pairs, %{}, fn {key, value}, seen ->
      if Map.has_key?(seen, key) and seen[key] != value,
        do: {:halt, :incoherent},
        else: {:cont, Map.put(seen, key, value)}
    end)
    |> consistency_result()
  end

  defp consistency_result(:incoherent), do: Error.refusal(:incoherent_collection_snapshot)
  defp consistency_result(_), do: :ok

  defp transitions(entries, time, profile, limits) do
    entries
    |> Enum.sort_by(& &1["program"]["ir_digest"])
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, transitions} ->
      case transition(entry, time, profile, limits) do
        {:ok, result} ->
          record = %{"program_digest" => entry["program"]["ir_digest"], "result" => result}
          {:cont, {:ok, [record | transitions]}}

        error ->
          {:halt, error}
      end
    end)
    |> ordered()
  end

  defp transition(%{"event" => nil}, _, _, _), do: {:ok, nil}

  defp transition(entry, time, profile, limits),
    do:
      Kernel.advance(
        entry["program"],
        entry["event"],
        entry["snapshot"],
        time,
        entry["prior"],
        profile,
        limits
      )

  defp ordered({:ok, records}), do: {:ok, Enum.reverse(records)}
  defp ordered(error), do: error

  defp active_runs(entries, transitions, profile) do
    retained = Enum.flat_map(entries, &[&1["prior"]["original"], &1["prior"]["busy"]])

    advanced =
      Enum.map(transitions, fn
        %{"result" => nil} -> nil
        %{"result" => result} -> result["run"]
      end)

    count =
      retained
      |> Enum.concat(advanced)
      |> Enum.filter(&is_map/1)
      |> Map.new(&{{&1["program_digest"], &1["original"]}, &1})
      |> Map.values()
      |> Enum.count(&(&1["status"] in ~w(running blocked)))

    if count <= profile.data["active_runs"], do: :ok, else: Error.refusal(:active_run_bound)
  end

  defp proposals(transitions, profile) do
    proposals =
      Enum.flat_map(transitions, fn
        %{"result" => nil} -> []
        %{"result" => result} -> result["proposals"]
      end)

    if length(proposals) <= profile.data["pending_work"],
      do: {:ok, proposals},
      else: Error.refusal(:pending_work_bound)
  end
end
