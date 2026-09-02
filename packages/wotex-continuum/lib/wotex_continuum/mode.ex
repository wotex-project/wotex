defmodule WotexContinuum.Mode do
  @moduledoc """
  Deployment placement and current upstream-connectivity value.
  """

  @behaviour WotexContinuum.Value

  alias WotexContinuum.{Contract, Error, Validation}

  @deployments [:saas, :hybrid, :connected_onprem, :air_gapped]
  @connectivity_states [:connected, :intermittent, :disconnected]
  @kind "mode"

  @enforce_keys [:deployment, :connectivity]
  defstruct [:deployment, :connectivity, extensions: %{}]

  @type deployment :: :saas | :hybrid | :connected_onprem | :air_gapped
  @type connectivity :: :connected | :intermittent | :disconnected
  @type t :: %__MODULE__{deployment: deployment(), connectivity: connectivity(), extensions: map()}

  @impl true
  def kind, do: @kind

  @doc "Returns the supported deployment values."
  @spec deployments() :: [deployment()]
  def deployments, do: @deployments

  @doc "Returns the supported connectivity values."
  @spec connectivity_states() :: [connectivity()]
  def connectivity_states, do: @connectivity_states

  @impl true
  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(data) do
    fields = [:deployment, :connectivity, :extensions]

    with {:ok, data} <- Contract.normalize(Contract.envelope(data, @kind), fields, @kind),
         {:ok, deployment} <- Validation.required(data, :deployment),
         {:ok, deployment} <- Validation.enum(deployment, ["deployment"], @deployments),
         {:ok, connectivity} <- Validation.required(data, :connectivity),
         {:ok, connectivity} <-
           Validation.enum(connectivity, ["connectivity"], @connectivity_states),
         :ok <- validate_air_gap(deployment, connectivity),
         {:ok, extensions} <- Validation.extensions(Map.get(data, :extensions, %{}), ["extensions"]) do
      {:ok, %__MODULE__{deployment: deployment, connectivity: connectivity, extensions: extensions}}
    end
  end

  @impl true
  def to_map(%__MODULE__{} = value) do
    Contract.base(@kind)
    |> Map.put("deployment", Atom.to_string(value.deployment))
    |> Map.put("connectivity", Atom.to_string(value.connectivity))
    |> Map.put("extensions", value.extensions)
  end

  defp validate_air_gap(:air_gapped, connectivity) when connectivity != :disconnected do
    Error.error(
      :invalid_mode,
      ["connectivity"],
      "air-gapped deployment requires disconnected upstream connectivity"
    )
  end

  defp validate_air_gap(_deployment, _connectivity), do: :ok
end
