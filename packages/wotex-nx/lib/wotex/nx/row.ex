defmodule Wotex.Nx.Row do
  @moduledoc """
  A timestamped row keyed by accepted feature names.

  Each entry contains either the selected `Wotex.Nx.Observation` or `nil` so
  the encoder can apply the feature's explicit missing-value policy. The row
  also records source observation identifiers as provenance.
  """

  alias Wotex.Nx.{Error, Observation}

  @typedoc "A timestamp, feature-keyed observations, and their source identifiers."
  @opaque t :: %__MODULE__{
            timestamp: integer(),
            observations: %{String.t() => Observation.t() | nil},
            provenance: %{String.t() => String.t() | nil}
          }

  @enforce_keys [:timestamp, :observations, :provenance]
  defstruct @enforce_keys

  @doc """
  Builds a row from an integer timestamp and feature-name keyed observations.

  Values must be `Wotex.Nx.Observation` structs or `nil`. The constructor
  derives the provenance map from observation IDs and rejects all other values.
  """
  @spec new(integer(), map()) :: {:ok, t()} | {:error, Error.t()}
  def new(timestamp, observations) when is_integer(timestamp) and is_map(observations) do
    if Enum.all?(observations, fn
         {name, %Observation{}} when is_binary(name) -> true
         {name, nil} when is_binary(name) -> true
         _ -> false
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

  def new(_, _),
    do:
      {:error,
       Error.new(
         :invalid_row,
         :construction,
         "row requires an integer timestamp and observation map"
       )}
end
