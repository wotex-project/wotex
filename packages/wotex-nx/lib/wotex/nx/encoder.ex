defmodule Wotex.Nx.Encoder do
  @moduledoc """
  Converts accepted temporal rows into a deterministic lazy `Nx.Batch`.

  Encoding follows schema order and emits a tuple of value tensors, mask
  tensors, and a quality vector for each row. It validates observation identity,
  DataSchema values, units, quality, missing policy, shape, dtype, and limits
  before construction. It does not select a backend or execute a model.
  """

  alias Nx, as: Numerical
  alias Wotex.DataSchema

  alias Wotex.Nx.{
    DataSchemaValidator,
    Encoded,
    Error,
    Feature,
    Observation,
    Options,
    Row,
    Schema
  }

  @doc """
  Encodes non-empty rows according to an accepted `Wotex.Nx.Schema`.

  Pass `:unit_converter` as `{module, config}` only when source and target units
  differ. The result includes the lazy batch and enough order, timestamp, and
  provenance information to interpret it deterministically.
  """
  @spec encode([Row.t()], Schema.t(), keyword()) :: {:ok, Encoded.t()} | {:error, Error.t()}
  def encode(rows, schema, opts \\ [])

  def encode(rows, %Schema{} = schema, opts) when is_list(rows) and is_list(opts) do
    with :ok <- Options.validate(opts, [:unit_converter], :invalid_encoder_input, :encoding) do
      cond do
        rows == [] ->
          {:error, Error.new(:empty_rows, :encoding, "at least one row is required")}

        length(rows) > schema.max_rows ->
          {:error,
           Error.new(:row_limit_exceeded, :limit, "row limit exceeded", %{
             count: length(rows),
             max_rows: schema.max_rows
           })}

        not Enum.all?(rows, &match?(%Row{}, &1)) ->
          {:error, Error.new(:invalid_rows, :encoding, "encoder input must contain Row values")}

        true ->
          encode_rows(rows, schema, opts)
      end
    end
  end

  def encode(_, _, _),
    do: {:error, Error.new(:invalid_encoder_input, :encoding, "encoder input is invalid")}

  defp encode_rows(rows, schema, opts) do
    with {:ok, containers} <- map_rows(rows, schema.features, opts),
         {:ok, batch} <- build_batch(containers, schema.batch_key) do
      {:ok,
       %Encoded{
         batch: batch,
         schema: schema,
         feature_order: Enum.map(schema.features, & &1.name),
         timestamps: Enum.map(rows, & &1.timestamp),
         provenance: Enum.map(rows, & &1.provenance),
         layout: :feature_tuple_values_masks_quality_vector
       }}
    end
  end

  defp map_rows(rows, features, opts) do
    result =
      Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, encoded_rows} ->
        case encode_row(row, features, opts) do
          {:ok, container} -> {:cont, {:ok, [container | encoded_rows]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, error} -> {:error, error}
    end
  end

  defp encode_row(row, features, opts) do
    result =
      Enum.reduce_while(
        features,
        {:ok, [], [], []},
        &encode_feature_for_row(&1, &2, row, opts)
      )

    case result do
      {:ok, values, masks, qualities} ->
        quality_tensor =
          qualities
          |> Enum.reverse()
          |> Numerical.tensor(type: :u8, names: [:feature])

        value_tuple =
          values
          |> Enum.reverse()
          |> List.to_tuple()

        mask_tuple =
          masks
          |> Enum.reverse()
          |> List.to_tuple()

        {:ok, {value_tuple, mask_tuple, quality_tensor}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp encode_feature_for_row(feature, {:ok, values, masks, qualities}, row, opts) do
    observation = Map.get(row.observations, feature.name)

    case encode_feature(observation, feature, row.timestamp, opts) do
      {:ok, value, mask, quality} ->
        {:cont, {:ok, [value | values], [mask | masks], [quality | qualities]}}

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp encode_feature(nil, feature, timestamp, _),
    do: encode_missing(feature, timestamp, :missing)

  defp encode_feature(%Observation{} = observation, feature, timestamp, opts) do
    cond do
      observation.thing_id != feature.thing_id or
        observation.affordance_type != feature.affordance_type or
          observation.affordance_name != feature.affordance_name ->
        {:error,
         Error.new(
           :observation_feature_mismatch,
           :encoding,
           "observation does not match feature affordance",
           %{
             feature: feature.name,
             timestamp: timestamp
           }
         )}

      not MapSet.member?(feature.accepted_quality, observation.quality) ->
        encode_missing(feature, timestamp, observation.quality)

      true ->
        with {:ok, value} <- convert_unit(observation, feature, opts),
             :ok <-
               DataSchemaValidator.validate(
                 value,
                 DataSchema.to_map(feature.data_schema),
                 feature.allow_non_finite?
               ),
             normalized <- normalize(value, feature.normalization),
             {:ok, tensor} <- tensor(normalized, feature) do
          {:ok, tensor, mask(feature.shape, 0), quality_code(observation.quality)}
        end
    end
  end

  defp encode_missing(%Feature{missing: :error} = feature, timestamp, quality) do
    {:error,
     Error.new(
       :missing_feature_value,
       :encoding,
       "feature value is missing or rejected by quality policy",
       %{
         feature: feature.name,
         timestamp: timestamp,
         quality: quality
       }
     )}
  end

  defp encode_missing(%Feature{missing: {:fill, fill}} = feature, _, quality) do
    value = broadcast_value(fill, feature.shape)

    with :ok <-
           DataSchemaValidator.validate(
             value,
             DataSchema.to_map(feature.data_schema),
             feature.allow_non_finite?
           ),
         normalized <- normalize(value, feature.normalization),
         {:ok, tensor} <- tensor(normalized, feature) do
      {:ok, tensor, mask(feature.shape, 1), quality_code(quality)}
    end
  end

  defp convert_unit(%Observation{unit: unit, value: value}, %Feature{unit: unit}, _),
    do: {:ok, value}

  defp convert_unit(%Observation{unit: nil, value: value}, %Feature{unit: nil}, _),
    do: {:ok, value}

  defp convert_unit(%Observation{} = observation, %Feature{} = feature, opts) do
    case Keyword.get(opts, :unit_converter) do
      {module, config} when is_atom(module) and not is_nil(module) ->
        convert_with_port(observation, feature, module, config)

      _ ->
        {:error,
         Error.new(:unit_conversion_required, :unit, "observation and feature units differ", %{
           feature: feature.name,
           observation_unit: observation.unit,
           feature_unit: feature.unit
         })}
    end
  end

  defp convert_with_port(observation, feature, module, config) do
    if valid_unit_converter?(observation, feature, module) do
      result =
        module.convert(
          observation.value,
          observation.unit,
          feature.unit,
          feature.data_schema,
          config
        )

      normalize_conversion_result(result, feature)
    else
      {:error,
       Error.new(:invalid_unit_converter, :unit, "unit converter port is invalid", %{
         feature: feature.name
       })}
    end
  end

  defp valid_unit_converter?(observation, feature, module) do
    is_binary(observation.unit) and is_binary(feature.unit) and Code.ensure_loaded?(module) and
      function_exported?(module, :convert, 5)
  end

  defp normalize_conversion_result({:ok, converted}, _), do: {:ok, converted}

  defp normalize_conversion_result({:error, _}, feature) do
    {:error,
     Error.new(:unit_conversion_failed, :unit, "unit conversion failed", %{
       feature: feature.name
     })}
  end

  defp normalize_conversion_result(_, feature) do
    {:error,
     Error.new(
       :invalid_unit_converter_return,
       :unit,
       "unit converter returned an invalid value",
       %{feature: feature.name}
     )}
  end

  defp normalize(value, :none), do: value
  defp normalize(value, {:z_score, mean, stddev}), do: map_numbers(value, &((&1 - mean) / stddev))

  defp normalize(value, {:min_max, minimum, maximum}),
    do: map_numbers(value, &((&1 - minimum) / (maximum - minimum)))

  defp map_numbers(values, function) when is_list(values),
    do: Enum.map(values, &map_numbers(&1, function))

  defp map_numbers(true, function), do: function.(1)
  defp map_numbers(false, function), do: function.(0)
  defp map_numbers(value, function) when is_number(value), do: function.(value)

  defp tensor(value, feature) do
    converted = booleans_to_numbers(value)
    numerical = Numerical.tensor(converted, type: feature.dtype)

    if Numerical.shape(numerical) == feature.shape do
      {:ok, numerical}
    else
      {:error,
       Error.new(:tensor_shape_mismatch, :encoding, "tensor shape does not match feature shape", %{
         feature: feature.name,
         expected_shape: feature.shape,
         actual_shape: Numerical.shape(numerical)
       })}
    end
  rescue
    _ in [ArgumentError, FunctionClauseError] ->
      {:error,
       Error.new(:tensor_construction_failed, :encoding, "tensor construction failed", %{
         feature: feature.name
       })}
  end

  defp booleans_to_numbers(values) when is_list(values),
    do: Enum.map(values, &booleans_to_numbers/1)

  defp booleans_to_numbers(true), do: 1
  defp booleans_to_numbers(false), do: 0
  defp booleans_to_numbers(value), do: value

  defp broadcast_value(value, {}), do: value
  defp broadcast_value(value, shape), do: broadcast_dimensions(value, Tuple.to_list(shape))
  defp broadcast_dimensions(value, []), do: value

  defp broadcast_dimensions(value, [size | rest]),
    do: List.duplicate(broadcast_dimensions(value, rest), size)

  defp mask({}, value), do: Numerical.tensor(value, type: :u8)
  defp mask(shape, value), do: Numerical.broadcast(Numerical.tensor(value, type: :u8), shape)

  defp quality_code(quality), do: Map.fetch!(Wotex.Nx.quality_codes(), quality)

  defp build_batch(containers, batch_key) do
    stacked = Numerical.Batch.stack(containers)
    batch = Numerical.Batch.key(stacked, batch_key)
    {:ok, batch}
  rescue
    _ in [ArgumentError, FunctionClauseError] ->
      {:error, Error.new(:batch_construction_failed, :encoding, "Nx.Batch construction failed")}
  end
end
