defmodule WotexContinuum.Compatibility do
  @moduledoc """
  Pure schema and capability requirements for continuum composition.

  The evaluator compares one schema version and a set of declared capabilities
  against the complete requirement set. It returns every mismatch in stable
  order so consumers can explain why composition failed instead of hiding
  detail behind a boolean.

  Compatibility proves declared version relationships only. It does not prove
  conformance, trust, availability, or permission.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Capability, CapabilityRequirement, Contract, Error, Validation}

  @kind "compatibility"

  @enforce_keys [:schema_requirement, :required_capabilities]
  defstruct [:schema_requirement, :required_capabilities, extensions: %{}]

  @type mismatch ::
          %{type: :schema, requirement: String.t(), actual: String.t()}
          | %{type: :missing_capability, id: String.t(), requirement: String.t()}
          | %{
              type: :capability_version,
              id: String.t(),
              requirement: String.t(),
              actual: String.t()
            }

  @type t :: %__MODULE__{
          schema_requirement: String.t(),
          required_capabilities: [CapabilityRequirement.t()],
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{} = value), do: from_map(Map.from_struct(value))

  def from_map(data) do
    fields = [:schema_requirement, :required_capabilities, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, requirement} <- Validation.required(data, :schema_requirement),
         {:ok, requirement} <-
           Validation.version_requirement(requirement, "/schema_requirement"),
         {:ok, capabilities} <-
           Validation.structs(
             Map.get(data, :required_capabilities, []),
             "/required_capabilities",
             CapabilityRequirement
           ),
         :ok <- unique_requirements(capabilities),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         schema_requirement: requirement,
         required_capabilities: capabilities,
         extensions: extensions
       }}
    end
  end

  @doc "Returns all deterministic compatibility mismatches."
  @spec evaluate(t(), String.t(), [Capability.t()]) :: :ok | {:error, [mismatch()]}
  def evaluate(%__MODULE__{} = requirements, schema_version, capabilities)
      when is_binary(schema_version) and is_list(capabilities) do
    declared = Map.new(capabilities, &{&1.id, &1.version})

    schema_mismatches =
      if matches_requirement?(schema_version, requirements.schema_requirement) do
        []
      else
        [
          %{
            type: :schema,
            requirement: requirements.schema_requirement,
            actual: schema_version
          }
        ]
      end

    capability_mismatches =
      Enum.flat_map(requirements.required_capabilities, &capability_mismatch(&1, declared))

    case schema_mismatches ++ capability_mismatches do
      [] -> :ok
      mismatches -> {:error, mismatches}
    end
  end

  defp capability_mismatch(requirement, declared) do
    case Map.fetch(declared, requirement.id) do
      :error ->
        [
          %{
            type: :missing_capability,
            id: requirement.id,
            requirement: requirement.version_requirement
          }
        ]

      {:ok, actual} ->
        version_mismatch(requirement, actual)
    end
  end

  defp version_mismatch(requirement, actual) do
    if matches_requirement?(actual, requirement.version_requirement) do
      []
    else
      [
        %{
          type: :capability_version,
          id: requirement.id,
          requirement: requirement.version_requirement,
          actual: actual
        }
      ]
    end
  end

  @doc "Alias of `from_map/1` retained for the 0.1 constructor API."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(data), do: from_map(data)

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("schema_requirement", value.schema_requirement)
    |> Map.put(
      "required_capabilities",
      Enum.map(value.required_capabilities, &CapabilityRequirement.to_map/1)
    )
    |> Map.put("extensions", value.extensions)
  end

  defp unique_requirements(requirements) do
    ids = Enum.map(requirements, & &1.id)
    Validation.uniqueness(ids, "/required_capabilities")
  end

  defp matches_requirement?(version, requirement) do
    case Version.parse(version) do
      {:ok, parsed} -> Version.match?(parsed, requirement)
      :error -> false
    end
  end
end
