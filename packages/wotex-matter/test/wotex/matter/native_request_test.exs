defmodule Wotex.Matter.NativeRequestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Error
  alias Wotex.Matter.Native.{Request, Wire}

  test "WMA-B02 escaped bytes include quotes and preserve the final newline reservation" do
    for value <- [
          String.duplicate("x", 131_069),
          String.duplicate(<<0>>, 21_844) <> "12345"
        ] do
      assert {:ok, encoded} = Request.encode(value)
      assert byte_size(encoded) == 131_071
      assert {:ok, ^value} = Wire.frame(encoded)
      assert {:error, %Error{code: :invalid_request}} = Request.encode(value <> "x")
    end

    for value <- ["é", "\"\\\b\t\n\f\r", "\u2028\u2029", 0.0, 1.0e300] do
      assert {:ok, encoded} = Request.encode(value)
      assert {:ok, ^value} = Jason.decode(encoded)
    end
  end

  test "WMA-B02 collection depth 24 and collection size 1024 are exact bounds" do
    nested = Enum.reduce(1..24, nil, fn _, child -> [child] end)
    assert {:ok, encoded} = Request.encode(nested)
    assert {:ok, ^nested} = Wire.frame(encoded)
    assert {:error, %Error{}} = Request.encode([nested])

    for collection <- [List.duplicate(0, 1024), Map.new(1..1024, &{to_string(&1), 0})] do
      assert {:ok, encoded} = Request.encode(collection)
      assert {:ok, ^collection} = Wire.frame(encoded)
    end

    assert {:error, %Error{}} = Request.encode(List.duplicate(0, 1025))
    assert {:error, %Error{}} = Request.encode(Map.new(1..1025, &{to_string(&1), 0}))
  end

  test "WMA-B02 aggregate node accounting includes object keys" do
    full = List.duplicate(%{"k" => nil}, 341)
    last = List.duplicate(%{"k" => nil}, 340) ++ [nil, nil]
    boundary = [full, full, full, last]
    assert {:ok, encoded} = Request.encode(boundary)
    assert {:ok, ^boundary} = Wire.frame(encoded)
    assert {:error, %Error{}} = Request.encode([full, full, full, last ++ [nil]])
  end

  test "WMA-C02 scalars and native tag representations reject lossy or unsupported terms" do
    for value <- [-0x8000000000000000, 0, 0xFFFFFFFFFFFFFFFF] do
      assert {:ok, encoded} = Request.encode(value)
      assert {:ok, ^value} = Wire.frame(encoded)
    end

    assert :ok = Request.validate(%{tag: {:context, 255}, type: :u64, value: 0})
    assert :ok = Request.validate(%{tag: :anonymous, type: :boolean, value: false})

    for value <- [
          -0x8000000000000001,
          0x1_0000000000000000,
          <<255>>,
          [1 | :improper],
          {:context, 256},
          %{"key" => 1, key: 2},
          %{1 => "invalid key"},
          %Wotex.Matter.Error{code: :invalid_request},
          fn -> :invalid end
        ] do
      assert {:error, %Error{code: :invalid_request, effect: :none, details: %{}}} =
               Request.validate(value)
    end

    assert {:error, %Error{code: :invalid_subscription}} = Request.subscription(nil, 1)
  end
end
