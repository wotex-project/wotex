defmodule Wotex.OPCUA.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Value

  test "explicit variants avoid numeric inference and retain binary values" do
    assert {:ok, %{type: "Double", value: 1.5}} = Value.encode(1.5, "Double")
    assert {:ok, %{type: "UInt16", value: 42}} = Value.encode(%{type: "UInt16", value: 42}, nil)

    assert {:ok, %{type: "String", value: nil}} =
             Value.encode(%{"type" => "String", "value" => nil}, nil)

    assert {:ok, %{value: "AP8="}} = Value.encode(<<0, 255>>, "ByteString")

    assert {:ok, %{type: "ByteString", array: true, value: ["AP8=", nil, ""]}} =
             Value.encode(%{type: "ByteString", array: true, value: [<<0, 255>>, nil, <<>>]}, nil)

    assert {:ok, %{type: "ByteString", array: true, value: nil}} =
             Value.encode(%{type: "ByteString", array: true, value: nil}, nil)

    assert {:ok, %{type: "ByteString", array: true, value: ["AP8="]}} =
             Value.encode(%{"type" => "ByteString", "array" => true, "value" => [<<0, 255>>]}, nil)

    assert {:ok, %{type: "ByteString", array: true, value: ["AP8="], dimensions: [1, 1]}} =
             Value.encode(
               %{
                 "type" => "ByteString",
                 "array" => true,
                 "value" => [<<0, 255>>],
                 "dimensions" => [1, 1]
               },
               nil
             )

    for invalid <- [
          %{type: "ByteString", array: true, value: List.duplicate(<<0>>, 1025)},
          %{type: "ByteString", array: true, value: [<<0>>], dimensions: [1, 2]},
          %{type: "ByteString", array: true, value: [<<0>>], extra: true},
          %{"type" => "ByteString", "array" => true, "value" => [<<0>>], "extra" => true}
        ] do
      assert {:error, %{code: :variant_type_required}} = Value.encode(invalid, nil)
    end

    for {typed, value} <- [
          {%{type: "Int64", array: true, value: [-9_223_372_036_854_775_808, 0]},
           [-9_223_372_036_854_775_808, 0]},
          {%{"type" => "Boolean", "array" => true, "value" => [true, false]}, [true, false]},
          {%{type: "String", array: true, value: ["a", nil], dimensions: [1, 2]}, ["a", nil]},
          {%{type: "Float", array: true, value: nil}, nil}
        ] do
      assert {:ok, %{array: true, value: ^value}} = Value.encode(typed, nil)
    end

    for invalid <- [
          %{type: "Byte", array: true, value: [256]},
          %{type: "Double", array: true, value: [1]},
          %{type: "Guid", array: true, value: ["72962b91-fa75-4ae6-8d28-b404dc7daf63"]},
          %{type: "Int32", array: true, value: [1, 2], dimensions: [2]}
        ] do
      assert {:error, %{code: :variant_type_required}} = Value.encode(invalid, nil)
    end

    assert {:error, _} = Value.encode(65_536, "UInt16")
    assert {:error, _} = Value.encode(1.5, nil)

    assert {:ok, 1.5, %{opcua_type: "Double", status: 0}} =
             Value.result(%{"type" => "Double", "value" => 1.5, "status" => 0})

    assert {:ok, <<0, 255>>, _} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => %{"type" => "ByteString", "base64" => "AP8="}
             })

    assert {:ok, [<<0, 255>>, nil, <<>>], %{opcua_type: "ByteString", status: 0}} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => [
                 %{"type" => "ByteString", "base64" => "AP8="},
                 nil,
                 %{"type" => "ByteString", "base64" => ""}
               ]
             })

    assert {:error, %{code: :invalid_bytestring}} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => [%{"type" => "ByteString", "base64" => "AA==", "extra" => true}]
             })

    assert {:error, %{code: :response_limit}} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => List.duplicate(nil, 1025)
             })

    large = %{"type" => "ByteString", "base64" => Base.encode64(:binary.copy(<<0>>, 65_536))}

    assert {:error, %{code: :response_limit}} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => List.duplicate(large, 17)
             })

    assert {:error, %{code: :response_limit}} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => %{
                 "type" => "ByteString",
                 "base64" => Base.encode64(:binary.copy(<<0>>, 65_537))
               }
             })

    assert {:error, _} =
             Value.result(%{
               "type" => "ByteString",
               "status" => 0,
               "value" => %{"type" => "ByteString", "base64" => "invalid"}
             })

    assert {:error, %{code: :bad_status}} =
             Value.result(%{"type" => "Double", "value" => nil, "status" => 0x80000000})

    assert {:error, _} = Value.result(%{"status" => "invalid"})
    assert {:ok, "written", %{}} = Value.result("written")
  end
end
