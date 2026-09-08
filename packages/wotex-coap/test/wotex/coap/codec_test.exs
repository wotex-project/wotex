defmodule Wotex.CoAP.CodecTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.CoAP.{Block, Codec, Error, Message, Observe}

  test "golden UDP request and extended option encodings" do
    message = %Message{type: :con, code: 1, message_id: 7, token: <<42>>, options: [{11, "test"}]}
    assert {:ok, <<0x41, 1, 0, 7, 42, 0xB4, "test">>} = Codec.encode(message)

    for number <- [0, 12, 13, 268, 269, 65_535], length <- [0, 12, 13, 268, 269] do
      current = %{message | options: [{number, :binary.copy(<<0>>, length)}], payload: "data"}
      assert {:ok, bytes} = Codec.encode(current)
      assert {:ok, ^current} = Codec.decode(bytes)
    end

    assert Codec.uint(0) == <<>>
    assert Codec.uint(256) == <<1, 0>>
  end

  test "malformed fields and incomplete datagrams fail" do
    base = %Message{type: :con, code: 1, message_id: 0}

    for {key, value} <- [
          type: :invalid,
          code: -1,
          code: 256,
          message_id: -1,
          message_id: 65_536,
          token: <<0::72>>,
          token: nil,
          options: nil,
          options: [:bad],
          options: [{-1, "x"}],
          options: List.duplicate({11, "x"}, 65),
          payload: nil,
          payload: :binary.copy(<<0>>, 1153)
        ] do
      assert {:error, %Error{}} = Codec.encode(Map.put(base, key, value))
    end

    assert {:error, _} = Codec.encode(nil)
    assert {:error, _} = Codec.encode(%{base | code: 0, token: <<1>>})
    assert {:error, _} = Codec.encode(%{base | type: :rst})

    for bytes <- [
          <<>>,
          <<0>>,
          <<0, 1, 0, 0>>,
          <<0x49, 1, 0, 0, 0::72>>,
          <<0x48, 1, 0, 0>>,
          <<0x40, 1, 0, 0, 255>>,
          <<0x40, 1, 0, 0, 0xF0>>,
          <<0x40, 1, 0, 0, 0x0F>>,
          <<0x40, 1, 0, 0, 0xD0>>,
          <<0x40, 1, 0, 0, 0xE0, 0>>,
          <<0x40, 1, 0, 0, 0xB4, 1>>,
          <<0x40, 1, 0, 0, 0xE0, 255, 255>>,
          :binary.copy(<<0>>, 1153)
        ] do
      assert {:error, %Error{}} = Codec.decode(bytes)
    end

    assert {:error, %{code: :option_limit}} =
             Codec.decode(<<0x40, 1, 0, 0>> <> :binary.copy(<<0>>, 65))

    assert {:error, _} = Codec.validate_options(%{base | options: [{99, <<>>}]})
    assert {:error, _} = Codec.validate_options(%{base | options: [{12, <<>>}, {12, <<>>}]})
    assert :ok = Codec.validate_options(%{base | options: [{100, "extension"}]})
    assert Codec.option(%{base | options: [{11, "a"}, {11, "b"}]}, 11) == ["a", "b"]
  end

  property "arbitrary datagrams and valid option pairs are bounded and roundtrip" do
    check all(bytes <- binary(max_length: 1200)) do
      result = Codec.decode(bytes)
      assert match?({:ok, %Message{}}, result) or match?({:error, %Error{}}, result)
    end

    check all(
            mid <- integer(0..65_535),
            token <- binary(max_length: 8),
            value <- binary(max_length: 100)
          ) do
      message = %Message{
        type: :non,
        code: 69,
        message_id: mid,
        token: token,
        options: [{100, value}]
      }

      assert {:ok, bytes} = Codec.encode(message)
      assert {:ok, ^message} = Codec.decode(bytes)
    end
  end

  test "Block validates continuity, size and aggregate budgets" do
    for size <- [16, 32, 64, 128, 256, 512, 1024], n <- [0, 1, 1_048_575], more <- [true, false] do
      block = %Block{number: n, more: more, size: size}
      assert {:ok, encoded} = Block.encode(block)
      assert {:ok, ^block} = Block.decode(encoded)
    end

    assert {:error, _} = Block.decode(<<7>>)
    assert {:error, _} = Block.decode(<<0::32>>)
    assert {:error, _} = Block.encode(nil)
    block = %Block{number: 0, more: true, size: 16}
    data = :binary.copy(<<1>>, 16)
    assert {:ok, ^data, :more} = Block.append(<<>>, block, data, 32)
    assert {:ok, _, :complete} = Block.append(data, %{block | number: 1, more: false}, <<2>>, 32)
    assert {:error, _} = Block.append(data, block, data, 32)
    assert {:error, _} = Block.append(<<>>, block, <<1>>, 32)
    assert {:error, _} = Block.append(<<>>, block, data, 15)
    assert {:error, _} = Block.append(nil, block, data, 15)
    assert Observe.fresh?(0xFFFFFF, 0, 0)
    refute Observe.fresh?(10, 9, 0)
    refute Observe.fresh?(1, 1, 128_000)
    assert Observe.fresh?(1, 1, 128_001)
    refute Observe.fresh?(-1, 0, 0)
  end
end
