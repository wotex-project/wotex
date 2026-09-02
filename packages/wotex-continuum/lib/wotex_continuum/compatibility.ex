defmodule WotexContinuum.Compatibility do
  @moduledoc """
  Pure schema and capability compatibility requirements.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Capability, CapabilityRequirement, Contract, Validation}

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

  @impl true
  def kind, do: @kind

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:schema_requirement, :required_capabilities, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, requirement} <- Validation.required(data, :schema_requirement),
         {:ok, requirement} <-
           Validation.version_requirement(requirement, ["schema_requirement"]),
         {:ok, capabilities} <-
           Validation.structs(
             Map.get(data, :required_capabilities, []),
             ["required_capabilities"],
             CapabilityRequirement
           ),
         :ok <- unique_requirements(capabilities),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
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
      Enum.flat_map(requirements.required_capabilities, fn requirement ->
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
      end)

    case schema_mismatches ++ capability_mismatches do
      [] -> :ok
      mismatches -> {:error, mismatches}
    end
  end

  @impl true
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
    Validation.uniqueness(ids, ["required_capabilities"])
  end

  defp matches_requirement?(version, requirement) do
    case Version.parse(version) do
      {:ok, parsed} -> Version.match?(parsed, requirement)
      :error -> false
    end
  end
end
