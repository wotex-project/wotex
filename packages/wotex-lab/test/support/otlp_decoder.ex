defmodule Wotex.Lab.Test.OtlpDecoder do
  @moduledoc false

  # An independent protobuf reader for the OTLP export requests the Lab
  # writes, following opentelemetry-proto v1.5.0 field numbers:
  # request.resource_{spans,logs}=1; resource=1 (attributes=1), scope_{spans,logs}=2;
  # scope=1 (name=1, version=2), spans/log_records=2; Span trace_id=1,
  # span_id=2, name=5, kind=6, start=7 fixed64, end=8 fixed64, attributes=9,
  # status=15 (code=3); LogRecord time=1 fixed64, severity_number=2,
  # severity_text=3, body=5 (string_value=1), attributes=6, observed=11
  # fixed64, event_name=12; KeyValue key=1, value=2 (string_value=1).
  # Unknown fields are returned under :unknown so tests can refuse them.

  import Bitwise

  @spec traces(binary()) :: map()
  def traces(body), do: request(body, &span/1)

  @spec logs(binary()) :: map()
  def logs(body), do: request(body, &log/1)

  defp request(body, record) do
    [{1, 2, resource_records}] = fields(body)

    Enum.reduce(fields(resource_records), %{resource: nil, scope: nil, records: []}, fn
      {1, 2, resource}, acc ->
        %{acc | resource: for({1, 2, kv} <- fields(resource), do: kv(kv))}

      {2, 2, scoped}, acc ->
        Enum.reduce(fields(scoped), acc, fn
          {1, 2, scope}, inner ->
            %{
              inner
              | scope:
                  Map.new(fields(scope), fn
                    {1, 2, name} -> {:name, name}
                    {2, 2, v} -> {:version, v}
                  end)
            }

          {2, 2, item}, inner ->
            %{inner | records: inner.records ++ [record.(item)]}
        end)
    end)
  end

  defp span(bytes) do
    Enum.reduce(fields(bytes), %{attributes: [], unknown: []}, fn
      {1, 2, id}, acc -> Map.put(acc, :trace_id, id)
      {2, 2, id}, acc -> Map.put(acc, :span_id, id)
      {5, 2, name}, acc -> Map.put(acc, :name, name)
      {6, 0, kind}, acc -> Map.put(acc, :kind, kind)
      {7, 1, start}, acc -> Map.put(acc, :start_ns, start)
      {8, 1, stop}, acc -> Map.put(acc, :end_ns, stop)
      {9, 2, kv}, acc -> %{acc | attributes: acc.attributes ++ [kv(kv)]}
      {15, 2, status}, acc -> Map.put(acc, :status, for({3, 0, code} <- fields(status), do: code))
      other, acc -> %{acc | unknown: [other | acc.unknown]}
    end)
  end

  defp log(bytes) do
    Enum.reduce(fields(bytes), %{attributes: [], unknown: []}, fn
      {1, 1, time}, acc ->
        Map.put(acc, :time_ns, time)

      {2, 0, number}, acc ->
        Map.put(acc, :severity_number, number)

      {3, 2, text}, acc ->
        Map.put(acc, :severity_text, text)

      {5, 2, body}, acc ->
        Map.put(acc, :body, for({1, 2, value} <- fields(body), do: value) |> hd())

      {6, 2, kv}, acc ->
        %{acc | attributes: acc.attributes ++ [kv(kv)]}

      {11, 1, observed}, acc ->
        Map.put(acc, :observed_ns, observed)

      {12, 2, name}, acc ->
        Map.put(acc, :event_name, name)

      other, acc ->
        %{acc | unknown: [other | acc.unknown]}
    end)
  end

  defp kv(bytes) do
    Enum.reduce(fields(bytes), {nil, nil}, fn
      {1, 2, key}, {_, value} -> {key, value}
      {2, 2, any}, {key, _} -> {key, for({1, 2, value} <- fields(any), do: value) |> hd()}
    end)
  end

  @spec fields(binary()) :: [{pos_integer(), 0 | 1 | 2, term()}]
  def fields(<<>>), do: []

  def fields(binary) do
    {tag, rest} = varint(binary, 0, 0)

    {value, rest} =
      case band(tag, 7) do
        0 ->
          varint(rest, 0, 0)

        1 ->
          <<value::little-64, rest::binary>> = rest
          {value, rest}

        2 ->
          {length, rest} = varint(rest, 0, 0)
          <<value::binary-size(^length), rest::binary>> = rest
          {value, rest}
      end

    [{tag >>> 3, band(tag, 7), value} | fields(rest)]
  end

  defp varint(<<0::1, byte::7, rest::binary>>, acc, shift), do: {acc ||| byte <<< shift, rest}

  defp varint(<<1::1, byte::7, rest::binary>>, acc, shift),
    do: varint(rest, acc ||| byte <<< shift, shift + 7)
end
