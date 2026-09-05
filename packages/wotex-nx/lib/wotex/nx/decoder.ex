defmodule Wotex.Nx.Decoder do
  @moduledoc """
  Validates one numerical tensor against an explicit output contract.

  Decoding checks vectorization, shape, dtype, DataSchema value constraints,
  output-specific bounds, and required caller context before returning an
  observation, prediction, anomaly, or Action proposal. Every result is inert:
  this module neither admits canonical state nor invokes an Action.
  """

  alias Nx, as: Numerical
  alias Wotex.DataSchema

  alias Wotex.Nx.{
    ActionProposal,
    Anomaly,
    DataSchemaValidator,
    Error,
    Observation,
    Options,
    OutputSchema,
    Prediction
  }

  @doc """
  Decodes a tensor without admitting state or invoking a Thing Action.

  All output kinds require caller-supplied `:id`. Their output schema determines
  the additional required timing and identity options. Invalid tensors or
  options return `Wotex.Nx.Error`; expected failures do not raise.
  """
  @spec decode(Nx.Tensor.t(), OutputSchema.t(), keyword()) ::
          {:ok, Observation.t() | Prediction.t() | Anomaly.t() | ActionProposal.t()}
          | {:error, Error.t()}
  def decode(tensor, schema, opts \\ [])

  def decode(%Nx.Tensor{} = tensor, %OutputSchema{} = schema, opts)
      when is_list(opts) do
    with :ok <-
           Options.validate(opts, decoder_options(schema.kind), :invalid_output_options, :output),
         :ok <- tensor_contract(tensor, schema),
         {:ok, value} <- tensor_value(tensor, DataSchema.to_map(schema.data_schema)),
         :ok <- validate_value(value, schema),
         {:ok, common} <- common_options(opts, schema.metadata) do
      build(schema, value, common, opts)
    end
  rescue
    _ in [ArgumentError, RuntimeError, FunctionClauseError] ->
      {:error,
       Error.new(
         :tensor_read_failed,
         :output,
         "numerical output could not be read"
       )}
  end

  def decode(_, _, _) do
    {:error,
     Error.new(
       :invalid_decoder_input,
       :output,
       "decoder requires an Nx tensor, OutputSchema, and keyword options"
     )}
  end

  defp tensor_contract(tensor, schema) do
    cond do
      tensor.vectorized_axes != [] ->
        {:error,
         Error.new(
           :vectorized_output_unsupported,
           :output,
           "numerical output must not contain vectorized axes"
         )}

      Numerical.shape(tensor) != schema.shape ->
        {:error,
         Error.new(
           :output_shape_mismatch,
           :output,
           "numerical output shape does not match OutputSchema",
           %{expected: schema.shape, actual: Numerical.shape(tensor)}
         )}

      Numerical.type(tensor) != schema.dtype ->
        {:error,
         Error.new(
           :output_dtype_mismatch,
           :output,
           "numerical output dtype does not match OutputSchema",
           %{expected: schema.dtype, actual: Numerical.type(tensor)}
         )}

      true ->
        :ok
    end
  end

  defp decoder_options(:observation),
    do: [:id, :metadata, :observed_at, :quality, :source]

  defp decoder_options(:prediction), do: [:id, :metadata, :produced_at, :target_at]
  defp decoder_options(:anomaly), do: [:id, :metadata, :produced_at]
  defp decoder_options(:action_proposal), do: [:id, :metadata, :proposed_at]
  defp decoder_options(_), do: []

  defp tensor_value(tensor, data_schema) do
    raw =
      if Numerical.shape(tensor) == {} do
        Numerical.to_number(tensor)
      else
        Numerical.to_list(tensor)
      end

    restore_schema_value(raw, data_schema)
  end

  defp restore_schema_value(0, %{"type" => "boolean"}), do: {:ok, false}
  defp restore_schema_value(1, %{"type" => "boolean"}), do: {:ok, true}

  defp restore_schema_value(_, %{"type" => "boolean"}) do
    {:error,
     Error.new(
       :invalid_boolean_encoding,
       :output,
       "boolean numerical output must be encoded as zero or one"
     )}
  end

  defp restore_schema_value(values, %{"type" => "array", "items" => items})
       when is_list(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, decoded} ->
        case restore_schema_value(value, items) do
          {:ok, restored} -> {:cont, {:ok, [restored | decoded]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, error} -> {:error, error}
    end
  end

  defp restore_schema_value(value, _), do: {:ok, value}

  defp validate_value(value, schema) do
    case DataSchemaValidator.validate(
           value,
           DataSchema.to_map(schema.data_schema),
           schema.allow_non_finite?
         ) do
      :ok ->
        :ok

      {:error, %Error{} = error} ->
        {:error, Error.new(error.code, :output, error.message, error.details)}
    end
  end

  defp common_options(opts, schema_metadata) do
    id = Keyword.get(opts, :id)
    metadata = Keyword.get(opts, :metadata, %{})

    if non_empty?(id) and is_map(metadata) do
      {:ok, %{id: id, metadata: Map.merge(schema_metadata, metadata)}}
    else
      {:error,
       Error.new(
         :invalid_output_options,
         :output,
         "output requires a non-empty caller-supplied id and map metadata"
       )}
    end
  end

  defp build(%OutputSchema{kind: :observation} = schema, value, common, opts) do
    Observation.new(
      id: common.id,
      thing_id: schema.thing_id,
      affordance_type: schema.affordance_type,
      affordance_name: schema.affordance_name,
      observed_at: Keyword.get(opts, :observed_at),
      value: value,
      unit: schema.unit,
      quality: Keyword.get(opts, :quality, :good),
      source: Keyword.get(opts, :source),
      metadata: common.metadata
    )
    |> output_phase()
  end

  defp build(%OutputSchema{kind: :prediction} = schema, value, common, opts) do
    produced_at = Keyword.get(opts, :produced_at)
    target_at = Keyword.get(opts, :target_at)

    if is_integer(produced_at) and is_integer(target_at) do
      {:ok,
       %Prediction{
         id: common.id,
         thing_id: schema.thing_id,
         affordance_type: schema.affordance_type,
         affordance_name: schema.affordance_name,
         value: value,
         produced_at: produced_at,
         target_at: target_at,
         unit: schema.unit,
         metadata: common.metadata
       }}
    else
      {:error,
       Error.new(
         :invalid_prediction_time,
         :output,
         "prediction requires integer produced_at and target_at"
       )}
    end
  end

  defp build(%OutputSchema{kind: :anomaly} = schema, score, common, opts) do
    produced_at = Keyword.get(opts, :produced_at)

    if is_integer(produced_at) do
      {:ok,
       %Anomaly{
         id: common.id,
         thing_id: schema.thing_id,
         affordance_type: schema.affordance_type,
         affordance_name: schema.affordance_name,
         score: score,
         anomalous?: anomalous?(score, schema.threshold, schema.anomaly_rule),
         threshold: schema.threshold,
         rule: schema.anomaly_rule,
         produced_at: produced_at,
         metadata: common.metadata
       }}
    else
      {:error,
       Error.new(
         :invalid_anomaly_time,
         :output,
         "anomaly requires an integer produced_at"
       )}
    end
  end

  defp build(%OutputSchema{kind: :action_proposal} = schema, input, common, opts) do
    proposed_at = Keyword.get(opts, :proposed_at)

    if is_integer(proposed_at) do
      {:ok,
       %ActionProposal{
         id: common.id,
         thing_id: schema.thing_id,
         action_name: schema.affordance_name,
         input: input,
         proposed_at: proposed_at,
         metadata: common.metadata
       }}
    else
      {:error,
       Error.new(
         :invalid_action_proposal_time,
         :output,
         "Action proposal requires an integer proposed_at"
       )}
    end
  end

  defp anomalous?(score, threshold, :above), do: score > threshold
  defp anomalous?(score, threshold, :at_or_above), do: score >= threshold
  defp anomalous?(score, threshold, :below), do: score < threshold
  defp anomalous?(score, threshold, :at_or_below), do: score <= threshold

  defp output_phase({:ok, output}), do: {:ok, output}

  defp output_phase({:error, %Error{} = error}) do
    {:error, Error.new(error.code, :output, error.message, error.details)}
  end

  defp non_empty?(value), do: is_binary(value) and byte_size(value) > 0
end
