defmodule Wotex.Routines.CompilationContext do
  @moduledoc false

  alias Wotex.Routines.{Basis, Error, Limits, Profile, Registry, Source, Validation, ValueContract}

  @fields ~w(registry bases bindings definitions arguments compiler_basis)

  @spec new(term(), Source.t(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def new(input, source, profile, limits) do
    with {:ok, data, _} <- Validation.admit(input, limits, nil),
         :ok <-
           Validation.fields(data, @fields),
         :ok <- Validation.digest(data["compiler_basis"], "/compiler_basis"),
         {:ok, registry} <- Registry.new(data["registry"], limits),
         {:ok, bases} <- bases(data["bases"], registry, limits),
         {:ok, definitions} <- definitions(data["definitions"], source, profile, limits),
         :ok <- binding_names(data["bindings"], definitions),
         {:ok, bindings} <- bindings(data["bindings"], bases, registry, limits),
         :ok <- arguments(source.data["parameters"], data["arguments"], limits),
         :ok <- closure(definitions, limits) do
      {:ok,
       %{
         data: data,
         registry: registry,
         bases: bases,
         bindings: bindings,
         definitions: definitions
       }}
    end
  end

  @spec arguments(map(), term(), Limits.t()) :: :ok | {:error, Error.t()}
  def arguments(parameters, values, limits) do
    with :ok <- Validation.fields(values, Map.keys(parameters)) do
      Validation.each(Map.to_list(parameters), fn {name, contract} ->
        ValueContract.accepts(contract, values[name], limits)
      end)
    end
  end

  defp bases(values, registry, limits) when is_list(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn data, {:ok, acc} ->
      with {:ok, basis} <- Basis.new(data, registry, limits),
           false <- Map.has_key?(acc, basis.data["id"]) do
        {:cont, {:ok, Map.put(acc, basis.data["id"], basis)}}
      else
        true -> {:halt, Error.refusal(:duplicate_identity, "/bases")}
        error -> {:halt, error}
      end
    end)
  end

  defp bases(_, _, _), do: Error.refusal(:invalid_type, "/bases")

  defp definitions(values, source, profile, limits) when is_list(values) do
    if length(values) < profile.data["active_definitions"] do
      Enum.reduce_while(values, {:ok, %{source.data["id"] => source}}, fn data, {:ok, acc} ->
        with {:ok, child} <- Source.new(data, profile, limits),
             false <- Map.has_key?(acc, child.data["id"]) do
          {:cont, {:ok, Map.put(acc, child.data["id"], child)}}
        else
          true -> {:halt, Error.refusal(:duplicate_identity, "/definitions")}
          error -> {:halt, error}
        end
      end)
    else
      Error.refusal(:definition_bound, "/definitions")
    end
  end

  defp definitions(_, _, _, _), do: Error.refusal(:invalid_type, "/definitions")

  defp binding_names(bindings, definitions) do
    names =
      definitions
      |> Map.values()
      |> Enum.flat_map(& &1.data["bindings"])
      |> Enum.uniq()

    Validation.fields(bindings, names)
  end

  defp bindings(values, bases, registry, limits) do
    Enum.reduce_while(Enum.sort(values), {:ok, %{}}, fn {name, data}, {:ok, acc} ->
      with :ok <- Validation.text(name, "/bindings"),
           :ok <- Validation.fields(data, ~w(basis thing_id resource_roles)),
           :ok <- Registry.require_contract(registry, data["basis"], limits),
           %Basis{} = basis <- bases[data["basis"]["id"]],
           true <- Map.take(basis.data, ~w(id version semantic_digest)) == data["basis"],
           :ok <- Validation.iri(data["thing_id"], "/bindings/thing_id"),
           {:ok, domains} <- Basis.domains(basis, data["resource_roles"], registry, limits) do
        binding = %{data: data, basis: basis, domains: domains}
        {:cont, {:ok, Map.put(acc, name, binding)}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, Error.refusal(:unknown_binding_basis, "/bindings")}
      end
    end)
  end

  defp closure(definitions, limits) do
    graph = Map.new(definitions, fn {id, source} -> {id, invocations(source.data["steps"])} end)

    with :ok <-
           Validation.each(Map.values(graph), fn refs ->
             Validation.each(refs, &revision(&1, definitions))
           end),
         {:ok, _} <- visit_all(Enum.sort(Map.keys(graph)), graph, MapSet.new(), MapSet.new()) do
      Validation.each(Map.values(definitions), &validate_calls(&1, definitions, limits))
    end
  end

  defp revision({id, revision}, definitions) do
    case definitions[id] do
      %Source{data: %{"revision" => ^revision}} -> :ok
      _ -> Error.refusal(:missing_child_revision, "/definitions")
    end
  end

  defp validate_calls(source, definitions, limits) do
    Validation.each(calls(source.data["steps"]), fn call ->
      target = definitions[call["routine_id"]].data["parameters"]
      provided = call["arguments"]

      with :ok <- Validation.fields(provided, Map.keys(target)) do
        Validation.each(Map.to_list(provided), fn {name, value} ->
          declared_argument(value, source.data["parameters"], target[name], limits)
        end)
      end
    end)
  end

  defp declared_argument(%{"parameter" => name}, parameters, target, _) do
    source = parameters[name]

    compatible =
      source["type"] == target["type"] and
        (source["type"] != "integer" or source["unit"]["dimension"] == target["unit"]["dimension"])

    if compatible, do: :ok, else: Error.refusal(:incompatible_parameter, "/arguments")
  end

  defp declared_argument(value, _, target, limits), do: ValueContract.accepts(target, value, limits)

  defp calls(%{"kind" => "invoke"} = data), do: [data]
  defp calls(%{"kind" => "sequence", "steps" => values}), do: Enum.flat_map(values, &calls/1)
  defp calls(%{"kind" => "parallel", "branches" => values}), do: Enum.flat_map(values, &calls/1)
  defp calls(%{"kind" => "if", "then" => yes, "else" => no}), do: calls(yes) ++ calls(no)
  defp calls(_), do: []

  defp invocations(%{"kind" => "invoke", "routine_id" => id, "revision" => revision}),
    do: [{id, revision}]

  defp invocations(%{"kind" => "sequence", "steps" => values}),
    do: Enum.flat_map(values, &invocations/1)

  defp invocations(%{"kind" => "parallel", "branches" => values}),
    do: Enum.flat_map(values, &invocations/1)

  defp invocations(%{"kind" => "if", "then" => yes, "else" => no}),
    do: invocations(yes) ++ invocations(no)

  defp invocations(_), do: []

  defp visit_all(ids, graph, done, active) do
    Enum.reduce_while(ids, {:ok, done}, fn id, {:ok, done} ->
      cond do
        MapSet.member?(active, id) ->
          {:halt, Error.refusal(:recursive_invocation, "/definitions")}

        MapSet.member?(done, id) ->
          {:cont, {:ok, done}}

        true ->
          children = Enum.map(graph[id], &elem(&1, 0))

          case visit_all(children, graph, done, MapSet.put(active, id)) do
            {:ok, done} -> {:cont, {:ok, MapSet.put(done, id)}}
            error -> {:halt, error}
          end
      end
    end)
  end
end
