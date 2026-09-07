defmodule Wotex.Nx.OutputSchema do
  @moduledoc """
  Defines the only numerical output a decoder is allowed to accept.

  The contract binds an output kind and Thing affordance to an exact DataSchema,
  shape, dtype, maximum width, unit, finite-value policy, and metadata. Anomaly
  outputs additionally preserve their threshold and comparison rule. This
  removes model-specific guesswork from result interpretation.
  """

  alias Wotex.DataSchema
  alias Wotex.Nx.{Error, NumericalSchema, Options}

  @kinds [:observation, :prediction, :anomaly, :action_proposal]
  @options [
    :kind,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :data_schema,
    :shape,
    :dtype,
    :max_width,
    :unit,
    :threshold,
    :anomaly_rule,
    :metadata,
    :allow_non_finite?
  ]

  @typedoc "Inert result kind produced by numerical decoding."
  @type kind :: :observation | :prediction | :anomaly | :action_proposal

  @typedoc "A bounded numerical output contract for one inert result kind."
  @opaque t :: %__MODULE__{
            kind: kind(),
            thing_id: String.t(),
            affordance_type: :property | :event | :action,
            affordance_name: String.t(),
            data_schema: DataSchema.t(),
            dtype: Nx.Type.t(),
            shape: tuple(),
            max_width: pos_integer(),
            unit: String.t() | nil,
            allow_non_finite?: boolean(),
            threshold: number() | nil,
            anomaly_rule: :above | :at_or_above | :below | :at_or_below | nil,
            metadata: map()
          }

  @enforce_keys [
    :kind,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :data_schema,
    :dtype,
    :shape,
    :max_width,
    :unit,
    :allow_non_finite?,
    :threshold,
    :anomaly_rule,
    :metadata
  ]
  defstruct @enforce_keys

  @doc """
  Builds and validates an explicit numerical-output contract.

  Required identity and kind options are checked against the DataSchema.
  Shape and dtype must preserve its value category, maximum width is enforced
  before allocation, and anomaly policy is accepted only for anomaly outputs.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <-
           Options.validate(opts, @options, :invalid_output_schema_options, :construction) do
      build(opts)
    end
  end

  def new(_) do
    {:error,
     Error.new(
       :invalid_output_schema_options,
       :construction,
       "output schema options must be a keyword list"
     )}
  end

  defp build(opts) do
    data_schema = Keyword.get(opts, :data_schema)

    with %DataSchema{} <- data_schema,
         map <- DataSchema.to_map(data_schema),
         {:ok, inferred_shape, inferred_dtype} <- NumericalSchema.infer(map),
         shape <- Keyword.get(opts, :shape, inferred_shape),
         dtype <- Keyword.get(opts, :dtype, inferred_dtype),
         max_width <- Keyword.get(opts, :max_width, 65_536),
         {:ok, normalized_dtype} <- NumericalSchema.normalize_dtype(dtype, shape),
         :ok <- exact_shape(shape, inferred_shape),
         :ok <- NumericalSchema.validate_dtype(map, normalized_dtype),
         :ok <- width(inferred_shape, max_width),
         {:ok, identity} <- identity(opts),
         :ok <- kind_schema(identity.kind, map, inferred_shape),
         {:ok, unit} <- unit(Keyword.get(opts, :unit, Map.get(map, "unit"))),
         {:ok, threshold} <-
           threshold(identity.kind, Keyword.get(opts, :threshold), normalized_dtype),
         {:ok, anomaly_rule} <-
           anomaly_rule(identity.kind, Keyword.get(opts, :anomaly_rule)),
         {:ok, metadata} <- metadata(Keyword.get(opts, :metadata, %{})),
         {:ok, allow_non_finite?} <-
           boolean_policy(Keyword.get(opts, :allow_non_finite?, false)),
         :ok <- finite_kind(identity.kind, allow_non_finite?) do
      {:ok,
       struct!(
         __MODULE__,
         Map.merge(identity, %{
           data_schema: data_schema,
           dtype: normalized_dtype,
           shape: shape,
           max_width: max_width,
           unit: unit,
           allow_non_finite?: allow_non_finite?,
           threshold: threshold,
           anomaly_rule: anomaly_rule,
           metadata: metadata
         })
       )}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      _ ->
        {:error,
         Error.new(
           :data_schema_required,
           :construction,
           "output schema requires a Wotex DataSchema"
         )}
    end
  end

  @doc "Returns the stable inert output kinds accepted by the decoder."
  @spec kinds() :: nonempty_list(kind())
  def kinds, do: @kinds

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = schema) do
    options = [
      kind: schema.kind,
      thing_id: schema.thing_id,
      affordance_type: schema.affordance_type,
      affordance_name: schema.affordance_name,
      data_schema: schema.data_schema,
      dtype: schema.dtype,
      shape: schema.shape,
      max_width: schema.max_width,
      unit: schema.unit,
      threshold: schema.threshold,
      anomaly_rule: schema.anomaly_rule,
      metadata: schema.metadata,
      allow_non_finite?: schema.allow_non_finite?
    ]

    new(options) == {:ok, schema}
  rescue
    _ in [ArgumentError, FunctionClauseError] -> false
  end

  def valid?(_), do: false

  defp identity(opts) do
    kind = Keyword.get(opts, :kind)
    thing_id = Keyword.get(opts, :thing_id)
    affordance_type = Keyword.get(opts, :affordance_type)
    affordance_name = Keyword.get(opts, :affordance_name)

    if kind in @kinds and non_empty?(thing_id) and non_empty?(affordance_name) and
         valid_affordance?(kind, affordance_type) do
      {:ok,
       %{
         kind: kind,
         thing_id: thing_id,
         affordance_type: affordance_type,
         affordance_name: affordance_name
       }}
    else
      {:error,
       Error.new(
         :invalid_output_identity,
         :construction,
         "output kind and Thing affordance identity are invalid"
       )}
    end
  end

  defp valid_affordance?(:action_proposal, :action), do: true

  defp valid_affordance?(kind, type)
       when kind in [:observation, :prediction, :anomaly] and type in [:property, :event],
       do: true

  defp valid_affordance?(_, _), do: false

  defp exact_shape(shape, shape) when is_tuple(shape), do: :ok

  defp exact_shape(_, _) do
    {:error,
     Error.new(
       :shape_schema_mismatch,
       :construction,
       "output shape must match the fixed DataSchema shape"
     )}
  end

  defp kind_schema(:anomaly, %{"type" => type}, {}) when type in ["number", "integer"],
    do: :ok

  defp kind_schema(:anomaly, _, _) do
    {:error,
     Error.new(
       :invalid_anomaly_schema,
       :construction,
       "anomaly output requires a scalar numerical DataSchema"
     )}
  end

  defp kind_schema(_, _, _), do: :ok

  defp width(shape, max_width) when is_integer(max_width) and max_width > 0 do
    if NumericalSchema.width(shape) <= max_width do
      :ok
    else
      {:error,
       Error.new(
         :width_limit_exceeded,
         :limit,
         "output schema exceeds max_width",
         %{max_width: max_width}
       )}
    end
  end

  defp width(_, _) do
    {:error,
     Error.new(
       :invalid_limit,
       :construction,
       "output max_width must be positive"
     )}
  end

  defp unit(nil), do: {:ok, nil}
  defp unit(value) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}

  defp unit(_) do
    {:error,
     Error.new(
       :invalid_unit,
       :construction,
       "output unit must be nil or a non-empty string"
     )}
  end

  defp threshold(:anomaly, value, {:f, 64}) when is_number(value), do: {:ok, value * 1.0}

  defp threshold(:anomaly, value, {:f, 32}) when is_number(value) do
    case <<value * 1.0::float-32>> do
      <<rounded::float-32>> -> {:ok, rounded}
      _ -> invalid_threshold()
    end
  end

  defp threshold(:anomaly, value, dtype) when is_number(value) do
    converted =
      value
      |> Nx.tensor(type: dtype)
      |> Nx.to_number()

    if is_number(converted) do
      {:ok, converted}
    else
      invalid_threshold()
    end
  rescue
    _ in [ArgumentError, RuntimeError, FunctionClauseError] ->
      invalid_threshold()
  end

  defp threshold(:anomaly, _, _),
    do:
      {:error,
       Error.new(
         :threshold_required,
         :construction,
         "anomaly output requires a numerical threshold"
       )}

  defp threshold(_, nil, _), do: {:ok, nil}

  defp threshold(_, _, _),
    do:
      {:error,
       Error.new(:unexpected_threshold, :construction, "threshold is valid only for anomaly output")}

  defp anomaly_rule(:anomaly, nil), do: {:ok, :at_or_above}

  defp anomaly_rule(:anomaly, value)
       when value in [:above, :at_or_above, :below, :at_or_below],
       do: {:ok, value}

  defp anomaly_rule(:anomaly, _) do
    {:error,
     Error.new(
       :invalid_anomaly_rule,
       :construction,
       "anomaly rule is unsupported"
     )}
  end

  defp anomaly_rule(_, nil), do: {:ok, nil}

  defp anomaly_rule(_, _) do
    {:error,
     Error.new(
       :unexpected_anomaly_rule,
       :construction,
       "anomaly rule is valid only for anomaly output"
     )}
  end

  defp invalid_threshold do
    {:error,
     Error.new(
       :invalid_threshold,
       :construction,
       "anomaly threshold cannot be represented by the output dtype"
     )}
  end

  defp metadata(value) when is_map(value), do: {:ok, value}

  defp metadata(_),
    do: {:error, Error.new(:invalid_metadata, :construction, "output metadata must be a map")}

  defp boolean_policy(value) when is_boolean(value), do: {:ok, value}

  defp boolean_policy(_) do
    {:error,
     Error.new(
       :invalid_finite_policy,
       :construction,
       "allow_non_finite? must be boolean"
     )}
  end

  defp finite_kind(:anomaly, true) do
    {:error,
     Error.new(
       :non_finite_anomaly_unsupported,
       :construction,
       "anomaly output must require finite scores"
     )}
  end

  defp finite_kind(_, _), do: :ok

  defp non_empty?(value), do: is_binary(value) and byte_size(value) > 0
end
