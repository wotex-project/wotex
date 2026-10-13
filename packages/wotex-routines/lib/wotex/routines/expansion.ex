defmodule Wotex.Routines.Expansion do
  @moduledoc false

  alias Wotex.Routines.{CompilationContext, Error, Limits, Profile, Source, Unit, ValueContract}

  @spec build(Source.t(), map(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def build(source, context, profile, limits) do
    state = %{
      context: context,
      parameters: source.data["parameters"],
      profile: profile.data,
      limits: limits,
      nodes: 0,
      predicates: 0,
      effects: 0,
      waits: 0,
      depth: 0
    }

    args = context.data["arguments"]

    with {:ok, condition, state} <- predicate(source.data["condition"], args, state),
         :ok <- trigger(source.data["trigger"], state),
         {:ok, steps, _} <- node(source.data["steps"], args, [], state) do
      {:ok,
       %{
         "condition" => condition,
         "trigger" => source.data["trigger"],
         "steps" => steps,
         "run_ms" => source.data["run_ms"],
         "overlap" => source.data["overlap"]
       }}
    end
  end

  defp node(data, args, path, state) do
    with {:ok, state} <- charge(state, :nodes, "expanded_nodes") do
      expand(data, args, path, state)
    end
  end

  defp expand(%{"kind" => "effect"} = data, args, path, state) do
    binding = state.context.bindings[data["binding"]]
    basis = binding.basis.data

    with true <- basis["affordance"]["operation"] in ~w(writeproperty invokeaction),
         true <- data["completion"] == basis["evidence"]["completion"],
         {:ok, input} <-
           typed_argument(data["input"], args, state.parameters, basis["value"], state.limits),
         :ok <- ValueContract.accepts(basis["value"], input, state.limits),
         {:ok, state} <- charge(state, :effects, "effects") do
      ir =
        data
        |> Map.put("input", input)
        |> Map.put("path", Enum.reverse(path))
        |> Map.put("evidence_contract", basis["evidence"]["report_contract"])

      {:ok, ir, state}
    else
      false -> Error.refusal(:incompatible_effect, "/steps")
      error -> error
    end
  end

  defp expand(%{"kind" => kind} = data, args, path, state) when kind in ~w(sequence parallel) do
    key = if kind == "sequence", do: "steps", else: "branches"

    with {:ok, children, state} <- children(data[key], args, path, state) do
      ir =
        data
        |> Map.put(key, children)
        |> Map.put("path", Enum.reverse(path))

      {:ok, ir, state}
    end
  end

  defp expand(%{"kind" => "if"} = data, args, path, state) do
    with {:ok, condition, state} <- predicate(data["condition"], args, state),
         {:ok, yes, state} <- node(data["then"], args, [0 | path], state),
         {:ok, no, state} <- node(data["else"], args, [1 | path], state) do
      ir =
        data
        |> Map.put("condition", condition)
        |> Map.put("then", yes)
        |> Map.put("else", no)
        |> Map.put("path", Enum.reverse(path))

      {:ok, ir, state}
    end
  end

  defp expand(%{"kind" => "wait"} = data, args, path, state) do
    with {:ok, state} <- charge(state, :waits, "waits"),
         {:ok, condition, state} <- predicate(data["condition"], args, state) do
      ir =
        data
        |> Map.put("condition", condition)
        |> Map.put("path", Enum.reverse(path))

      {:ok, ir, state}
    end
  end

  defp expand(%{"kind" => "delay"} = data, _, path, state) do
    with {:ok, state} <- charge(state, :waits, "waits") do
      {:ok, Map.put(data, "path", path), state}
    end
  end

  defp expand(%{"kind" => "invoke"} = data, args, path, state) do
    child = state.context.definitions[data["routine_id"]]

    with true <- state.depth < state.profile["invocation_depth"],
         {:ok, values} <-
           bind_arguments(
             data["arguments"],
             args,
             state.parameters,
             child.data["parameters"],
             state.limits
           ),
         :ok <- CompilationContext.arguments(child.data["parameters"], values, state.limits),
         parent_parameters = state.parameters,
         {:ok, condition, state} <-
           predicate(child.data["condition"], values, %{
             state
             | parameters: child.data["parameters"]
           }),
         depth = state.depth,
         {:ok, body, state} <-
           node(child.data["steps"], values, [0 | path], %{
             state
             | depth: depth + 1,
               parameters: child.data["parameters"]
           }) do
      ir =
        data
        |> Map.put("arguments", values)
        |> Map.put("condition", condition)
        |> Map.put("run_ms", child.data["run_ms"])
        |> Map.put("body", body)
        |> Map.put("path", Enum.reverse(path))

      {:ok, ir, %{state | depth: depth, parameters: parent_parameters}}
    else
      false -> Error.refusal(:invocation_bound, "/steps")
      error -> error
    end
  end

  defp expand(%{"kind" => "noop"} = data, _, path, state),
    do: {:ok, Map.put(data, "path", path), state}

  defp children(values, args, path, state) do
    result =
      Enum.reduce_while(Enum.with_index(values), {:ok, [], state}, fn {value, index},
                                                                      {:ok, acc, state} ->
        case node(value, args, [index | path], state) do
          {:ok, child, state} -> {:cont, {:ok, [child | acc], state}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, children, state} -> {:ok, Enum.reverse(children), state}
      error -> error
    end
  end

  defp predicate(data, args, state) do
    with {:ok, state} <- charge(state, :predicates, "predicate_nodes") do
      predicate_form(data, args, state)
    end
  end

  defp predicate_form(%{"op" => "literal", "value" => value}, _, state),
    do: {:ok, [["literal", value]], state}

  defp predicate_form(%{"op" => operation} = data, args, state) when operation in ~w(eq gt lt) do
    basis = state.context.bindings[data["binding"]].basis.data

    with true <- basis["affordance"]["type"] in ~w(property event),
         true <- operation == "eq" or basis["value"]["type"] == "integer",
         {:ok, value} <-
           typed_argument(data["value"], args, state.parameters, basis["value"], state.limits),
         :ok <- ValueContract.accepts(basis["value"], value, state.limits) do
      {:ok, [[operation, data["binding"], value]], state}
    else
      false -> Error.refusal(:incompatible_predicate, "/condition")
      error -> error
    end
  end

  defp predicate_form(%{"op" => "not", "arg" => data}, args, state) do
    with {:ok, code, state} <- predicate(data, args, state) do
      {:ok, Enum.concat(code, [["not"]]), state}
    end
  end

  defp predicate_form(%{"op" => operation, "args" => values}, args, state)
       when operation in ~w(all any) do
    result =
      Enum.reduce_while(values, {:ok, [], state}, fn value, {:ok, code, state} ->
        case predicate(value, args, state) do
          {:ok, child, state} -> {:cont, {:ok, [child | code], state}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, code, state} ->
        instructions = Enum.flat_map(Enum.reverse(code), & &1)
        {:ok, Enum.concat(instructions, [[operation, length(values)]]), state}

      error ->
        error
    end
  end

  defp trigger(%{"kind" => "edge"} = data, state) do
    value = state.context.bindings[data["binding"]].basis.data
    type = value["value"]["type"]

    cond do
      value["affordance"]["type"] not in ~w(property event) ->
        Error.refusal(:incompatible_trigger, "/trigger")

      type == "boolean" and data["hysteresis"] == nil ->
        :ok

      type == "integer" and is_map(data["hysteresis"]) ->
        with :ok <- ValueContract.accepts(value["value"], data["hysteresis"]["enter"], state.limits) do
          ValueContract.accepts(value["value"], data["hysteresis"]["exit"], state.limits)
        end

      true ->
        Error.refusal(:incompatible_trigger, "/trigger")
    end
  end

  defp trigger(_, _), do: :ok

  defp typed_argument(%{"parameter" => name}, values, parameters, target, limits) do
    source = parameters[name]
    value = values[name]

    cond do
      source["type"] != target["type"] ->
        Error.refusal(:incompatible_parameter)

      source["type"] == "integer" ->
        Unit.convert(value, source["unit"], target["unit"], limits)

      true ->
        with :ok <- ValueContract.accepts(target, value, limits), do: {:ok, value}
    end
  end

  defp typed_argument(value, _, _, target, limits) do
    with :ok <- ValueContract.accepts(target, value, limits), do: {:ok, value}
  end

  defp bind_arguments(inputs, values, parameters, targets, limits) do
    Enum.reduce_while(inputs, {:ok, %{}}, fn {name, input}, {:ok, acc} ->
      case targets[name] do
        nil ->
          {:halt, Error.refusal(:unknown_parameter)}

        target ->
          case typed_argument(input, values, parameters, target, limits) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
            error -> {:halt, error}
          end
      end
    end)
  end

  defp charge(state, key, profile_key) do
    count = Map.fetch!(state, key)
    maximum = Map.fetch!(state.profile, profile_key)

    if is_integer(count) and is_integer(maximum) and count < maximum,
      do: {:ok, Map.put(state, key, count + 1)},
      else: Error.refusal(:expansion_bound, "/steps")
  end
end
