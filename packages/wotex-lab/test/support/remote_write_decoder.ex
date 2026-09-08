defmodule Wotex.Lab.Test.RemoteWriteDecoder do
  @moduledoc false

  # An independent protobuf reader for `prometheus.WriteRequest` bodies so the
  # hand-written encoder is proven against a second implementation of the
  # same field numbers (timeseries=1; labels=1, samples=2; name=1, value=2;
  # value=1 double, timestamp=2 int64). Special doubles are returned as their
  # 64-bit patterns because the BEAM has no NaN float.

  import Bitwise

  alias Wotex.Lab.Metrics.Snappy

  @spec decode_body(binary()) :: [
          %{labels: [{String.t(), String.t()}], samples: [{integer(), term()}]}
        ]
  def decode_body(body) do
    {:ok, raw} = Snappy.decompress(body)
    decode_request(raw)
  end

  @spec decode_request(binary()) :: [map()]
  def decode_request(raw) do
    raw
    |> fields()
    |> Enum.map(fn {1, 2, bytes} -> timeseries(bytes) end)
  end

  defp timeseries(bytes) do
    Enum.reduce(fields(bytes), %{labels: [], samples: []}, fn
      {1, 2, label}, acc -> %{acc | labels: acc.labels ++ [label(label)]}
      {2, 2, sample}, acc -> %{acc | samples: acc.samples ++ [sample(sample)]}
    end)
  end

  defp label(bytes) do
    Enum.reduce(fields(bytes), {nil, nil}, fn
      {1, 2, name}, {_name, value} -> {name, value}
      {2, 2, value}, {name, _value} -> {name, value}
    end)
  end

  defp sample(bytes) do
    Enum.reduce(fields(bytes), {nil, nil}, fn
      {1, 1, <<pattern::unsigned-little-64>> = double}, {timestamp, _value} ->
        {timestamp, float(double, pattern)}

      {2, 0, varint}, {_timestamp, value} ->
        {if(varint >= 1 <<< 63, do: varint - (1 <<< 64), else: varint), value}
    end)
    |> then(fn {timestamp, value} -> {timestamp, value} end)
  end

  defp float(double, pattern) do
    case double do
      <<value::little-float-64>> -> value
      _special -> {:special, pattern}
    end
  end

  defp fields(<<>>), do: []

  defp fields(bytes) do
    {key, rest} = varint(bytes)
    number = key >>> 3
    wire = key &&& 7

    case wire do
      0 ->
        {value, rest} = varint(rest)
        [{number, 0, value} | fields(rest)]

      1 ->
        <<value::binary-size(8), rest::binary>> = rest
        [{number, 1, value} | fields(rest)]

      2 ->
        {length, rest} = varint(rest)
        <<value::binary-size(^length), rest::binary>> = rest
        [{number, 2, value} | fields(rest)]
    end
  end

  defp varint(bytes, shift \\ 0, acc \\ 0)

  defp varint(<<0::1, byte::7, rest::binary>>, shift, acc), do: {acc ||| byte <<< shift, rest}

  defp varint(<<1::1, byte::7, rest::binary>>, shift, acc),
    do: varint(rest, shift + 7, acc ||| byte <<< shift)
end
