defmodule Wotex.BACnet.RuntimeFrame do
  @moduledoc false

  alias Wotex.BACnet.{COV, COVRequest, Error, Value, ValueBoundary}

  @keys [
    :source,
    :device_instance,
    :process_identifier,
    :object_type,
    :instance,
    :property,
    :array_index,
    :time_remaining,
    :report_values
  ]

  @doc false
  @spec validate(term(), term(), COVRequest.t(), term()) :: :ok | {:error, Error.t()}
  def validate(value, metadata, %COVRequest{} = request, destination)
      when is_map(metadata) and map_size(metadata) == 9 do
    with true <- Map.keys(metadata) -- @keys == [],
         true <-
           metadata.source === destination and metadata.device_instance === request.device_instance,
         true <-
           metadata.object_type === request.object_type and metadata.instance === request.instance,
         true <-
           metadata.property === request.property and metadata.array_index === request.array_index,
         true <- uint?(metadata.process_identifier, 4_294_967_295),
         true <- uint?(metadata.time_remaining, 4_294_967_295),
         :ok <- ValueBoundary.validate(metadata),
         :ok <- Value.validate_read(value),
         true <- valid_entries?(metadata.report_values),
         {:ok, selected} <- COV.value(%{values: metadata.report_values}, request),
         true <- selected === value do
      :ok
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_runtime_frame)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_runtime_frame)}
  end

  def validate(_, _, _, _), do: {:error, Error.new(:invalid_runtime_frame)}

  @doc false
  @spec project(term(), map()) :: {:ok, term(), map()}
  def project(value, metadata) do
    {payload, native} = Value.result(value)
    {:ok, payload, Map.merge(metadata, native)}
  end

  defp valid_entries?(entries) when is_list(entries), do: Enum.all?(entries, &entry?/1)
  defp valid_entries?(_), do: false

  defp entry?(%{property: property, array_index: index, priority: priority, value: value} = entry)
       when map_size(entry) == 4 do
    uint?(property, 4_194_303) and (is_nil(index) or uint?(index, 4_294_967_295)) and
      (is_nil(priority) or (is_integer(priority) and priority in 1..16)) and
      Value.validate_read(value) == :ok
  end

  defp entry?(_), do: false
  defp uint?(value, maximum), do: is_integer(value) and value >= 0 and value <= maximum
end
