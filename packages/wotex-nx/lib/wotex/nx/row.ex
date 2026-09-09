defmodule Wotex.Nx.Row do
  @moduledoc """
  A timestamped row keyed by caller-supplied feature names.

  Each entry contains either the selected `Wotex.Nx.Observation` or `nil` so
  the encoder can apply the feature's explicit missing-value policy. The row
  also records source observation identifiers as provenance.

  Row keys identify features for later encoding with a `Wotex.Nx.Schema`. The constructor accepts
  valid observations and explicit absence, then derives an equally keyed
  provenance map from observation IDs. It does not choose observations,
  interpolate values, convert units, or fill missing features.

  The integer timestamp is a caller-defined coordinate and is not read from a
  system clock. Window selection establishes the row's temporal membership;
  encoding later checks feature identity, quality, units, value constraints,
  and missing policy before allocating tensor data.
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
    if Enum.all?(observations, &valid_observation_entry?/1) do
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

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = row) do
    new(row.timestamp, row.observations) == {:ok, row}
  end

  def valid?(_), do: false

  defp valid_observation_entry?({name, %Observation{} = observation}) when is_binary(name),
    do: Observation.valid?(observation)

  defp valid_observation_entry?({name, nil}) when is_binary(name), do: true
  defp valid_observation_entry?(_), do: false
end
