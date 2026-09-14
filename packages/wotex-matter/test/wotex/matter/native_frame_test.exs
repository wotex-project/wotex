defmodule Wotex.Matter.NativeFrameTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.{Error, Native.Wire}

  test "WMA-B02 bounds JSON representation depth separately from TLV nesting" do
    assert {:ok, _} = Wire.frame(nested(24))
    assert {:error, %Error{code: :invalid_frame}} = Wire.frame(nested(25))
  end

  test "WMA-B02 counts collection entries and aggregate keys and values" do
    assert {:ok, _} = Wire.frame(Jason.encode!(List.duplicate(0, 1024)))

    assert {:error, %Error{code: :invalid_frame}} =
             Wire.frame(Jason.encode!(List.duplicate(0, 1025)))

    # Root, three arrays with 1024 scalars each, and 1020 final scalars: 4096 nodes.
    boundary = List.duplicate(List.duplicate(0, 1024), 3) ++ List.duplicate(0, 1020)
    assert {:ok, _} = Wire.frame(Jason.encode!(boundary))
    assert {:error, %Error{code: :invalid_frame}} = Wire.frame(Jason.encode!([0 | boundary]))

    # Each object member consumes both a key and a value in native SAX parsing.
    object = Map.new(1..1024, &{Integer.to_string(&1), 0})
    assert {:error, %Error{code: :invalid_frame}} = Wire.frame(Jason.encode!([object, object]))
  end

  test "WMA-B02 retains uint64 precision and rejects duplicate keys and malformed input" do
    assert {:ok, %{"value" => 0xFFFFFFFFFFFFFFFF}} =
             Wire.frame(~s({"value":18446744073709551615}))

    for input <- [~s({"ok":false,"ok":true}), ~s({"value":1e999}), <<255>>, "{", nil] do
      assert {:error, %Error{code: :invalid_frame}} = Wire.frame(input)
    end

    assert {:ok, _} = Wire.frame(~s("#{String.duplicate("x", 131_069)}"))

    assert {:error, %Error{code: :invalid_frame}} =
             Wire.frame(~s("#{String.duplicate("x", 131_070)}"))
  end

  defp nested(depth), do: String.duplicate("[", depth) <> "0" <> String.duplicate("]", depth)
end
