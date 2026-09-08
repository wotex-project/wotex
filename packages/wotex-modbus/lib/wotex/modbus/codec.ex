defmodule Wotex.Modbus.Codec do
  @moduledoc "Bounded Modbus TCP framing and strict function-specific response validation."

  import Bitwise
  alias Wotex.Modbus.{Command, Error}

  @type frame :: %{transaction_id: 0..65_535, unit_id: 0..255, pdu: binary()}

  @doc "Encodes a validated command as an ADU with an explicit Transaction Identifier."
  @spec encode(Command.t(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%Command{} = command, transaction_id)
      when is_integer(transaction_id) and transaction_id in 0..65_535 do
    with :ok <- Command.validate(command) do
      payload = pdu(command)
      length = byte_size(payload) + 1
      {:ok, <<transaction_id::16, 0::16, length::16, command.address.unit_id, payload::binary>>}
    end
  end

  def encode(_, _), do: {:error, Error.new(:invalid_command)}

  @doc "Decodes one bounded ADU; returns remaining bytes without consuming another frame."
  @spec decode(term()) :: {:ok, frame(), binary()} | :more | {:error, Error.t()}
  def decode(data) when is_binary(data) and byte_size(data) < 6, do: :more

  def decode(<<_transaction::16, protocol::16, length::16, _::binary>>)
      when protocol != 0 or length not in 2..254,
      do: {:error, Error.new(:invalid_mbap)}

  def decode(<<transaction::16, 0::16, length::16, rest::binary>>) do
    if byte_size(rest) < length do
      :more
    else
      <<unit, data::binary>> = rest
      pdu = binary_part(data, 0, length - 1)
      tail = binary_part(data, length - 1, byte_size(data) - length + 1)
      {:ok, %{transaction_id: transaction, unit_id: unit, pdu: pdu}, tail}
    end
  end

  def decode(_), do: {:error, Error.new(:invalid_frame)}

  @doc "Validates correlation, byte counts, padding, exception shape and write echoes."
  @spec response(frame(), Command.t(), non_neg_integer()) ::
          {:ok, [non_neg_integer() | boolean()] | :written} | {:error, Error.t()}
  def response(frame, command, transaction_id) do
    with :ok <- Command.validate(command),
         do: correlated_response(frame, command, transaction_id)
  end

  defp correlated_response(
         %{transaction_id: tid, unit_id: unit, pdu: payload},
         %Command{address: %{unit_id: unit}} = cmd,
         tid
       )
       when is_integer(tid) and tid in 0..65_535 and is_binary(payload) and
              byte_size(payload) in 1..253,
       do: parse_response(payload, cmd)

  defp correlated_response(_, _, _), do: {:error, Error.new(:response_mismatch)}

  defp pdu(%Command{function: f, address: a}) when f in [1, 2, 3, 4],
    do: <<f, a.offset::16, a.quantity::16>>

  defp pdu(%Command{function: 5, address: a, values: [v]}),
    do: <<5, a.offset::16, if(v, do: 0xFF00, else: 0)::16>>

  defp pdu(%Command{function: 6, address: a, values: [v]}), do: <<6, a.offset::16, v::16>>

  defp pdu(%Command{function: 15, address: a, values: values}) do
    bits = pack_bits(values)
    <<15, a.offset::16, a.quantity::16, byte_size(bits), bits::binary>>
  end

  defp pdu(%Command{function: 16, address: a, values: values}) do
    registers = for value <- values, into: <<>>, do: <<value::16>>
    <<16, a.offset::16, a.quantity::16, byte_size(registers), registers::binary>>
  end

  defp pack_bits(values) do
    values
    |> Enum.chunk_every(8)
    |> Enum.map(fn group ->
      group
      |> Enum.with_index()
      |> Enum.reduce(0, fn {v, i}, byte ->
        if v, do: bor(byte, bsl(1, i)), else: byte
      end)
    end)
    |> :erlang.list_to_binary()
  end

  defp parse_response(<<exception, code>>, %Command{function: f}) when exception == f + 128,
    do: {:error, Error.new(:remote_exception, nil, %{exception_code: code, function: f})}

  defp parse_response(<<f, count, data::binary>>, %Command{function: f, address: a})
       when f in [3, 4] and count == a.quantity * 2 and byte_size(data) == count,
       do: {:ok, for(<<value::16 <- data>>, do: value)}

  defp parse_response(<<f, count, data::binary>>, %Command{function: f, address: a})
       when f in [1, 2] and count == div(a.quantity + 7, 8) and byte_size(data) == count do
    unused = rem(a.quantity, 8)

    if unused == 0 or bsr(:binary.last(data), unused) == 0 do
      {:ok,
       for(
         index <- 0..(a.quantity - 1),
         do: band(:binary.at(data, div(index, 8)), bsl(1, rem(index, 8))) != 0
       )}
    else
      {:error, Error.new(:invalid_padding)}
    end
  end

  defp parse_response(<<f, offset::16, quantity::16>>, %Command{function: f, address: a})
       when f in [15, 16] and offset == a.offset and quantity == a.quantity,
       do: {:ok, :written}

  defp parse_response(payload, %Command{function: f} = command) when f in [5, 6] do
    if payload == pdu(command),
      do: {:ok, :written},
      else: {:error, Error.new(:response_mismatch)}
  end

  defp parse_response(_, _), do: {:error, Error.new(:invalid_response)}
end
