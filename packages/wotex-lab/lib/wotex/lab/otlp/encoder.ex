defmodule Wotex.Lab.Otlp.Encoder do
  @moduledoc """
  Hand-written OTLP/HTTP protobuf encoding for Lab spans and log records.

  The encoder writes `ExportTraceServiceRequest` and `ExportLogsServiceRequest`
  messages of opentelemetry-proto v1.5.0 and reads the `partial_success` field
  of their responses. It supports only the fields the Lab emits: resource
  string attributes; one instrumentation scope named `wotex_lab` with the
  package version; spans with trace and span identifiers, name, internal kind,
  start and end Unix nanoseconds, string attributes and an OK or ERROR status;
  and log records with time, observed time, severity number and text, string
  body, string attributes and event name. Messages, links, events, parent
  identifiers, flags and non-string attribute values are never written.

  Encoding validates each record's shape and bounds (32 attributes, 128-byte
  keys, 256-byte values, 16-byte trace and 8-byte span identifiers) and returns
  `invalid_otlp_record` instead of truncating. `partial_success/2` accepts an
  empty body as full acceptance, decodes the rejected count and error message
  of a protobuf response and refuses malformed input. No network access, atom
  creation or schema compilation happens here.
  """

  import Bitwise

  alias Wotex.Lab.Error

  @scope_name "wotex_lab"
  @scope_version "0.1.0"
  @max_attributes 32
  @max_key_bytes 128
  @max_value_bytes 256
  @max_message_bytes 1_024
  @severities %{info: {9, "INFO"}, warn: {13, "WARN"}, error: {17, "ERROR"}}

  @typedoc "A string attribute."
  @type attribute :: {String.t(), String.t()}

  @typedoc "A closed internal span."
  @type span :: %{
          trace_id: <<_::128>>,
          span_id: <<_::64>>,
          name: String.t(),
          start_ns: non_neg_integer(),
          end_ns: non_neg_integer(),
          attributes: [attribute()],
          status: :ok | :error
        }

  @typedoc "A closed log record."
  @type log :: %{
          time_ns: non_neg_integer(),
          observed_ns: non_neg_integer(),
          severity: :info | :warn | :error,
          body: String.t(),
          event_name: String.t(),
          attributes: [attribute()]
        }

  @typedoc "An OTLP signal."
  @type signal :: :traces | :logs

  @doc "The pinned opentelemetry-proto revision."
  @spec proto_revision() :: String.t()
  def proto_revision, do: "v1.5.0"

  @doc "Encodes resource attributes and spans as an `ExportTraceServiceRequest`."
  @spec encode_traces([attribute()], [span()]) :: {:ok, binary()} | {:error, Error.t()}
  def encode_traces(resource, spans) when is_list(spans) and spans != [] do
    with {:ok, resource} <- resource(resource),
         {:ok, spans} <- collect(spans, &span/1) do
      {:ok, IO.iodata_to_binary(bytes(1, [resource, bytes(2, [scope(), spans])]))}
    end
  end

  def encode_traces(_, _), do: invalid()

  @doc "Encodes resource attributes and log records as an `ExportLogsServiceRequest`."
  @spec encode_logs([attribute()], [log()]) :: {:ok, binary()} | {:error, Error.t()}
  def encode_logs(resource, logs) when is_list(logs) and logs != [] do
    with {:ok, resource} <- resource(resource),
         {:ok, logs} <- collect(logs, &log/1) do
      {:ok, IO.iodata_to_binary(bytes(1, [resource, bytes(2, [scope(), logs])]))}
    end
  end

  def encode_logs(_, _), do: invalid()

  @doc """
  Reads the partial-success field of an export response.

  Returns the number of rejected spans or log records and the server's error
  message, which callers should treat as untrusted diagnostic text.
  """
  @spec partial_success(signal(), binary()) ::
          {:ok, %{rejected: non_neg_integer(), message: String.t()}} | {:error, Error.t()}
  def partial_success(signal, body) when signal in [:traces, :logs] and is_binary(body) do
    with {:ok, fields} <- fields(body, []) do
      case Enum.filter(fields, &match?({1, 2, _}, &1)) do
        [] ->
          {:ok, %{rejected: 0, message: ""}}

        entries ->
          {1, 2, partial} = List.last(entries)
          partial_fields(partial)
      end
    end
  end

  def partial_success(_, _), do: malformed()

  defp partial_fields(partial) do
    with {:ok, fields} <- fields(partial, []) do
      rejected =
        for {1, 0, value} <- fields, reduce: 0 do
          _ -> signed(value)
        end

      message =
        for {2, 2, value} <- fields, reduce: "" do
          _ -> value
        end

      if rejected >= 0 and String.valid?(message) and byte_size(message) <= @max_message_bytes,
        do: {:ok, %{rejected: rejected, message: message}},
        else: malformed()
    end
  end

  defp resource(attributes) do
    with {:ok, attributes} <- attributes(attributes, 1), do: {:ok, bytes(1, attributes)}
  end

  defp scope, do: bytes(1, [bytes(1, @scope_name), bytes(2, @scope_version)])

  defp span(
         %{
           trace_id: <<_::128>> = trace_id,
           span_id: <<_::64>> = span_id,
           name: name,
           start_ns: start_ns,
           end_ns: end_ns,
           attributes: attributes,
           status: status
         } = span
       )
       when map_size(span) == 7 and status in [:ok, :error] and is_integer(start_ns) and
              is_integer(end_ns) and start_ns >= 0 and end_ns >= start_ns and
              end_ns < 1 <<< 64 do
    with true <- text?(name),
         {:ok, attributes} <- attributes(attributes, 9) do
      code = if status == :ok, do: 1, else: 2

      {:ok,
       bytes(2, [
         bytes(1, trace_id),
         bytes(2, span_id),
         bytes(5, name),
         uint(6, 1),
         fixed64(7, start_ns),
         fixed64(8, end_ns),
         attributes,
         bytes(15, uint(3, code))
       ])}
    else
      _ -> invalid()
    end
  end

  defp span(_), do: invalid()

  defp log(
         %{
           time_ns: time_ns,
           observed_ns: observed_ns,
           severity: severity,
           body: body,
           event_name: event_name,
           attributes: attributes
         } = log
       )
       when map_size(log) == 6 and is_map_key(@severities, severity) and is_integer(time_ns) and
              is_integer(observed_ns) and time_ns >= 0 and observed_ns >= 0 and
              time_ns < 1 <<< 64 and observed_ns < 1 <<< 64 do
    {number, text} = Map.fetch!(@severities, severity)

    with true <- text?(body) and text?(event_name),
         {:ok, attributes} <- attributes(attributes, 6) do
      {:ok,
       bytes(2, [
         fixed64(1, time_ns),
         uint(2, number),
         bytes(3, text),
         bytes(5, bytes(1, body)),
         attributes,
         fixed64(11, observed_ns),
         bytes(12, event_name)
       ])}
    else
      _ -> invalid()
    end
  end

  defp log(_), do: invalid()

  defp attributes(attributes, field)
       when is_list(attributes) and length(attributes) <= @max_attributes do
    attributes
    |> collect(fn
      {key, value} when is_binary(key) and is_binary(value) ->
        if byte_size(key) in 1..@max_key_bytes and String.valid?(key) and text?(value),
          do: {:ok, bytes(field, [bytes(1, key), bytes(2, bytes(1, value))])},
          else: invalid()

      _ ->
        invalid()
    end)
  end

  defp attributes(_, _), do: invalid()

  defp collect(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, encoded} -> {:cont, {:ok, [acc, encoded]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp text?(value),
    do: is_binary(value) and byte_size(value) <= @max_value_bytes and String.valid?(value)

  defp bytes(number, iodata), do: [key(number, 2), varint(IO.iodata_length(iodata)), iodata]
  defp uint(number, value), do: [key(number, 0), varint(value)]
  defp fixed64(number, value), do: [key(number, 1), <<value::little-unsigned-64>>]
  defp key(number, wire), do: varint(number <<< 3 ||| wire)
  defp varint(value) when value < 128, do: <<value>>
  defp varint(value), do: <<1::1, band(value, 127)::7, varint(value >>> 7)::binary>>

  defp fields(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp fields(binary, acc) do
    with {:ok, tag, rest} <- read_varint(binary, 0, 0),
         number = tag >>> 3,
         true <- number > 0,
         {:ok, value, rest} <- read_value(band(tag, 7), rest) do
      fields(rest, [{number, band(tag, 7), value} | acc])
    else
      _ -> malformed()
    end
  end

  defp read_value(0, binary), do: read_varint(binary, 0, 0)
  defp read_value(1, <<value::little-64, rest::binary>>), do: {:ok, value, rest}
  defp read_value(5, <<value::little-32, rest::binary>>), do: {:ok, value, rest}

  defp read_value(2, binary) do
    with {:ok, length, rest} <- read_varint(binary, 0, 0),
         true <- byte_size(rest) >= length do
      <<value::binary-size(^length), rest::binary>> = rest
      {:ok, value, rest}
    else
      _ -> :error
    end
  end

  defp read_value(_, _), do: :error

  defp read_varint(_, _, shift) when shift > 63, do: :error

  defp read_varint(<<0::1, byte::7, rest::binary>>, acc, shift),
    do: {:ok, acc ||| byte <<< shift, rest}

  defp read_varint(<<1::1, byte::7, rest::binary>>, acc, shift),
    do: read_varint(rest, acc ||| byte <<< shift, shift + 7)

  defp read_varint(_, _, _), do: :error

  defp signed(value) when value >= 1 <<< 63, do: value - (1 <<< 64)
  defp signed(value), do: value

  defp invalid,
    do:
      {:error, Error.new(:invalid_otlp_record, :export, "OTLP record is outside the closed shape")}

  defp malformed,
    do: {:error, Error.new(:malformed_otlp_response, :export, "OTLP export response is malformed")}
end
