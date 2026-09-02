defmodule Wotex.Nx.Observation do
  @moduledoc """
  Immutable input or inert output observation.

  This extension value does not assert canonical Property state or Event truth.
  """

  alias Wotex.Nx.Error

  @qualities [:good, :uncertain, :bad, :missing]

  @opaque t :: %__MODULE__{
            id: String.t(),
            thing_id: String.t(),
            affordance_type: :property | :event,
            affordance_name: String.t(),
            observed_at: integer(),
            value: term(),
            unit: String.t() | nil,
            quality: atom(),
            source: String.t() | nil,
            metadata: map()
          }

  @enforce_keys [
    :id,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :observed_at,
    :value,
    :unit,
    :quality,
    :source,
    :metadata
  ]
  defstruct @enforce_keys

  @doc "Builds a typed observation from caller-supplied identity and time."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    observation = %{
      id: Keyword.get(opts, :id),
      thing_id: Keyword.get(opts, :thing_id),
      affordance_type: Keyword.get(opts, :affordance_type),
      affordance_name: Keyword.get(opts, :affordance_name),
      observed_at: Keyword.get(opts, :observed_at),
      value: Keyword.get(opts, :value),
      unit: Keyword.get(opts, :unit),
      quality: Keyword.get(opts, :quality, :good),
      source: Keyword.get(opts, :source),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    with :ok <- non_empty(observation.id, :id),
         :ok <- non_empty(observation.thing_id, :thing_id),
         :ok <- valid_type(observation.affordance_type),
         :ok <- non_empty(observation.affordance_name, :affordance_name),
         :ok <- valid_time(observation.observed_at),
         :ok <- optional_string(observation.unit, :unit),
         :ok <- valid_quality(observation.quality),
         :ok <- optional_string(observation.source, :source),
         :ok <- valid_metadata(observation.metadata) do
      {:ok, struct!(__MODULE__, observation)}
    end
  end

  def new(_opts) do
    {:error,
     Error.new(
       :invalid_observation_options,
       :construction,
       "observation options must be a keyword list"
     )}
  end

  @doc "Returns the stable set of supported quality states."
  @spec qualities() :: [atom()]
  def qualities, do: @qualities

  defp non_empty(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp non_empty(_value, field) do
    {:error,
     Error.new(
       :invalid_observation_field,
       :construction,
       "observation field must be a non-empty string",
       %{field: field}
     )}
  end

  defp valid_type(type) when type in [:property, :event], do: :ok

  defp valid_type(_type) do
    {:error,
     Error.new(
       :invalid_affordance_type,
       :construction,
       "observation affordance type must be property or event"
     )}
  end

  defp valid_time(time) when is_integer(time), do: :ok

  defp valid_time(_time),
    do: {:error, Error.new(:invalid_observed_at, :construction, "observed_at must be an integer")}

  defp optional_string(nil, _field), do: :ok
  defp optional_string(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp optional_string(_value, field) do
    {:error,
     Error.new(
       :invalid_observation_field,
       :construction,
       "optional observation field must be nil or a non-empty string",
       %{field: field}
     )}
  end

  defp valid_quality(quality) when quality in @qualities, do: :ok

  defp valid_quality(_quality),
    do: {:error, Error.new(:invalid_quality, :construction, "observation quality is unsupported")}

  defp valid_metadata(metadata) when is_map(metadata), do: :ok

  defp valid_metadata(_metadata),
    do: {:error, Error.new(:invalid_metadata, :construction, "observation metadata must be a map")}
end
