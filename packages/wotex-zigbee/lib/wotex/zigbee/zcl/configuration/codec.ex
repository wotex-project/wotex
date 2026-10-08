defmodule Wotex.Zigbee.ZCL.Configuration.Codec do
  @moduledoc false

  alias Wotex.Zigbee.Error
  alias Wotex.Zigbee.ZCL.{Value, Wire}

  @commands %{write_attributes: 2, configure_reporting: 6, read_reporting: 8}
  @responses %{
    4 => :write_response,
    7 => :configure_response,
    9 => :read_reporting_response,
    11 => :default_response
  }

  @doc false
  @spec encode(atom(), [map()], byte(), atom(), non_neg_integer() | nil) ::
          {:ok, binary(), [map()]} | {:error, Error.t()}
  def encode(command, records, sequence, direction, manufacturer)
      when is_map_key(@commands, command) and is_list(records) and length(records) in 1..32 do
    with {:ok, payload, canonical} <- encode_records(command, records),
         true <- unique?(command, canonical),
         {:ok, bytes} <-
           Wire.encode(Map.fetch!(@commands, command), payload, sequence, direction, manufacturer) do
      {:ok, bytes, canonical}
    else
      _ -> failure(:invalid_value)
    end
  end

  def encode(_, _, _, _, _), do: failure(:invalid_value)

  @doc false
  @spec decode(binary(), pos_integer()) :: {:ok, map()} | {:error, Error.t()}
  def decode(bytes, limit) when is_integer(limit) and limit in 1..32 do
    with {:ok, header, payload} <- Wire.parse(bytes),
         {:ok, command} <- Map.fetch(@responses, header.command),
         {:ok, result} <- decode_payload(command, payload, limit) do
      response =
        header
        |> Map.put(:command, command)
        |> Map.merge(result)
        |> Map.put(:raw, bytes)

      {:ok, response}
    else
      _ -> failure(:invalid_frame)
    end
  end

  def decode(_, _), do: failure(:invalid_frame)

  defp encode_records(command, records) do
    result =
      Enum.reduce_while(records, {:ok, <<>>, []}, fn record, {:ok, payload, canonical} ->
        case encode_record(command, record) do
          {:ok, bytes, normalized} ->
            {:cont, {:ok, <<payload::binary, bytes::binary>>, [normalized | canonical]}}

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, payload, canonical} -> {:ok, payload, Enum.reverse(canonical)}
      error -> error
    end
  end

  defp encode_record(:write_attributes, %{id: id, type: type, value: value} = record) do
    full = Map.get(record, :full_range, false)

    with true <- fields?(record, [:id, :type, :value], [:full_range]) and uint16?(id),
         {:ok, raw} <- Value.encode(type, value, full) do
      {:ok, <<id::little-16, type, raw::binary>>, Map.put(record, :full_range, full)}
    else
      _ -> failure(:invalid_value)
    end
  end

  defp encode_record(
         :configure_reporting,
         %{
           report_direction: :send,
           id: id,
           type: type,
           min_interval_s: minimum,
           max_interval_s: maximum
         } = record
       ) do
    with true <- uint16?(id) and intervals?(minimum, maximum),
         {:ok, category} <- Value.category(type),
         {:ok, change} <- encode_change(record, category) do
      {:ok, <<0, id::little-16, type, minimum::little-16, maximum::little-16, change::binary>>,
       record}
    else
      _ -> failure(:invalid_value)
    end
  end

  defp encode_record(
         :configure_reporting,
         %{report_direction: :receive, id: id, timeout_s: timeout} = record
       ) do
    if fields?(record, [:id, :report_direction, :timeout_s], []) and uint16?(id) and
         uint16?(timeout),
       do: {:ok, <<1, id::little-16, timeout::little-16>>, record},
       else: failure(:invalid_value)
  end

  defp encode_record(:read_reporting, %{report_direction: direction, id: id} = record) do
    if fields?(record, [:id, :report_direction], []) and uint16?(id) and
         direction in [:send, :receive],
       do: {:ok, <<direction_byte(direction), id::little-16>>, record},
       else: failure(:invalid_value)
  end

  defp encode_record(_, _), do: failure(:invalid_value)

  defp encode_change(record, :discrete) do
    if fields?(record, [:id, :report_direction, :type, :min_interval_s, :max_interval_s], []),
      do: {:ok, <<>>},
      else: failure(:invalid_value)
  end

  defp encode_change(%{change: change} = record, :analog) do
    zero_required =
      record.max_interval_s == 0xFFFF or
        (record.min_interval_s == 0xFFFF and record.max_interval_s == 0)

    if fields?(
         record,
         [:id, :report_direction, :type, :min_interval_s, :max_interval_s, :change],
         []
       ) and
         is_integer(change) and (not zero_required or change == 0),
       do: Value.encode(record.type, change),
       else: failure(:invalid_value)
  end

  defp encode_change(_, _), do: failure(:invalid_value)

  defp decode_payload(command, <<0>>, _) when command in [:write_response, :configure_response],
    do: {:ok, %{aggregate: :all_success, records: []}}

  defp decode_payload(command, payload, limit)
       when command in [:write_response, :configure_response] do
    with {:ok, records} <- error_records(command, payload, limit, []),
         do: {:ok, %{aggregate: :errors, records: records}}
  end

  defp decode_payload(:read_reporting_response, payload, limit) do
    with {:ok, records} <- reporting_records(payload, limit, []),
         do: {:ok, %{aggregate: :records, records: records}}
  end

  defp decode_payload(:default_response, <<command, status>>, _),
    do:
      {:ok, %{aggregate: :default, records: [], original_command: command, status: status(status)}}

  defp decode_payload(_, _, _), do: failure(:invalid_frame)

  defp error_records(_, <<>>, _, []), do: failure(:invalid_frame)
  defp error_records(_, <<>>, _, records), do: {:ok, Enum.reverse(records)}

  defp error_records(:write_response, <<status, id::little-16, tail::binary>>, limit, records)
       when status != 0 and limit > 0 do
    error_records(:write_response, tail, limit - 1, [%{id: id, status: status(status)} | records])
  end

  defp error_records(
         :configure_response,
         <<status, direction, id::little-16, tail::binary>>,
         limit,
         records
       )
       when status != 0 and direction in [0, 1] and limit > 0 do
    record = %{id: id, report_direction: report_direction(direction), status: status(status)}
    error_records(:configure_response, tail, limit - 1, [record | records])
  end

  defp error_records(_, _, _, _), do: failure(:invalid_frame)

  defp reporting_records(<<>>, _, []), do: failure(:invalid_frame)
  defp reporting_records(<<>>, _, records), do: {:ok, Enum.reverse(records)}

  defp reporting_records(<<status, direction, id::little-16, bytes::binary>>, limit, records)
       when direction in [0, 1] and limit > 0 do
    with {:ok, configuration, tail} <- read_configuration(status, direction, bytes) do
      record = %{
        id: id,
        report_direction: report_direction(direction),
        status: status(status),
        configuration: configuration
      }

      reporting_records(tail, limit - 1, [record | records])
    end
  end

  defp reporting_records(_, _, _), do: failure(:invalid_frame)

  defp read_configuration(status, _, bytes) when status != 0, do: {:ok, nil, bytes}

  defp read_configuration(0, 1, <<timeout::little-16, tail::binary>>),
    do: {:ok, %{timeout_s: timeout}, tail}

  defp read_configuration(0, 0, <<type, bytes::binary>>) when byte_size(bytes) >= 4 do
    case Value.category(type) do
      {:ok, category} -> read_send_configuration(type, category, bytes)
      {:error, _} -> {:ok, {:unsupported, type, <<type, bytes::binary>>}, <<>>}
    end
  end

  defp read_configuration(_, _, _), do: failure(:invalid_frame)

  defp read_send_configuration(
         type,
         category,
         <<minimum::little-16, maximum::little-16, bytes::binary>>
       ) do
    with {:ok, change, raw, tail} <- read_change(type, category, bytes) do
      {:ok,
       %{
         type: type,
         min_interval_s: minimum,
         max_interval_s: maximum,
         change: change,
         raw_change: raw
       }, tail}
    end
  end

  defp read_send_configuration(_, _, _), do: failure(:invalid_frame)
  defp read_change(type, :analog, bytes), do: Value.decode(type, bytes)
  defp read_change(_, :discrete, bytes), do: {:ok, nil, nil, bytes}

  defp unique?(command, records) do
    keys = Enum.map(records, &key(command, &1))
    length(keys) == length(Enum.uniq(keys))
  end

  defp key(:write_attributes, record), do: record.id
  defp key(_, record), do: {record.report_direction, record.id}

  defp fields?(record, required, optional),
    do:
      map_size(record) in length(required)..(length(required) + length(optional)) and
        Enum.all?(required, &Map.has_key?(record, &1)) and
        Enum.all?(Map.keys(record), &(&1 in required or &1 in optional))

  defp intervals?(minimum, maximum),
    do:
      uint16?(minimum) and uint16?(maximum) and
        (maximum == 0 or maximum >= minimum)

  defp uint16?(value), do: is_integer(value) and value in 0..0xFFFF
  defp direction_byte(:send), do: 0
  defp direction_byte(:receive), do: 1
  defp report_direction(0), do: :send
  defp report_direction(1), do: :receive
  defp status(0), do: :success
  defp status(code), do: {:error, code}
  defp failure(kind), do: {:error, %Error{kind: kind, operation: :zcl_configuration}}
end
