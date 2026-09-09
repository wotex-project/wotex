defmodule Wotex.BACnet.COV do
  @moduledoc false

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{COVRequest, Error, Value, ValueBoundary}

  @doc false
  @spec request(COVRequest.t(), 0..4_294_967_295, boolean()) ::
          {:ok, APDU.ConfirmedServiceRequest.t()} | {:error, Error.t()}
  def request(request, identifier, cancel \\ false)

  def request(%COVRequest{} = request, identifier, cancel)
      when is_integer(identifier) and identifier in 0..4_294_967_295 and is_boolean(cancel) do
    with :ok <- COVRequest.validate(request) do
      selectors = [
        unsigned(0, identifier),
        {:tagged, {1, <<request.object_type::10, request.instance::22>>, 4}}
      ]

      registration =
        if cancel,
          do: [],
          else: [unsigned(2, if(request.confirmed, do: 1, else: 0)), unsigned(3, request.lifetime)]

      property =
        if request.type == :cov_property,
          do: [
            {:constructed,
             {4, [unsigned(0, request.property)] ++ optional_unsigned(1, request.array_index), 0}}
          ],
          else: []

      increment =
        if not cancel and request.cov_increment,
          do: [{:tagged, {5, <<request.cov_increment::float-32>>, 4}}],
          else: []

      {:ok,
       %APDU.ConfirmedServiceRequest{
         segmented_response_accepted: true,
         max_segments: 32,
         max_apdu: 1476,
         invoke_id: 0,
         sequence_number: nil,
         proposed_window_size: nil,
         service: if(request.type == :cov, do: :subscribe_cov, else: :subscribe_cov_property),
         parameters: selectors ++ registration ++ property ++ increment
       }}
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_subscription)}

  @doc false
  @spec notification(term()) :: {:ok, map()} | {:error, Error.t()}
  def notification(%APDU.ConfirmedServiceRequest{
        service: :confirmed_cov_notification,
        parameters: parameters,
        invoke_id: id
      })
      when is_integer(id) and id in 0..255 do
    decode(parameters, true, id)
  end

  def notification(%APDU.UnconfirmedServiceRequest{
        service: :unconfirmed_cov_notification,
        parameters: parameters
      }),
      do: decode(parameters, false, nil)

  def notification(_), do: {:error, Error.new(:invalid_cov_notification)}

  @doc false
  @spec matches?(map(), COVRequest.t(), non_neg_integer()) :: boolean()
  def matches?(
        %{
          process_identifier: _,
          device_instance: _,
          object_type: _,
          instance: _,
          confirmed: _,
          values: _
        } = report,
        %COVRequest{} = request,
        identifier
      ) do
    report.process_identifier == identifier and
      report.device_instance == request.device_instance and
      report.object_type == request.object_type and report.instance == request.instance and
      report.confirmed == request.confirmed and
      (request.type == :cov or
         Enum.any?(report.values, &property_matches?(&1, request)))
  rescue
    _ -> false
  end

  def matches?(_, _, _), do: false

  @doc false
  @spec value(map(), COVRequest.t()) :: {:ok, term()} | {:error, Error.t()}
  def value(%{values: values}, %COVRequest{type: :cov}) when is_list(values), do: {:ok, values}

  def value(%{values: values}, %COVRequest{type: :cov_property} = request) when is_list(values) do
    case Enum.filter(values, &property_matches?(&1, request)) do
      [] ->
        {:error, Error.new(:missing_cov_property)}

      [first | rest] ->
        if Enum.all?(rest, &(&1.value === first.value)),
          do: {:ok, first.value},
          else: {:error, Error.new(:conflicting_cov_values)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_cov_notification)}
  end

  def value(_, _), do: {:error, Error.new(:invalid_cov_notification)}

  defp property_matches?(
         %{property: property, array_index: index},
         %COVRequest{property: property, array_index: index}
       ),
       do: true

  defp property_matches?(_, _), do: false

  defp decode(
         [
           {:tagged, {0, process, process_size}},
           {:tagged, {1, <<8::10, device::22>>, 4}},
           {:tagged, {2, <<object_type::10, instance::22>>, 4}},
           {:tagged, {3, remaining, remaining_size}},
           {:constructed, {4, values, 0}}
         ],
         confirmed,
         id
       )
       when device < 4_194_303 and instance < 4_194_303 do
    with {:ok, process} <- unsigned_value(process, process_size),
         {:ok, remaining} <- unsigned_value(remaining, remaining_size),
         {:ok, values} <- properties(values, [], 0),
         :ok <- ValueBoundary.validate(Enum.map(values, & &1.value)) do
      {:ok,
       %{
         process_identifier: process,
         device_instance: device,
         object_type: object_type,
         instance: instance,
         time_remaining: remaining,
         values: values,
         confirmed: confirmed,
         invoke_id: id
       }}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_cov_notification)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_cov_notification)}
  end

  defp decode(_, _, _), do: {:error, Error.new(:invalid_cov_notification)}

  defp properties([], values, count) when count > 0, do: {:ok, Enum.reverse(values)}

  defp properties([{:tagged, {0, bytes, size}} | rest], values, count) when count < 1024 do
    with {:ok, property} <- unsigned_value(bytes, size),
         true <- property <= 4_194_303,
         {:ok, index, rest} <- optional_value(rest, 1),
         [{:constructed, {2, value, 0}} | rest] <- rest,
         {:ok, priority, rest} <- optional_value(rest, 3),
         true <- is_nil(priority) or priority in 1..16,
         :ok <- ValueBoundary.validate(value),
         {:ok, value} <- encodings(value),
         :ok <- Value.validate_read(value) do
      properties(
        rest,
        [%{property: property, array_index: index, priority: priority, value: value} | values],
        count + 1
      )
    else
      {:error, %Error{}} = error -> error
      _ -> :error
    end
  end

  defp properties([_ | _], _, 1024), do: {:error, Error.new(:value_limit)}
  defp properties(_, _, _), do: :error

  defp encodings(values) when is_list(values) do
    result =
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case Encoding.create(value) do
          {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
          _ -> {:halt, :error}
        end
      end)

    case result do
      {:ok, result} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp encodings(value), do: Encoding.create(value)

  defp optional_value([{:tagged, {tag, bytes, size}} | rest], tag) do
    with {:ok, value} <- unsigned_value(bytes, size), do: {:ok, value, rest}
  end

  defp optional_value(rest, _), do: {:ok, nil, rest}

  defp unsigned_value(bytes, size)
       when is_binary(bytes) and size in 1..4 and byte_size(bytes) == size,
       do: {:ok, :binary.decode_unsigned(bytes)}

  defp unsigned_value(_, _), do: :error
  defp optional_unsigned(_, nil), do: []
  defp optional_unsigned(tag, value), do: [unsigned(tag, value)]

  defp unsigned(tag, value) do
    bytes = :binary.encode_unsigned(value)
    {:tagged, {tag, bytes, byte_size(bytes)}}
  end
end
