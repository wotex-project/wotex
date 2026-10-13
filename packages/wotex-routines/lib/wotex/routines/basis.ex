defmodule Wotex.Routines.Basis do
  @moduledoc "Installed, closed behaviour semantics. A basis supplies no device identity or authority."

  alias Wotex.Routines.{Error, Limits, Registry, Unit, Validation}

  @fields ~w(format id version byte_digest semantic_digest implementation_digest compiler_digest
    affordance value security_contract lifecycle_contract required_contracts evidence effects
    timing analysis annotations)
  @digests ~w(byte_digest semantic_digest implementation_digest compiler_digest)
  @operations %{
    "property" => ~w(readproperty writeproperty observeproperty),
    "action" => ~w(invokeaction),
    "event" => ~w(subscribeevent)
  }
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Checks complete semantics, canonical identity and every exact offline contract."
  @spec new(term(), Registry.t(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, registry, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @fields),
         :ok <- Validation.choice(data["format"], ["wotex.routines.basis@1"], "/format"),
         :ok <- Validation.text(data["id"], "/id"),
         :ok <- Validation.text(data["version"], "/version"),
         :ok <- Validation.each(@digests, &Validation.digest(data[&1], "/" <> &1)),
         :ok <- affordance(data["affordance"]),
         :ok <- value(data["value"], limits),
         :ok <- evidence(data["evidence"], limits),
         :ok <- effects(data["effects"]),
         :ok <- timing(data["timing"], limits),
         :ok <- analysis(data["analysis"]),
         :ok <- annotations(data["annotations"]),
         {:ok, digest} <- semantic_digest(data, limits),
         :ok <- matches_digest(data["semantic_digest"], digest),
         :ok <- contracts(data, registry, limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Hashes the sorted-key semantic projection; calculation alone does not admit a basis."
  @spec semantic_digest(term(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def semantic_digest(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         true <- is_map(data) do
      Validation.hash(Map.drop(data, @digests), limits)
    else
      false -> Error.refusal(:invalid_type)
      error -> error
    end
  end

  @doc "Resolves all roles to sorted whole-resource domains after full basis revalidation."
  @spec domains(t(), term(), Registry.t(), Limits.t()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def domains(basis, bindings, registry, limits) do
    with {:ok, basis} <- new(basis, registry, limits),
         {:ok, bindings, _} <- Validation.admit(bindings, limits, nil),
         roles = basis.data["effects"]["resource_roles"],
         :ok <- Validation.fields(bindings, roles),
         :ok <- Validation.each(Map.values(bindings), &Validation.text(&1, "/bindings")) do
      domains =
        bindings
        |> Map.values()
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, domains}
    end
  end

  @doc "Revalidates the complete basis before projecting it as JSON data."
  @spec to_map(term(), Registry.t(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(value, registry, limits) do
    with {:ok, value} <- new(value, registry, limits), do: {:ok, value.data}
  end

  defp affordance(data) do
    with :ok <- Validation.fields(data, ~w(type name operation), [], "/affordance"),
         :ok <- Validation.text(data["name"], "/affordance/name"),
         :ok <- Validation.choice(data["type"], Map.keys(@operations), "/affordance/type") do
      Validation.choice(data["operation"], @operations[data["type"]], "/affordance/operation")
    end
  end

  defp value(data, limits) do
    with :ok <- Validation.fields(data, ~w(type unit enum), [], "/value"),
         :ok <- Validation.choice(data["type"], ~w(boolean integer enum), "/value/type") do
      case data do
        %{"type" => "boolean", "unit" => nil, "enum" => []} ->
          :ok

        %{"type" => "integer", "enum" => [], "unit" => unit} ->
          case Unit.new(unit, limits) do
            {:ok, _} -> :ok
            error -> error
          end

        %{"type" => "enum", "unit" => nil, "enum" => values} ->
          Validation.strings(values, "/value/enum", true)

        _ ->
          Error.refusal(:invalid_value_contract, "/value")
      end
    end
  end

  defp evidence(data, limits) do
    with :ok <-
           Validation.fields(
             data,
             ~w(sources freshness_ms require_source_time continuity completion),
             [],
             "/evidence"
           ),
         :ok <- Validation.strings(data["sources"], "/evidence/sources", true),
         :ok <-
           Validation.each(
             data["sources"],
             &Validation.choice(
               &1,
               ~w(device_report derived_report protocol_response),
               "/evidence/sources"
             )
           ),
         :ok <- Validation.integer(data["freshness_ms"], limits, "/evidence/freshness_ms", 0),
         :ok <- Validation.boolean(data["require_source_time"], "/evidence/require_source_time"),
         :ok <-
           Validation.choice(data["continuity"], ~w(continuous snapshot), "/evidence/continuity") do
      Validation.choice(
        data["completion"],
        ~w(local_queue protocol_response correlated_report reported_match),
        "/evidence/completion"
      )
    end
  end

  defp effects(data) do
    with :ok <-
           Validation.fields(
             data,
             ~w(resource_roles repeat stop supersession partial_possible unknown_possible),
             [],
             "/effects"
           ),
         :ok <- Validation.strings(data["resource_roles"], "/effects/resource_roles"),
         :ok <-
           Validation.choice(
             data["repeat"],
             ~w(never after_known_failure after_reported_safe),
             "/effects/repeat"
           ),
         :ok <- Validation.choice(data["stop"], ~w(unsupported separate_effect), "/effects/stop"),
         :ok <-
           Validation.choice(data["supersession"], ["block_until_known"], "/effects/supersession"),
         :ok <- Validation.boolean(data["partial_possible"], "/effects/partial_possible"),
         :ok <- Validation.boolean(data["unknown_possible"], "/effects/unknown_possible") do
      if data["resource_roles"] == [] or data["unknown_possible"],
        do: :ok,
        else: Error.refusal(:missing_unknown_outcome, "/effects/unknown_possible")
    end
  end

  defp timing(data, limits) do
    with :ok <-
           Validation.fields(
             data,
             ~w(deadline_ms duration_ms dwell_ms cooldown_ms uncertainty),
             [],
             "/timing"
           ),
         :ok <- Validation.integer(data["deadline_ms"], limits, "/timing/deadline_ms", 1),
         :ok <-
           Validation.each(
             ~w(duration_ms dwell_ms cooldown_ms),
             &Validation.integer(data[&1], limits, "/timing/" <> &1, 0)
           ) do
      Validation.choice(data["uncertainty"], ["block"], "/timing/uncertainty")
    end
  end

  defp analysis(data) do
    with :ok <- Validation.fields(data, ~w(classification profile properties), [], "/analysis") do
      case data do
        %{"classification" => "unsupported", "profile" => nil, "properties" => []} ->
          :ok

        %{"classification" => "supported", "properties" => properties} ->
          Validation.strings(properties, "/analysis/properties", true)

        _ ->
          Error.refusal(:unsupported_analysis, "/analysis")
      end
    end
  end

  defp annotations(data) do
    with :ok <- Validation.fields(data, [], ~w(title description tags), "/annotations"),
         :ok <-
           Validation.each(
             Map.take(data, ~w(title description)) |> Map.values(),
             &Validation.text(&1, "/annotations")
           ) do
      Validation.strings(Map.get(data, "tags", []), "/annotations/tags")
    end
  end

  defp contracts(data, registry, limits) do
    root = Map.take(data, ~w(id version semantic_digest))

    case data["required_contracts"] do
      required when is_list(required) ->
        model =
          if data["analysis"]["classification"] == "supported",
            do: [data["analysis"]["profile"]],
            else: []

        Registry.require_all(
          registry,
          [root, data["security_contract"], data["lifecycle_contract"]] ++ required ++ model,
          limits
        )

      _ ->
        Error.refusal(:invalid_type, "/required_contracts")
    end
  end

  defp matches_digest(value, value), do: :ok
  defp matches_digest(_, _), do: Error.refusal(:semantic_digest_mismatch, "/semantic_digest")
end
