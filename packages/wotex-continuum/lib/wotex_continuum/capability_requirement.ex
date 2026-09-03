defmodule WotexContinuum.CapabilityRequirement do
  @moduledoc """
  A capability identity paired with an Elixir semantic-version requirement.

  Compatibility values use this nested contract to state what a consumer must
  provide. Parsing proves requirement syntax only; it does not locate, load, or
  authorize an implementation.
  """

  alias WotexContinuum.{Error, Validation}

  @enforce_keys [:id, :version_requirement]
  defstruct [:id, :version_requirement]

  @type t :: %__MODULE__{id: String.t(), version_requirement: String.t()}

  @doc "Constructs a capability requirement."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    with {:ok, data} <- Validation.normalize(data, [:id, :version_requirement]),
         {:ok, id} <- Validation.required(data, :id),
         {:ok, id} <- Validation.string(id, ["id"]),
         {:ok, requirement} <- Validation.required(data, :version_requirement),
         {:ok, requirement} <-
           Validation.version_requirement(requirement, ["version_requirement"]) do
      {:ok, %__MODULE__{id: id, version_requirement: requirement}}
    end
  end

  @doc "Returns the wire map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{"id" => value.id, "version_requirement" => value.version_requirement}
  end
end
