defmodule Wotex.CoAP.Codec do
  @moduledoc "Bounded RFC 7252 UDP encoding and parsing; malformed input returns structured errors."

  alias Wotex.CoAP.{Error, Message}
  @types %{con: 0, non: 1, ack: 2, rst: 3}
  @reverse %{0 => :con, 1 => :non, 2 => :ack, 3 => :rst}
  @maximum 1152
  @single [3, 6, 7, 12, 14, 17, 23, 27, 28, 35, 39, 60]
  @known [1, 3, 4, 5, 6, 7, 8, 11, 12, 14, 15, 17, 20, 23, 27, 28, 35, 39, 60]
  @lengths %{
    1 => 0..8,
    3 => 1..255,
    4 => 1..8,
    5 => 0..0,
    6 => 0..3,
    7 => 0..2,
    8 => 0..255,
    11 => 0..255,
    12 => 0..2,
    14 => 0..4,
    15 => 0..255,
    17 => 0..2,
    20 => 0..255,
    23 => 0..3,
    27 => 0..3,
    28 => 0..4,
    35 => 1..1034,
    39 => 1..255,
    60 => 0..4,
    292 => 0..8
  }

  @doc "Encodes a validated message with canonical option ordering, retaining repeats."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%Message{} = message) do
    with :ok <- valid(message),
         {:ok, options} <- encode_options(Enum.sort_by(message.options, &elem(&1, 0)), 0, []) do
      payload = if message.payload == <<>>, do: <<>>, else: <<255, message.payload::binary>>

      data =
        IO.iodata_to_binary([
          <<1::2, @types[message.type]::2, byte_size(message.token)::4, message.code,
            message.message_id::16>>,
          message.token,
          options,
          payload
        ])

      if byte_size(data) <= @maximum, do: {:ok, data}, else: failure(:message_too_large)
    end
  end

  def encode(_), do: failure(:invalid_message)

  @doc "Parses a complete UDP datagram; no trailing payload marker or unchecked allocation."
  @spec decode(term()) :: {:ok, Message.t()} | {:error, Error.t()}
  def decode(data) when is_binary(data) and byte_size(data) > @maximum,
    do: failure(:message_too_large)

  def decode(<<1::2, type::2, size::4, code, mid::16, token::binary-size(size), rest::binary>>)
      when size <= 8 do
    with {:ok, options, payload} <- decode_options(rest, 0, [], 0),
         message = %Message{
           type: @reverse[type],
           code: code,
           message_id: mid,
           token: token,
           options: options,
           payload: payload
         },
         :ok <- valid(message) do
      {:ok, message}
    end
  end

  def decode(_), do: failure(:invalid_header)

  @doc "Rejects unsupported critical options and duplicate nonrepeatable options."
  @spec validate_options(term()) :: :ok | {:error, Error.t()}
  def validate_options(%Message{} = message) do
    with :ok <- valid(message), do: semantics(message.options)
  end

  def validate_options(_), do: failure(:invalid_message)

  defp semantics(options) do
    cond do
      Enum.any?(options, fn {number, _} -> rem(number, 2) == 1 and number not in @known end) ->
        failure(:unsupported_critical_option)

      Enum.any?(@single, fn number -> Enum.count(options, &(elem(&1, 0) == number)) > 1 end) ->
        failure(:duplicate_option)

      Enum.any?(options, fn {number, value} ->
        case Map.fetch(@lengths, number) do
          {:ok, range} -> byte_size(value) not in range
          :error -> false
        end
      end) ->
        failure(:invalid_option_length)

      true ->
        :ok
    end
  end

  @doc "Encodes an unsigned option integer in minimal form."
  @spec uint(non_neg_integer()) :: binary()
  def uint(0), do: <<>>
  def uint(value) when is_integer(value) and value > 0, do: :binary.encode_unsigned(value)

  @doc "Returns numeric option values, preserving source order."
  @spec option(Message.t(), non_neg_integer()) :: [binary()]
  def option(%Message{options: options}, number), do: for({^number, value} <- options, do: value)

  defp valid(message) do
    with :ok <- valid_header(message) do
      cond do
        not is_binary(message.payload) ->
          failure(:invalid_payload)

        not is_list(message.options) or length(message.options) > 64 ->
          failure(:option_limit)

        not Enum.all?(message.options, &valid_option?/1) ->
          failure(:invalid_option)

        message.code == 0 and
            (message.token != <<>> or message.options != [] or message.payload != <<>>) ->
          failure(:invalid_empty_message)

        message.type == :rst and message.code != 0 ->
          failure(:invalid_reset)

        true ->
          :ok
      end
    end
  end

  defp valid_header(message) do
    cond do
      not Map.has_key?(@types, message.type) ->
        failure(:invalid_type)

      not is_integer(message.code) or message.code not in 0..255 ->
        failure(:invalid_code)

      not is_integer(message.message_id) or message.message_id not in 0..65_535 ->
        failure(:invalid_message_id)

      not is_binary(message.token) or byte_size(message.token) > 8 ->
        failure(:invalid_token)

      true ->
        :ok
    end
  end

  defp valid_option?({number, value}),
    do:
      is_integer(number) and number in 0..65_535 and is_binary(value) and
        byte_size(value) <= @maximum

  defp valid_option?(_), do: false

  defp encode_options([], _, acc), do: {:ok, Enum.reverse(acc)}

  defp encode_options([{number, value} | tail], previous, acc) do
    {delta, extra_delta} = extended(number - previous)
    {length, extra_length} = extended(byte_size(value))

    encoded = [<<delta::4, length::4>>, extra_delta, extra_length, value]
    encode_options(tail, number, [encoded | acc])
  end

  defp extended(n) when n < 13, do: {n, <<>>}
  defp extended(n) when n < 269, do: {13, <<n - 13>>}
  defp extended(n), do: {14, <<n - 269::16>>}

  defp decode_options(<<>>, _, acc, _), do: {:ok, Enum.reverse(acc), <<>>}
  defp decode_options(<<255>>, _, _, _), do: failure(:empty_payload_marker)
  defp decode_options(<<255, payload::binary>>, _, acc, _), do: {:ok, Enum.reverse(acc), payload}
  defp decode_options(_, _, _, 64), do: failure(:option_limit)

  defp decode_options(<<delta::4, length::4, rest::binary>>, previous, acc, count) do
    with {:ok, delta, rest} <- expand(delta, rest),
         {:ok, size, rest} <- expand(length, rest),
         true <- byte_size(rest) >= size and previous + delta <= 65_535 do
      value = binary_part(rest, 0, size)
      tail = binary_part(rest, size, byte_size(rest) - size)
      decode_options(tail, previous + delta, [{previous + delta, value} | acc], count + 1)
    else
      _ -> failure(:invalid_option)
    end
  end

  defp expand(n, rest) when n < 13, do: {:ok, n, rest}
  defp expand(13, <<extra, rest::binary>>), do: {:ok, extra + 13, rest}
  defp expand(14, <<extra::16, rest::binary>>), do: {:ok, extra + 269, rest}
  defp expand(_, _), do: failure(:invalid_option)
  defp failure(code), do: {:error, Error.new(code)}
end
