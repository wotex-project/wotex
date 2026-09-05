defmodule WotexContinuum.Mode do
  @moduledoc """
  Deployment placement paired with observed upstream connectivity.

  Placement and connectivity are separate because connected on-premises or
  hybrid systems can become intermittent, while air-gapped placement must
  remain disconnected. The explicit value lets other contracts describe
  degradation and lifecycle without consulting global configuration.

  Mode reports where execution occurs; it does not select a provider or
  establish a network connection.
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

  @impl WotexContinuum.Value
  def kind, do: @kind

  @doc "Returns the supported deployment values."
  @spec deployments() :: nonempty_list(deployment())
  def deployments, do: @deployments

  @doc "Returns the supported connectivity values."
  @spec connectivity_states() :: nonempty_list(connectivity())
  def connectivity_states, do: @connectivity_states

  @impl WotexContinuum.Value
  def new(%__MODULE__{} = value), do: new(Map.from_struct(value))

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

  @impl WotexContinuum.Value
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

  defp validate_air_gap(_, _), do: :ok
end
