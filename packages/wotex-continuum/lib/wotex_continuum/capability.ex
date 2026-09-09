defmodule WotexContinuum.Capability do
  @moduledoc """
  A mechanical declaration of operations available in deployment modes.

  A capability names its versioned operation set, supported modes, network
  requirement, and degradation behavior. Manifests use these declarations for
  deterministic compatibility checks before composition.

  Declaration is descriptive, not authoritative: it grants no permission and
  invokes no operation.

  `from_map/1` validates the capability identifier and semantic version, a
  unique operation list, which may be empty, supported deployment modes, required network class,
  degradation behavior, and namespaced extensions. `to_map/1` emits the common
  continuum envelope with deterministic string representations of enumerated
  values.

  Compatibility compares these declarations with explicit requirements. It
  does not inspect a module, start a provider, test an operation, or infer
  authorization. The consumer remains responsible for establishing that a
  concrete implementation matches the declaration and for enforcing its
  network and degradation policy.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, Mode, Validation}

  @kind "capability"
  @networks [:none, :local, :external]
  @degradations [:fail_closed, :read_only, :queue, :unavailable]

  @enforce_keys [:id, :version, :operations, :modes, :network, :degradation]
  defstruct [:id, :version, :operations, :modes, :network, :degradation, extensions: %{}]

  @type network :: :none | :local | :external
  @type degradation :: :fail_closed | :read_only | :queue | :unavailable
  @type t :: %__MODULE__{
          id: String.t(),
          version: String.t(),
          operations: [String.t()],
          modes: [Mode.deployment()],
          network: network(),
          degradation: degradation(),
          extensions: map()
        }

  @impl WotexContinuum.Value
  def kind, do: @kind

  @impl WotexContinuum.Value
  def from_map(%__MODULE__{} = value), do: from_map(Map.from_struct(value))

  def from_map(data) do
    fields = [:id, :version, :operations, :modes, :network, :degradation, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, id} <- Validation.required(data, :id),
         {:ok, id} <- Validation.string(id, "/id"),
         {:ok, version} <- Validation.required(data, :version),
         {:ok, version} <- Validation.semver(version, "/version"),
         {:ok, operations} <- Validation.required(data, :operations),
         {:ok, operations} <- Validation.string_list(operations, "/operations"),
         {:ok, modes} <- Validation.required(data, :modes),
         {:ok, modes} <- Validation.enum_list(modes, "/modes", Mode.deployments(), min: 1),
         {:ok, network} <- Validation.required(data, :network),
         {:ok, network} <- Validation.enum(network, "/network", @networks),
         {:ok, degradation} <- Validation.required(data, :degradation),
         {:ok, degradation} <-
           Validation.enum(degradation, "/degradation", @degradations),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), "/extensions") do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         operations: operations,
         modes: modes,
         network: network,
         degradation: degradation,
         extensions: extensions
       }}
    end
  end

  @doc "Alias of `from_map/1` retained for the 0.1 constructor API."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(data), do: from_map(data)

  @impl WotexContinuum.Value
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("id", value.id)
    |> Map.put("version", value.version)
    |> Map.put("operations", value.operations)
    |> Map.put("modes", Enum.map(value.modes, &Atom.to_string/1))
    |> Map.put("network", Atom.to_string(value.network))
    |> Map.put("degradation", Atom.to_string(value.degradation))
    |> Map.put("extensions", value.extensions)
  end
end
