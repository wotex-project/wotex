defmodule Wotex.CoAP.Block do
  @moduledoc """
  Represents an RFC 7959 Block1 or Block2 option for CoAP over UDP.

  A `t:t/0` contains the zero-based block number, the more-blocks flag, and a
  power-of-two block size from 16 through 1024 bytes. `decode/1` accepts the
  zero-to-three-byte option encoding and rejects the UDP-reserved SZX value 7.
  `encode/1` emits the minimal unsigned integer representation.

  `append/4` performs bounded sequential response reassembly. It verifies the
  expected byte offset, full size of non-final blocks, final-block size, and an
  explicit aggregate byte limit before allocating the combined binary. It does
  not reorder blocks or recover a changed representation. Those transfer-level
  decisions belong to `Wotex.CoAP.Blockwise`.
  """

  import Bitwise
  alias Wotex.CoAP.{Codec, Error}
  @enforce_keys [:number, :more, :size]
  defstruct [:number, :more, :size]

  @type t :: %__MODULE__{
          number: 0..1_048_575,
          more: boolean(),
          size: 16 | 32 | 64 | 128 | 256 | 512 | 1024
        }

  @doc "Decodes a zero-to-three-byte Block option; UDP reserves SZX=7."
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(data) when is_binary(data) and byte_size(data) <= 3 do
    value = :binary.decode_unsigned(data)
    szx = band(value, 7)

    if szx == 7,
      do: {:error, Error.new(:invalid_block_size)},
      else: {:ok, %__MODULE__{number: bsr(value, 4), more: band(value, 8) != 0, size: bsl(16, szx)}}
  end

  def decode(_), do: {:error, Error.new(:invalid_block)}

  @doc "Encodes a validated Block option with minimal integer encoding."
  @spec encode(t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%__MODULE__{number: n, more: more, size: size})
      when is_integer(n) and n in 0..1_048_575 and is_boolean(more) and
             size in [16, 32, 64, 128, 256, 512, 1024] do
    szx = Enum.find_index([16, 32, 64, 128, 256, 512, 1024], &(&1 == size))
    {:ok, Codec.uint(bor(bsl(n, 4), bor(if(more, do: 8, else: 0), szx)))}
  end

  def encode(_), do: {:error, Error.new(:invalid_block)}

  @doc "Appends a consecutive block under an explicit aggregate byte limit."
  @spec append(binary(), t(), binary(), pos_integer()) ::
          {:ok, binary(), :more | :complete} | {:error, Error.t()}
  def append(acc, %__MODULE__{} = block, payload, limit)
      when is_binary(acc) and is_binary(payload) and is_integer(limit) and limit > 0 do
    with {:ok, _} <- encode(block) do
      cond do
        block.number * block.size != byte_size(acc) ->
          {:error, Error.new(:block_out_of_order)}

        byte_size(payload) > block.size or (block.more and byte_size(payload) != block.size) ->
          {:error, Error.new(:invalid_block_payload)}

        byte_size(acc) + byte_size(payload) > limit ->
          {:error, Error.new(:body_limit)}

        true ->
          {:ok, acc <> payload, if(block.more, do: :more, else: :complete)}
      end
    end
  end

  def append(_, _, _, _), do: {:error, Error.new(:invalid_block)}
end
