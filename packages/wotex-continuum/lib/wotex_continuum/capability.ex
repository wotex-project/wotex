defmodule WotexContinuum.Capability do
  @moduledoc """
  Mechanical capability declaration.

  Declaration does not grant permission to use an operation.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Mode, Validation}

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

  @impl true
  def kind, do: @kind

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:id, :version, :operations, :modes, :network, :degradation, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, id} <- Validation.required(data, :id),
         {:ok, id} <- Validation.string(id, ["id"]),
         {:ok, version} <- Validation.required(data, :version),
         {:ok, version} <- Validation.semver(version, ["version"]),
         {:ok, operations} <- Validation.required(data, :operations),
         {:ok, operations} <- Validation.string_list(operations, ["operations"]),
         {:ok, modes} <- Validation.required(data, :modes),
         {:ok, modes} <- Validation.enum_list(modes, ["modes"], Mode.deployments(), min: 1),
         {:ok, network} <- Validation.required(data, :network),
         {:ok, network} <- Validation.enum(network, ["network"], @networks),
         {:ok, degradation} <- Validation.required(data, :degradation),
         {:ok, degradation} <-
           Validation.enum(degradation, ["degradation"], @degradations),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
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

  @impl true
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
