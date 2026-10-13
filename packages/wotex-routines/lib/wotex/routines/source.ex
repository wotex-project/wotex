defmodule Wotex.Routines.Source do
  @moduledoc "Closed bounded routine syntax. Construction screens structure without installing or executing it."

  alias Wotex.Routines.{Error, Limits, Profile, Validation, ValueContract}

  @fields ~w(format profile id revision parameters bindings trigger condition steps overlap run_ms)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates complete source syntax, references, identities and local resource bounds."
  @spec new(term(), Profile.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, data, limits} <- Validation.admit(input, narrowed(limits, profile), __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- Validation.choice(data["format"], ["wotex.routines.source@1"], "/format"),
         :ok <- Validation.choice(data["profile"], ["bounded-composition@1"], "/profile"),
         :ok <- Validation.text(data["id"], "/id"),
         :ok <- Validation.text(data["revision"], "/revision"),
         :ok <- Validation.choice(data["overlap"], ["reject"], "/overlap"),
         :ok <- parameters(data["parameters"], limits),
         :ok <- Validation.strings(data["bindings"], "/bindings"),
         :ok <- duration(data["run_ms"], profile.data["run_ms"], limits),
         state = initial(data, profile, limits),
         :ok <- trigger(data["trigger"], state),
         {:ok, state} <- predicate(data["condition"], state),
         {:ok, _} <- node(data["steps"], state) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates complete source before projecting its JSON data."
  @spec to_map(term(), Profile.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(source, profile, limits) do
    with {:ok, source} <- new(source, profile, limits), do: {:ok, source.data}
  end

  defp narrowed(limits, profile) do
    %{
      limits
      | data: %{
          limits.data
          | "max_bytes" => min(limits.data["max_bytes"], profile.data["source_bytes"]),
            "max_depth" => min(limits.data["max_depth"], profile.data["source_depth"])
        }
    }
  end

  defp parameters(data, limits) when is_map(data) do
    Validation.each(Map.to_list(data), fn {key, value} ->
      with :ok <- Validation.text(key, "/parameters") do
        ValueContract.validate(value, limits)
      end
    end)
  end

  defp parameters(_, _), do: Error.refusal(:invalid_type, "/parameters")

  defp initial(data, profile, limits) do
    %{
      parameters: data["parameters"],
      bindings: data["bindings"],
      limits: limits,
      profile: profile.data,
      run_ms: data["run_ms"],
      nodes: 0,
      predicates: 0,
      effects: 0,
      waits: 0,
      ids: MapSet.new()
    }
  end

  defp trigger(%{"kind" => "manual"} = data, _), do: Validation.fields(data, ~w(kind))

  defp trigger(%{"kind" => "due"} = data, _) do
    with :ok <- Validation.fields(data, ~w(kind schedule_id)) do
      Validation.text(data["schedule_id"], "/trigger/schedule_id")
    end
  end

  defp trigger(%{"kind" => "edge"} = data, state) do
    with :ok <-
           Validation.fields(data, ~w(kind binding direction debounce_ms cooldown_ms hysteresis)),
         :ok <- binding(data["binding"], state),
         :ok <- Validation.choice(data["direction"], ~w(rising falling), "/trigger/direction"),
         :ok <- Validation.integer(data["debounce_ms"], state.limits, "/trigger/debounce_ms", 0),
         :ok <- Validation.integer(data["cooldown_ms"], state.limits, "/trigger/cooldown_ms", 0) do
      hysteresis(data["hysteresis"], data["direction"], state)
    end
  end

  defp trigger(_, _), do: Error.refusal(:unsupported_trigger, "/trigger")

  defp hysteresis(nil, _, _), do: :ok

  defp hysteresis(data, direction, state) do
    with :ok <- Validation.fields(data, ~w(enter exit)),
         :ok <- Validation.integer(data["enter"], state.limits, "/trigger/hysteresis/enter"),
         :ok <- Validation.integer(data["exit"], state.limits, "/trigger/hysteresis/exit") do
      ordered =
        if direction == "rising",
          do: data["enter"] > data["exit"],
          else: data["enter"] < data["exit"]

      if ordered, do: :ok, else: Error.refusal(:invalid_hysteresis, "/trigger/hysteresis")
    end
  end

  defp predicate(data, state) do
    with true <- state.predicates < state.profile["predicate_nodes"],
         {:ok, state} <- predicate_form(data, %{state | predicates: state.predicates + 1}) do
      {:ok, state}
    else
      false -> Error.refusal(:predicate_bound, "/condition")
      error -> error
    end
  end

  defp predicate_form(%{"op" => "literal"} = data, state) do
    with :ok <- Validation.fields(data, ~w(op value)),
         :ok <- Validation.choice(data["value"], [true, false, "unknown"], "/condition/value") do
      {:ok, state}
    end
  end

  defp predicate_form(%{"op" => operation} = data, state) when operation in ~w(eq gt lt) do
    with :ok <- Validation.fields(data, ~w(op binding value)),
         :ok <- binding(data["binding"], state),
         :ok <- argument(data["value"], state) do
      {:ok, state}
    end
  end

  defp predicate_form(%{"op" => "not"} = data, state) do
    with :ok <- Validation.fields(data, ~w(op arg)), do: predicate(data["arg"], state)
  end

  defp predicate_form(%{"op" => operation} = data, state) when operation in ~w(all any) do
    with :ok <- Validation.fields(data, ~w(op args)),
         :ok <- nonempty(data["args"]) do
      reduce(data["args"], state, &predicate/2)
    end
  end

  defp predicate_form(_, _), do: Error.refusal(:unsupported_predicate, "/condition")

  defp node(data, state) do
    with true <- state.nodes < state.profile["expanded_nodes"],
         :ok <- Validation.text(if(is_map(data), do: data["id"], else: nil), "/steps/id"),
         false <- MapSet.member?(state.ids, data["id"]) do
      node_form(data, %{state | nodes: state.nodes + 1, ids: MapSet.put(state.ids, data["id"])})
    else
      true -> Error.refusal(:duplicate_identity, "/steps/id")
      false -> Error.refusal(:node_bound, "/steps")
      error -> error
    end
  end

  defp node_form(%{"kind" => "noop"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind)), do: {:ok, state}
  end

  defp node_form(%{"kind" => "effect"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind binding input completion)),
         :ok <- binding(data["binding"], state),
         :ok <- argument(data["input"], state),
         :ok <-
           Validation.choice(
             data["completion"],
             ~w(local_queue protocol_response correlated_report reported_match),
             "/steps/completion"
           ),
         true <- state.effects < state.profile["effects"] do
      {:ok, %{state | effects: state.effects + 1}}
    else
      false -> Error.refusal(:effect_bound, "/steps")
      error -> error
    end
  end

  defp node_form(%{"kind" => kind} = data, state) when kind in ~w(sequence parallel) do
    key = if kind == "sequence", do: "steps", else: "branches"

    with :ok <- Validation.fields(data, ["id", "kind", key]),
         :ok <- nonempty(data[key]),
         true <- kind != "parallel" or length(data[key]) <= state.profile["parallel_width"] do
      reduce(data[key], state, &node/2)
    else
      false -> Error.refusal(:parallel_bound, "/steps")
      error -> error
    end
  end

  defp node_form(%{"kind" => "if"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind condition then else)),
         {:ok, state} <- predicate(data["condition"], state),
         {:ok, state} <- node(data["then"], state) do
      node(data["else"], state)
    end
  end

  defp node_form(%{"kind" => "wait"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind condition timeout_ms)),
         :ok <- duration(data["timeout_ms"], state.run_ms, state.limits),
         true <- state.waits < state.profile["waits"],
         {:ok, state} <- predicate(data["condition"], state) do
      {:ok, %{state | waits: state.waits + 1}}
    else
      false -> Error.refusal(:wait_bound, "/steps")
      error -> error
    end
  end

  defp node_form(%{"kind" => "delay"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind duration_ms)),
         :ok <- duration(data["duration_ms"], state.run_ms, state.limits),
         true <- state.waits < state.profile["waits"] do
      {:ok, %{state | waits: state.waits + 1}}
    else
      false -> Error.refusal(:wait_bound, "/steps")
      error -> error
    end
  end

  defp node_form(%{"kind" => "invoke"} = data, state) do
    with :ok <- Validation.fields(data, ~w(id kind routine_id revision arguments)),
         :ok <- Validation.text(data["routine_id"], "/steps/routine_id"),
         :ok <- Validation.text(data["revision"], "/steps/revision") do
      arguments(data["arguments"], state)
    end
  end

  defp node_form(_, _), do: Error.refusal(:unsupported_step, "/steps")

  defp arguments(data, state) when is_map(data) do
    with :ok <-
           Validation.each(Map.to_list(data), fn {key, value} ->
             with :ok <- Validation.text(key, "/steps/arguments"), do: argument(value, state)
           end) do
      {:ok, state}
    end
  end

  defp arguments(_, _), do: Error.refusal(:invalid_type, "/steps/arguments")

  defp argument(%{"parameter" => name} = data, state) when map_size(data) == 1 do
    with :ok <- Validation.text(name, "/parameter") do
      if Map.has_key?(state.parameters, name),
        do: :ok,
        else: Error.refusal(:unknown_parameter, "/parameter")
    end
  end

  defp argument(value, _) when is_boolean(value) or is_integer(value) or is_binary(value), do: :ok
  defp argument(_, _), do: Error.refusal(:unsupported_argument)

  defp binding(name, state) do
    with :ok <- Validation.text(name, "/binding") do
      if name in state.bindings, do: :ok, else: Error.refusal(:unknown_binding, "/binding")
    end
  end

  defp duration(value, maximum, limits) do
    with :ok <- Validation.integer(value, limits, "/duration", 1) do
      if value <= maximum, do: :ok, else: Error.refusal(:duration_bound, "/duration")
    end
  end

  defp nonempty(values) when is_list(values) and values != [], do: :ok
  defp nonempty(_), do: Error.refusal(:empty_or_invalid_array)

  defp reduce(values, state, operation) do
    Enum.reduce_while(values, {:ok, state}, fn value, {:ok, state} ->
      case operation.(value, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end
end
