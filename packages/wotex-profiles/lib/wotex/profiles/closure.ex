defmodule Wotex.Profiles.Closure do
  @moduledoc false

  alias Wotex.Profiles.{Binding, Definition, Definitions, Error, Grammar, Limits, Profile}

  @type t :: map()

  @doc false
  @spec prepare(term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def prepare(profile, closure, limits) do
    with {:ok, limits} <- Limits.new(limits),
         :ok <- Grammar.fields(closure, ~w(definitions bindings contracts), "/closure"),
         {:ok, definitions} <- collection(closure["definitions"], limits.data["max_definitions"]),
         {:ok, bindings} <- collection(closure["bindings"], limits.data["max_bindings"]),
         {:ok, contracts} <- collection(closure["contracts"], limits.data["max_dependencies"]),
         {:ok, _, _} <-
           Grammar.admit(
             %{
               "profile" => unwrap(profile),
               "closure" => %{
                 "definitions" => Enum.map(definitions, &unwrap/1),
                 "bindings" => Enum.map(bindings, &unwrap/1),
                 "contracts" => contracts
               }
             },
             limits
           ),
         {:ok, profile} <- Profile.new(profile, limits),
         {:ok, definitions} <- Definitions.new(definitions, limits),
         {:ok, bindings} <- bindings(bindings, limits),
         :ok <- Grammar.references(contracts, limits, "/closure/contracts"),
         {:ok, index} <- index(profile, definitions, bindings, contracts),
         :ok <- cycles(profile, index, limits),
         state = %{
           profile: profile,
           limits: limits,
           index: index,
           marks: %{},
           refs: %{},
           closure: %{
             "definitions" => Enum.map(definitions, & &1.data),
             "bindings" => Enum.map(bindings, & &1.data),
             "contracts" => contracts
           }
         },
         {:ok, _, state} <- visit(reference(profile), state, "/profile", :profile),
         {:ok, binding, state} <- visit(profile.data["binding"], state, "/binding", :binding),
         :ok <- fingerprint_fields(profile.data["fingerprint"], binding.data["capture_fields"]),
         {:ok, state} <- dependencies(profile.data["requires"], state, "/requires", :dependency) do
      {:ok, Map.put(state, :binding, binding)}
    end
  end

  @doc false
  @spec definition(map(), t(), String.t()) :: {:ok, map(), t()} | {:error, Error.t()}
  def definition(reference, state, path), do: visit(reference, state, path, :definition)

  @doc false
  @spec references(t()) :: [map()]
  def references(state) do
    state.refs
    |> Map.values()
    |> Enum.sort_by(&{&1["id"], &1["version"]})
  end

  defp collection(values, maximum), do: collection(values, maximum, [])
  defp collection([], _, acc), do: {:ok, Enum.reverse(acc)}
  defp collection([_ | _], 0, _), do: Error.refusal(:input_limit, "/closure")

  defp collection([value | rest], remaining, acc),
    do: collection(rest, remaining - 1, [value | acc])

  defp collection(_, _, _), do: Error.refusal(:invalid_input, "/closure")

  defp unwrap(%{__struct__: module, data: data}) when module in [Profile, Definition, Binding],
    do: data

  defp unwrap(value), do: value

  defp bindings(values, limits) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case Binding.new(value, limits) do
          {:ok, binding} -> {:cont, {:ok, [binding | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, values} -> {:ok, Enum.sort_by(values, &{&1.data["id"], &1.data["version"]})}
      error -> error
    end
  end

  defp reference(%Profile{} = value),
    do: Map.put(Map.take(value.data, ~w(id version)), "sha256", value.semantic_sha256)

  defp reference(%Definition{} = value),
    do: Map.put(Map.take(value.data, ~w(id version)), "sha256", value.semantic_sha256)

  defp reference(%Binding{} = value), do: Map.take(value.data, ~w(id version sha256))
  defp reference(value), do: value

  defp index(profile, definitions, bindings, contracts) do
    entries =
      [{:profile, profile}] ++
        Enum.map(definitions, &{:definition, &1}) ++
        Enum.map(bindings, &{:binding, &1}) ++ Enum.map(contracts, &{:contract, &1})

    Enum.reduce_while(entries, {:ok, %{}}, fn {kind, value}, {:ok, index} ->
      ref = reference(value)
      key = key(ref)

      if Map.has_key?(index, key) do
        {:halt, Error.refusal(:reference_conflict, "/closure")}
      else
        data = if kind == :contract, do: value, else: value.data
        {:cont, {:ok, Map.put(index, key, %{kind: kind, data: data, ref: ref})}}
      end
    end)
  end

  defp key(reference), do: {reference["id"], reference["version"]}

  defp visit(reference, state, path, expected) do
    key = key(reference)

    with {:ok, entry} <- lookup(reference, state.index, path),
         true <- allowed?(entry.kind, expected) do
      case state.marks[key] do
        :visiting -> Error.refusal(:cyclic_reference, path)
        :done -> {:ok, entry, state}
        nil -> expand(key, entry, state, path)
      end
    else
      false -> Error.refusal(:unsupported_semantics, path)
      error -> error
    end
  end

  defp lookup(reference, index, path) do
    case index[key(reference)] do
      nil -> Error.refusal(:missing_reference, path)
      %{ref: ^reference} = entry -> {:ok, entry}
      _ -> Error.refusal(:reference_conflict, path)
    end
  end

  defp allowed?(kind, kind), do: true
  defp allowed?(kind, :dependency), do: kind in [:definition, :contract]
  defp allowed?(_, _), do: false

  defp expand(key, entry, state, path) do
    if map_size(state.refs) < state.limits.data["max_dependencies"] do
      state = %{
        state
        | marks: Map.put(state.marks, key, :visiting),
          refs: Map.put(state.refs, key, entry.ref)
      }

      with {:ok, state} <- expand_entry(entry, state, path) do
        {:ok, entry, %{state | marks: Map.put(state.marks, key, :done)}}
      end
    else
      Error.refusal(:input_limit, path)
    end
  end

  defp expand_entry(%{kind: :definition, data: data}, state, path) do
    with {:ok, state} <- dependencies(data["requires"], state, path, :dependency) do
      if data["behaviour"] == nil,
        do: {:ok, state},
        else: dependencies([data["behaviour"]], state, path, :contract)
    end
  end

  defp expand_entry(%{kind: :binding, data: data}, state, path),
    do: dependencies([data["raw_value_contract"] | data["codec_contracts"]], state, path, :contract)

  defp expand_entry(_, state, _), do: {:ok, state}

  defp dependencies(values, state, path, expected) do
    Enum.reduce_while(values, {:ok, state}, fn reference, {:ok, state} ->
      case visit(reference, state, path, expected) do
        {:ok, _, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp fingerprint_fields(predicates, fields) do
    if Enum.all?(predicates, &(&1["field"] in fields)),
      do: :ok,
      else: Error.refusal(:unsupported_binding, "/fingerprint")
  end

  defp cycles(profile, index, limits) do
    roots = profile.data["requires"] ++ Enum.map(profile.data["channels"], & &1["semantic"])

    case cycle_edges(roots, index, %{}, limits.data["max_dependencies"]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp cycle_edges(values, index, marks, maximum) do
    Enum.reduce_while(values, {:ok, marks}, fn reference, {:ok, marks} ->
      case cycle_node(key(reference), index, marks, maximum) do
        {:ok, marks} -> {:cont, {:ok, marks}}
        error -> {:halt, error}
      end
    end)
  end

  defp cycle_node(key, index, marks, maximum) do
    case {marks[key], index[key]} do
      {:visiting, _} ->
        Error.refusal(:cyclic_reference, "/closure/definitions")

      {:done, _} ->
        {:ok, marks}

      {nil, %{kind: :definition, data: data}} ->
        if map_size(marks) < maximum do
          with {:ok, marks} <-
                 cycle_edges(data["requires"], index, Map.put(marks, key, :visiting), maximum),
               do: {:ok, Map.put(marks, key, :done)}
        else
          Error.refusal(:input_limit, "/closure/definitions")
        end

      _ ->
        {:ok, marks}
    end
  end
end
