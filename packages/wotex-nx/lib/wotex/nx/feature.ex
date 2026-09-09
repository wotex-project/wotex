defmodule Wotex.Nx.Feature do
  @moduledoc """
  Defines one ordered numerical feature derived from a Wotex DataSchema.

  A feature binds a Thing affordance to an exact Nx shape and dtype together
  with unit, quality, missing-value, normalization, and non-finite policies.
  Construction rejects ambiguous or unsafe combinations before any observation
  can reach tensor allocation.

  `new/1` infers the fixed shape and compatible Nx data type from a validated
  `Wotex.DataSchema`, then checks any explicit overrides against that semantic
  shape. Identity fields bind the feature to one Thing Property or Event.
  Accepted quality states, unit conversion requirements, fill behavior, and
  finite-value policy remain part of the stored contract.

  During encoding, a `Wotex.Nx.Observation` must match this identity and policy
  before its value enters a tensor. `width/1` exposes the flattened allocation
  cost used by `Wotex.Nx.Schema`. A feature does not select a window, learn
  normalization statistics, or infer conversions from unit names.
  """

  alias Wotex.DataSchema
  alias Wotex.Nx.{Error, NumericalSchema, Observation, Options}

  @normalizations [:none]
  @options [
    :name,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :data_schema,
    :shape,
    :dtype,
    :accepted_quality,
    :missing,
    :normalization,
    :unit,
    :allow_non_finite?
  ]

  @typedoc "An affordance-bound numerical feature with explicit conversion and quality policy."
  @opaque t :: %__MODULE__{
            name: String.t(),
            thing_id: String.t(),
            affordance_type: :property | :event,
            affordance_name: String.t(),
            data_schema: DataSchema.t(),
            dtype: term(),
            shape: tuple(),
            unit: String.t() | nil,
            accepted_quality: MapSet.t(atom()),
            missing: :error | {:fill, number() | boolean()},
            normalization: :none | {:z_score, number(), number()} | {:min_max, number(), number()},
            allow_non_finite?: boolean()
          }

  @enforce_keys [
    :name,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :data_schema,
    :dtype,
    :shape,
    :unit,
    :accepted_quality,
    :missing,
    :normalization,
    :allow_non_finite?
  ]
  defstruct @enforce_keys

  @doc """
  Builds a feature from an exact DataSchema and explicit numerical policy.

  Required options identify the feature, Thing, affordance type and name, and
  DataSchema. Optional shape and dtype must remain compatible with that schema.
  Unit, accepted quality, missing-value, normalization, and non-finite policies
  are validated and stored rather than inferred while encoding.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @options, :invalid_feature_options, :construction) do
      build(opts)
    end
  end

  def new(_) do
    {:error,
     Error.new(:invalid_feature_options, :construction, "feature options must be a keyword list")}
  end

  defp build(opts) do
    data_schema = Keyword.get(opts, :data_schema)

    with %DataSchema{} <- data_schema,
         map <- DataSchema.to_map(data_schema),
         {:ok, inferred_shape, inferred_dtype} <- NumericalSchema.infer(map),
         shape <- Keyword.get(opts, :shape, inferred_shape),
         dtype <- Keyword.get(opts, :dtype, inferred_dtype),
         {:ok, normalized_dtype} <- NumericalSchema.normalize_dtype(dtype, shape),
         :ok <- validate_shape(shape, inferred_shape),
         :ok <- NumericalSchema.validate_dtype(map, normalized_dtype),
         :ok <- validate_identity(opts),
         {:ok, accepted_quality} <- accepted_quality(opts),
         {:ok, missing} <- missing_policy(Keyword.get(opts, :missing, :error)),
         {:ok, normalization} <- normalization(Keyword.get(opts, :normalization, :none)),
         :ok <- NumericalSchema.validate_normalization(normalization, normalized_dtype),
         {:ok, unit} <- unit(Keyword.get(opts, :unit, Map.get(map, "unit"))),
         {:ok, allow_non_finite?} <-
           boolean_policy(Keyword.get(opts, :allow_non_finite?, false)) do
      {:ok,
       %__MODULE__{
         name: Keyword.fetch!(opts, :name),
         thing_id: Keyword.fetch!(opts, :thing_id),
         affordance_type: Keyword.fetch!(opts, :affordance_type),
         affordance_name: Keyword.fetch!(opts, :affordance_name),
         data_schema: data_schema,
         dtype: normalized_dtype,
         shape: shape,
         unit: unit,
         accepted_quality: accepted_quality,
         missing: missing,
         normalization: normalization,
         allow_non_finite?: allow_non_finite?
       }}
    else
      nil ->
        {:error,
         Error.new(:data_schema_required, :construction, "feature requires a Wotex DataSchema")}

      false ->
        {:error,
         Error.new(:data_schema_required, :construction, "feature requires a Wotex DataSchema")}

      {:error, %Error{} = error} ->
        {:error, error}

      _ ->
        {:error,
         Error.new(
           :data_schema_required,
           :construction,
           "feature requires a Wotex DataSchema"
         )}
    end
  end

  @doc "Returns the flattened numerical width used for pre-allocation limits."
  @spec width(t()) :: pos_integer()
  def width(%__MODULE__{shape: shape}), do: NumericalSchema.width(shape)

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = feature) do
    options = [
      name: feature.name,
      thing_id: feature.thing_id,
      affordance_type: feature.affordance_type,
      affordance_name: feature.affordance_name,
      data_schema: feature.data_schema,
      dtype: feature.dtype,
      shape: feature.shape,
      unit: feature.unit,
      accepted_quality: MapSet.to_list(feature.accepted_quality),
      missing: feature.missing,
      normalization: feature.normalization,
      allow_non_finite?: feature.allow_non_finite?
    ]

    new(options) == {:ok, feature}
  rescue
    _ in [ArgumentError, FunctionClauseError] -> false
  end

  def valid?(_), do: false

  defp validate_shape(shape, shape) when is_tuple(shape), do: :ok

  defp validate_shape(_, _) do
    {:error,
     Error.new(
       :shape_schema_mismatch,
       :construction,
       "feature shape must match the fixed DataSchema shape"
     )}
  end

  defp validate_identity(opts) do
    name = Keyword.get(opts, :name)
    thing_id = Keyword.get(opts, :thing_id)
    type = Keyword.get(opts, :affordance_type)
    affordance_name = Keyword.get(opts, :affordance_name)

    if is_binary(name) and byte_size(name) > 0 and is_binary(thing_id) and
         byte_size(thing_id) > 0 and type in [:property, :event] and
         is_binary(affordance_name) and byte_size(affordance_name) > 0 do
      :ok
    else
      {:error, Error.new(:invalid_feature_identity, :construction, "feature identity is invalid")}
    end
  end

  defp accepted_quality(opts) do
    qualities = Keyword.get(opts, :accepted_quality, [:good, :uncertain])

    if is_list(qualities) and qualities != [] and
         Enum.all?(qualities, &(&1 in Observation.qualities())) do
      {:ok, MapSet.new(qualities)}
    else
      {:error,
       Error.new(
         :invalid_accepted_quality,
         :construction,
         "accepted quality must be a non-empty quality list"
       )}
    end
  end

  defp missing_policy(:error), do: {:ok, :error}

  defp missing_policy({:fill, value}) when is_number(value) or is_boolean(value),
    do: {:ok, {:fill, value}}

  defp missing_policy(_),
    do:
      {:error,
       Error.new(
         :invalid_missing_policy,
         :construction,
         "missing policy must be :error or {:fill, value}"
       )}

  defp normalization(value) when value in @normalizations, do: {:ok, value}

  defp normalization({:z_score, mean, stddev})
       when is_number(mean) and is_number(stddev) and stddev > 0,
       do: {:ok, {:z_score, mean, stddev}}

  defp normalization({:min_max, minimum, maximum})
       when is_number(minimum) and is_number(maximum) and maximum > minimum,
       do: {:ok, {:min_max, minimum, maximum}}

  defp normalization(_),
    do:
      {:error,
       Error.new(:invalid_normalization, :construction, "normalization parameters are invalid")}

  defp unit(nil), do: {:ok, nil}
  defp unit(value) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}

  defp unit(_),
    do:
      {:error,
       Error.new(:invalid_unit, :construction, "feature unit must be nil or a non-empty string")}

  defp boolean_policy(value) when is_boolean(value), do: {:ok, value}

  defp boolean_policy(_) do
    {:error,
     Error.new(
       :invalid_finite_policy,
       :construction,
       "allow_non_finite? must be boolean"
     )}
  end
end
