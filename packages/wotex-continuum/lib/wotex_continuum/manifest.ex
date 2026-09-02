defmodule WotexContinuum.Manifest do
  @moduledoc """
  Immutable continuum manifest value.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Artifact, Capability, Compatibility, Contract, Error, Mode, Validation}

  @kind "continuum_manifest"

  @enforce_keys [:manifest_id, :artifact, :compatibility, :supported_modes, :capabilities]
  defstruct [
    :manifest_id,
    :artifact,
    :compatibility,
    :supported_modes,
    :capabilities,
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          manifest_id: String.t(),
          artifact: Artifact.t(),
          compatibility: Compatibility.t(),
          supported_modes: [Mode.deployment()],
          capabilities: [Capability.t()],
          extensions: map()
        }

  @impl true
  def kind, do: @kind

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:manifest_id, :artifact, :compatibility, :supported_modes, :capabilities, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, manifest_id} <- Validation.required(data, :manifest_id),
         {:ok, manifest_id} <- Validation.string(manifest_id, ["manifest_id"]),
         {:ok, artifact} <- Validation.required(data, :artifact),
         {:ok, artifact} <- Validation.nested(artifact, ["artifact"], Artifact),
         {:ok, compatibility} <- Validation.required(data, :compatibility),
         {:ok, compatibility} <-
           Validation.nested(compatibility, ["compatibility"], Compatibility),
         {:ok, modes} <- Validation.required(data, :supported_modes),
         {:ok, modes} <-
           Validation.enum_list(modes, ["supported_modes"], Mode.deployments(), min: 1),
         {:ok, capabilities} <- Validation.required(data, :capabilities),
         {:ok, capabilities} <- Validation.structs(capabilities, ["capabilities"], Capability),
         :ok <- unique_capabilities(capabilities),
         :ok <- capabilities_fit_modes(capabilities, modes),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok,
       %__MODULE__{
         manifest_id: manifest_id,
         artifact: artifact,
         compatibility: compatibility,
         supported_modes: modes,
         capabilities: capabilities,
         extensions: extensions
       }}
    end
  end

  @doc "Evaluates the manifest requirements against consumer capabilities."
  @spec compatible_with?(t(), String.t(), [Capability.t()]) ::
          :ok | {:error, [Compatibility.mismatch()]}
  def compatible_with?(%__MODULE__{} = manifest, schema_version, capabilities) do
    Compatibility.evaluate(manifest.compatibility, schema_version, capabilities)
  end

  @impl true
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("manifest_id", value.manifest_id)
    |> Map.put("artifact", Artifact.to_map(value.artifact))
    |> Map.put("compatibility", Compatibility.to_map(value.compatibility))
    |> Map.put("supported_modes", Enum.map(value.supported_modes, &Atom.to_string/1))
    |> Map.put("capabilities", Enum.map(value.capabilities, &Capability.to_map/1))
    |> Map.put("extensions", value.extensions)
  end

  defp unique_capabilities(capabilities) do
    capabilities
    |> Enum.map(& &1.id)
    |> Validation.uniqueness(["capabilities"])
  end

  defp capabilities_fit_modes(capabilities, modes) do
    case Enum.find(capabilities, fn capability ->
           not Enum.all?(capability.modes, &(&1 in modes))
         end) do
      nil ->
        :ok

      capability ->
        Error.error(
          :unsupported_capability_mode,
          ["capabilities"],
          "capability declares a mode not supported by the manifest",
          %{capability: capability.id}
        )
    end
  end
end
