defmodule Wotex.Nx.Observation do
  @moduledoc """
  An immutable input or inert output observation.

  The value binds a caller-defined identity and time coordinate to one Property
  or Event affordance value, optional unit, quality, source, and metadata. It is
  suitable for deterministic window selection and tensor encoding, but does not
  assert canonical Property state or Event truth.
  """

  alias Wotex.Nx.{Error, Options}

  @qualities [:good, :uncertain, :bad, :missing]
  @options [
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

  @typedoc "Quality carried by an accepted observation."
  @type quality :: :good | :uncertain | :bad | :missing

  @typedoc "An affordance-scoped value with caller-owned time, quality, and provenance."
  @opaque t :: %__MODULE__{
            id: String.t(),
            thing_id: String.t(),
            affordance_type: :property | :event,
            affordance_name: String.t(),
            observed_at: integer(),
            value: term(),
            unit: String.t() | nil,
            quality: quality(),
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

  @doc """
  Builds an observation from caller-supplied identity, time, and value.

  IDs and affordance names must be non-empty strings, the affordance type must
  be `:property` or `:event`, and the time coordinate must be an integer. The
  constructor validates metadata and quality but does not validate the value
  against a numerical schema; that occurs during feature encoding.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @options, :invalid_observation_options, :construction) do
      build(opts)
    end
  end

  def new(_) do
    {:error,
     Error.new(
       :invalid_observation_options,
       :construction,
       "observation options must be a keyword list"
     )}
  end

  defp build(opts) do
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

    with :ok <- required_value(opts),
         :ok <- non_empty(observation.id, :id),
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

  @doc "Returns the stable quality states accepted by observations and features."
  @spec qualities() :: nonempty_list(quality())
  def qualities, do: @qualities

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = observation) do
    options =
      observation
      |> Map.from_struct()
      |> Map.to_list()

    new(options) == {:ok, observation}
  end

  def valid?(_), do: false

  defp required_value(opts) do
    if Keyword.has_key?(opts, :value),
      do: :ok,
      else:
        {:error,
         Error.new(
           :invalid_observation_field,
           :construction,
           "observation value must be explicitly supplied",
           %{field: :value}
         )}
  end

  defp non_empty(value, _) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp non_empty(_, field) do
    {:error,
     Error.new(
       :invalid_observation_field,
       :construction,
       "observation field must be a non-empty string",
       %{field: field}
     )}
  end

  defp valid_type(type) when type in [:property, :event], do: :ok

  defp valid_type(_) do
    {:error,
     Error.new(
       :invalid_affordance_type,
       :construction,
       "observation affordance type must be property or event"
     )}
  end

  defp valid_time(time) when is_integer(time), do: :ok

  defp valid_time(_),
    do: {:error, Error.new(:invalid_observed_at, :construction, "observed_at must be an integer")}

  defp optional_string(nil, _), do: :ok
  defp optional_string(value, _) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp optional_string(_, field) do
    {:error,
     Error.new(
       :invalid_observation_field,
       :construction,
       "optional observation field must be nil or a non-empty string",
       %{field: field}
     )}
  end

  defp valid_quality(quality) when quality in @qualities, do: :ok

  defp valid_quality(_),
    do: {:error, Error.new(:invalid_quality, :construction, "observation quality is unsupported")}

  defp valid_metadata(metadata) when is_map(metadata), do: :ok

  defp valid_metadata(_),
    do: {:error, Error.new(:invalid_metadata, :construction, "observation metadata must be a map")}

  @doc "Returns the observation fields as a plain map; a read-only view, not an admission boundary."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Map.from_struct(value)
end
