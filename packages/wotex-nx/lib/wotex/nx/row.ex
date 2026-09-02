defmodule Wotex.Nx.Row do
  @moduledoc "Immutable temporal row selected for numerical encoding."

  alias Wotex.Nx.{Error, Observation}

  @opaque t :: %__MODULE__{
            timestamp: integer(),
            observations: %{String.t() => Observation.t() | nil},
            provenance: %{String.t() => String.t() | nil}
          }

  @enforce_keys [:timestamp, :observations, :provenance]
  defstruct @enforce_keys

  @doc "Builds a row with feature-name keyed observations."
  @spec new(integer(), map()) :: {:ok, t()} | {:error, Error.t()}
  def new(timestamp, observations) when is_integer(timestamp) and is_map(observations) do
    if Enum.all?(observations, fn
         {name, %Observation{}} when is_binary(name) -> true
         {name, nil} when is_binary(name) -> true
         _entry -> false
       end) do
      provenance =
        Map.new(observations, fn
          {name, %Observation{id: id}} -> {name, id}
          {name, nil} -> {name, nil}
        end)

      {:ok, %__MODULE__{timestamp: timestamp, observations: observations, provenance: provenance}}
    else
      {:error,
       Error.new(
         :invalid_row_observations,
         :construction,
         "row observations must map feature names to observations or nil"
       )}
    end
  end

  def new(_timestamp, _observations),
    do:
      {:error,
       Error.new(
         :invalid_row,
         :construction,
         "row requires an integer timestamp and observation map"
       )}
end
