defmodule Wotex.Profiles.Finalizer do
  @moduledoc false

  alias Wotex.Profiles.{Definition, Error, Grammar, Profile}

  @type state :: map()

  @doc false
  @spec resolve(map(), map(), non_neg_integer(), boolean()) ::
          {:ok, map(), non_neg_integer()} | {:error, Error.t()}
  def resolve(data, contract, steps, draft) do
    with :ok <- canonical_input(data, contract, draft),
         :ok <-
           definition_budget(data["definitions"], contract["limits"]["reader"]["max_definitions"]),
         {:ok, index} <- index(data["definitions"]),
         state = %{
           index: index,
           result: %{},
           marks: %{},
           remaining: steps,
           contracts: contract["contracts"],
           limits: contract["limits"]["reader"],
           draft: draft
         },
         {:ok, requires, state} <-
           references(data["profile"]["requires"], state, "/profile/requires"),
         {:ok, channels, state} <- channels(data["profile"]["channels"], state),
         true <- map_size(state.result) == map_size(index),
         profile = Map.merge(data["profile"], %{"requires" => requires, "channels" => channels}),
         :ok <-
           installed(
             profile["binding"],
             Enum.map(contract["bindings"], &Map.take(&1, ~w(id version sha256))),
             "/profile/binding"
           ),
         {:ok, profile} <- Profile.new(profile, state.limits) do
      definitions =
        state.result
        |> Map.values()
        |> Enum.sort_by(&{&1["id"], &1["version"]})

      {:ok,
       %{
         "format" => "wotex.profile.bundle@1",
         "profile" => profile.data,
         "definitions" => definitions
       }, state.remaining}
    else
      false -> Error.refusal(:invalid_input, "/definitions")
      error -> error
    end
  end

  defp definition_budget(values, maximum) do
    if length(values) <= maximum, do: :ok, else: Error.refusal(:input_limit, "/definitions")
  end

  defp canonical_input(_, _, true), do: :ok

  defp canonical_input(data, contract, false) do
    limits = contract["limits"]["reader"]

    with {:ok, _} <- Profile.new(data["profile"], limits),
         :ok <- Grammar.sorted_unique(data["definitions"], &key/1, "/definitions") do
      Grammar.each(data["definitions"], fn definition ->
        case Definition.new(definition, limits) do
          {:ok, _} -> :ok
          error -> error
        end
      end)
    end
  end

  defp index(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn value, {:ok, index} ->
      with :ok <- Grammar.id(value["id"], "/definitions"),
           :ok <- Grammar.version(value["version"], "/definitions"),
           key = key(value),
           false <- Map.has_key?(index, key) do
        {:cont, {:ok, Map.put(index, key, value)}}
      else
        true -> {:halt, Error.refusal(:reference_conflict, "/definitions")}
        error -> {:halt, error}
      end
    end)
  end

  defp key(value), do: {value["id"], value["version"]}
  defp tick(%{remaining: 0}), do: Error.refusal(:input_limit)
  defp tick(state), do: {:ok, %{state | remaining: state.remaining - 1}}

  defp references(values, state, path) do
    result =
      Enum.reduce_while(values, {:ok, [], state}, fn reference, {:ok, acc, state} ->
        case reference(reference, state, path) do
          {:ok, value, state} -> {:cont, {:ok, [value | acc], state}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, values, state} -> {:ok, Enum.sort_by(values, &key/1), state}
      error -> error
    end
  end

  defp reference(reference, state, path) do
    with {:ok, state} <- tick(state) do
      case reference do
        %{"local" => local} when map_size(reference) == 1 and state.draft ->
          definition(local, nil, state, path)

        %{"id" => _, "version" => _, "sha256" => _} ->
          exact_reference(reference, state, path)

        _ ->
          Error.refusal(:invalid_input, path)
      end
    end
  end

  defp exact_reference(reference, state, path) do
    with :ok <- Grammar.reference(reference, path) do
      if Map.has_key?(state.index, key(reference)),
        do: definition(reference, reference, state, path),
        else: exact_contract(reference, state, path)
    end
  end

  defp exact_contract(reference, state, path) do
    with :ok <- installed(reference, state.contracts, path), do: {:ok, reference, state}
  end

  defp installed(reference, values, path) do
    case Enum.find(values, &(key(&1) == key(reference))) do
      nil -> Error.refusal(:missing_reference, path)
      ^reference -> :ok
      _ -> Error.refusal(:reference_conflict, path)
    end
  end

  defp definition(local, exact, state, path) do
    key = key(local)

    case {state.marks[key], state.index[key]} do
      {:visiting, _} -> Error.refusal(:cyclic_reference, path)
      {:done, _} -> checked_ref(state.result[key], exact, state, path)
      {nil, nil} -> Error.refusal(:missing_reference, path)
      {nil, data} -> expand(key, data, exact, state, path)
    end
  end

  defp expand(key, data, exact, state, path) do
    with {:ok, state} <- tick(state),
         true <- map_size(state.marks) < state.limits["max_dependencies"],
         state = %{state | marks: Map.put(state.marks, key, :visiting)},
         {:ok, requires, state} <- references(data["requires"], state, path),
         :ok <- behaviour(data["behaviour"], state, path),
         data = Map.put(data, "requires", requires),
         {:ok, definition} <- Definition.new(normalize_schema(data), state.limits) do
      state = %{
        state
        | result: Map.put(state.result, key, definition.data),
          marks: Map.put(state.marks, key, :done)
      }

      checked_ref(definition.data, exact, state, path)
    else
      false -> Error.refusal(:input_limit, path)
      error -> error
    end
  end

  defp behaviour(nil, _, _), do: :ok
  defp behaviour(reference, state, path), do: installed(reference, state.contracts, path)

  defp checked_ref(data, exact, state, path) do
    with {:ok, reference} <- Definition.reference(data, state.limits),
         true <- exact == nil or reference == exact do
      {:ok, reference, state}
    else
      false -> Error.refusal(:reference_conflict, path)
      error -> error
    end
  end

  defp channels(values, state) do
    result =
      Enum.reduce_while(Enum.with_index(values), {:ok, [], state}, fn {channel, index},
                                                                      {:ok, acc, state} ->
        case reference(
               channel["semantic"],
               state,
               "/profile/channels/" <> Integer.to_string(index) <> "/semantic"
             ) do
          {:ok, reference, state} ->
            channel =
              Map.merge(channel, %{
                "semantic" => reference,
                "operations" => Enum.sort(channel["operations"])
              })

            case table(channel) do
              {:ok, channel} -> {:cont, {:ok, [channel | acc], state}}
              error -> {:halt, error}
            end

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, channels, state} -> {:ok, Enum.sort_by(channels, & &1["id"]), state}
      error -> error
    end
  end

  defp table(%{"conversion" => %{"kind" => "table", "entries" => entries} = conversion} = channel) do
    result =
      Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
        case Wotex.Runtime.Codec.Value.encode(entry["source"]) do
          {:ok, bytes} -> {:cont, {:ok, [{bytes, entry} | acc]}}
          _ -> {:halt, Error.refusal(:invalid_input, "/profile/channels")}
        end
      end)

    with {:ok, entries} <- result do
      sorted =
        entries
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))

      {:ok, Map.put(channel, "conversion", Map.put(conversion, "entries", sorted))}
    end
  end

  defp table(channel), do: {:ok, channel}

  defp normalize_schema(data) do
    Map.update!(data, "value_schema", &schema/1)
  end

  defp schema(value) do
    value =
      if Map.has_key?(value, "required"),
        do: Map.update!(value, "required", &Enum.sort/1),
        else: value

    value = if Map.has_key?(value, "items"), do: Map.update!(value, "items", &schema/1), else: value

    if Map.has_key?(value, "properties"),
      do:
        Map.update!(value, "properties", &Map.new(&1, fn {key, value} -> {key, schema(value)} end)),
      else: value
  end
end
