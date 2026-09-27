defmodule Wotex.Zigbee.Frame do
  @moduledoc """
  Bounded TI ZNP Monitor/Test UART frames.

  This codec follows the CC26x2 SDK 2.30.00.34 ZNP interface and the bundled
  Monitor/Test API SWRA198 revision 1.14: SOF `0xFE`, one payload length byte,
  Cmd0/Cmd1, payload, and XOR FCS. It performs no serial I/O. `feed/3`
  resynchronizes after garbage or a bad FCS and preserves incomplete tails.
  """

  import Bitwise

  alias Wotex.Zigbee.Error

  @enforce_keys [:type, :subsystem, :id, :payload]
  defstruct [:type, :subsystem, :id, :payload]

  @type type :: :sreq | :srsp | :areq
  @type t :: %__MODULE__{
          type: type(),
          subsystem: 0..31,
          id: 0..255,
          payload: binary()
        }

  @doc "Encodes one supported Monitor/Test frame with at most 250 data bytes."
  @spec encode(t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{type: type, subsystem: subsystem, id: id, payload: payload})
      when type in [:sreq, :srsp, :areq] and is_integer(subsystem) and subsystem in 0..31 and
             is_integer(id) and id in 0..255 and is_binary(payload) and byte_size(payload) <= 250 do
    cmd0 = type_bits(type) ||| subsystem
    body = <<byte_size(payload), cmd0, id, payload::binary>>
    {:ok, <<0xFE, body::binary, checksum(body)>>}
  end

  def encode(_), do: {:error, %Error{kind: :invalid_frame, operation: :encode}}

  @doc """
  Parses a bounded serial chunk and returns frames, the incomplete tail and
  the number of discarded malformed bytes or frames. A chunk that would
  exceed `max_buffer` is rejected before allocation of a combined buffer.
  """
  @spec feed(binary(), binary(), pos_integer()) ::
          {:ok, [t()], binary(), non_neg_integer()} | {:error, Error.t()}
  def feed(buffer, chunk, max_buffer \\ 4_096)

  def feed(buffer, chunk, max_buffer)
      when is_binary(buffer) and is_binary(chunk) and is_integer(max_buffer) and
             max_buffer >= 5 and byte_size(buffer) + byte_size(chunk) <= max_buffer do
    parse(buffer <> chunk, [], 0)
  end

  def feed(_, _, _), do: {:error, %Error{kind: :overload, operation: :feed}}

  defp parse(<<>>, frames, faults), do: {:ok, Enum.reverse(frames), <<>>, faults}

  defp parse(bytes, frames, faults) do
    case :binary.match(bytes, <<0xFE>>) do
      :nomatch ->
        {:ok, Enum.reverse(frames), <<>>, faults + byte_size(bytes)}

      {offset, 1} when offset > 0 ->
        <<_::binary-size(^offset), rest::binary>> = bytes
        parse(rest, frames, faults + offset)

      {0, 1} ->
        parse_frame(bytes, frames, faults)
    end
  end

  defp parse_frame(bytes, frames, faults) when byte_size(bytes) < 5,
    do: {:ok, Enum.reverse(frames), bytes, faults}

  defp parse_frame(<<0xFE, length, cmd0, id, tail::binary>> = bytes, frames, faults) do
    cond do
      length > 250 ->
        <<_, rest::binary>> = bytes
        parse(rest, frames, faults + 1)

      byte_size(tail) < length + 1 ->
        {:ok, Enum.reverse(frames), bytes, faults}

      true ->
        <<payload::binary-size(^length), fcs, rest::binary>> = tail
        body = <<length, cmd0, id, payload::binary>>

        case {type_from_bits(cmd0 &&& 0xE0), checksum(body) == fcs} do
          {{:ok, type}, true} ->
            frame = %__MODULE__{type: type, subsystem: cmd0 &&& 0x1F, id: id, payload: payload}
            parse(rest, [frame | frames], faults)

          _ ->
            <<_, after_sof::binary>> = bytes
            parse(after_sof, frames, faults + 1)
        end
    end
  end

  defp checksum(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.reduce(0, &bxor/2)
  end

  defp type_bits(:sreq), do: 0x20
  defp type_bits(:areq), do: 0x40
  defp type_bits(:srsp), do: 0x60

  defp type_from_bits(0x20), do: {:ok, :sreq}
  defp type_from_bits(0x40), do: {:ok, :areq}
  defp type_from_bits(0x60), do: {:ok, :srsp}
  defp type_from_bits(_), do: :error
end
