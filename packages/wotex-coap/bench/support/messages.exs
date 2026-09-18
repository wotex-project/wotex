defmodule Wotex.CoAP.Bench.Messages do
  @moduledoc false

  # Synthetic CoAP messages, representations, Link Format bodies and a pure
  # in-process peer for blockwise transfers. Replies are precomputed per block
  # number, so the exchange callback does only the option lookup a peer needs.

  alias Wotex.CoAP.{Block, Codec, Message}

  @token <<0x5A, 0x1C, 0x93, 0x07, 0x2E, 0x61, 0xB4, 0x08>>
  @etag <<0x0B, 0xAD, 0xCA, 0xFE>>
  @octet_stream 42
  @json 50

  @spec token() :: binary()
  def token, do: @token

  @spec etag() :: binary()
  def etag, do: @etag

  @spec body_sizes() :: %{String.t() => pos_integer()}
  def body_sizes, do: %{"1 KiB" => 1024, "16 KiB" => 16_384, "256 KiB" => 262_144}

  @spec body(pos_integer()) :: binary()
  def body(size) do
    pattern = :erlang.list_to_binary(Enum.to_list(0..255))
    binary_part(:binary.copy(pattern, div(size, 256) + 1), 0, size)
  end

  @spec json(non_neg_integer()) :: binary()
  def json(members) do
    {:ok, json} = Wotex.JSON.encode(object(members))
    json
  end

  @spec object(non_neg_integer()) :: map()
  def object(members), do: Map.new(1..members//1, &{"m#{&1}", &1 * 0.5})

  @spec request(1..4, [{non_neg_integer(), binary()}], binary()) :: Message.t()
  def request(code, options, payload \\ <<>>) do
    %Message{
      type: :con,
      code: code,
      message_id: 0x7D34,
      token: @token,
      options: options,
      payload: payload
    }
  end

  @spec reply(64..191, [{non_neg_integer(), binary()}], binary()) :: Message.t()
  def reply(code, options, payload \\ <<>>) do
    %Message{
      type: :ack,
      code: code,
      message_id: 0x7D34,
      token: @token,
      options: options,
      payload: payload
    }
  end

  @spec block(non_neg_integer(), boolean(), pos_integer()) :: binary()
  def block(number, more, size) do
    {:ok, value} = Block.encode(%Block{number: number, more: more, size: size})
    value
  end

  # A body that fits one block is sent without Block2 and Size2.
  @spec download_replies(binary(), pos_integer()) :: %{non_neg_integer() => Message.t()}
  def download_replies(body, size) when byte_size(body) <= size,
    do: %{0 => reply(69, [{4, @etag}, {12, Codec.uint(@octet_stream)}], body)}

  def download_replies(body, size) do
    total = byte_size(body)

    Map.new(0..(div(total + size - 1, size) - 1), fn number ->
      offset = number * size
      length = min(size, total - offset)

      options = [
        {4, @etag},
        {12, Codec.uint(@octet_stream)},
        {23, block(number, offset + length < total, size)},
        {28, Codec.uint(total)}
      ]

      {number, reply(69, options, binary_part(body, offset, length))}
    end)
  end

  @spec upload_replies(pos_integer(), pos_integer()) :: %{non_neg_integer() => Message.t()}
  def upload_replies(total, size) do
    last = div(total + size - 1, size) - 1

    Map.new(0..last, fn number ->
      more = number < last
      {number, reply(if(more, do: 95, else: 68), [{27, block(number, more, size)}])}
    end)
  end

  @spec peer(non_neg_integer()) :: (Message.t(), map() -> {{:ok, Message.t()}, map()})
  def peer(option) do
    fn request, replies ->
      [value] = Codec.option(request, option)
      {:ok, %Block{number: number}} = Block.decode(value)
      {{:ok, Map.fetch!(replies, number)}, replies}
    end
  end

  @spec json_format() :: non_neg_integer()
  def json_format, do: @json

  @spec links(pos_integer()) :: binary()
  def links(count) do
    resources =
      Enum.map(1..(count - 1)//1, fn index ->
        suffix = String.pad_leading(Integer.to_string(index), 3, "0")

        ~s(</properties/p#{suffix}>;rt="example.temperature";if="core.s";ct=50;sz=64;obs;) <>
          ~s(title="Room \\"east\\" #{suffix}")
      end)

    Enum.join([~s(</.well-known/wot>;rt="wot.thing";ct=432) | resources], ",")
  end
end
