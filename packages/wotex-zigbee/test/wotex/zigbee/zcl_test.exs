defmodule Wotex.Zigbee.ZCLTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, ZCL}

  test "bounded read request preserves manufacturer, direction and sequence" do
    assert {:ok, <<0, 7, 0, 0x34, 0x12>>} =
             ZCL.read_attributes([0x1234], 7, :client_to_server)

    assert {:ok, <<0x0C, 0x34, 0x12, 8, 0, 1, 0>>} =
             ZCL.read_attributes([1], 8, :server_to_client, 0x1234)

    assert {:error, %Error{}} = ZCL.read_attributes([], 1, :client_to_server)
    assert {:error, %Error{}} = ZCL.read_attributes([0x10000], 1, :client_to_server)
    assert {:error, %Error{}} = ZCL.read_attributes([1], 256, :client_to_server)
    assert {:error, %Error{}} = ZCL.read_attributes([1], 1, :unknown)
    assert {:error, %Error{}} = ZCL.read_attributes([1], 1, :client_to_server, -1)
    assert {:error, %Error{}} = ZCL.read_attributes(Enum.to_list(1..33), 1, :client_to_server)
  end

  test "read responses keep per-record errors, null, typed values and opaque extensions" do
    bytes =
      <<0x0C, 0x34, 0x12, 9, 1, 1::little-16, 0, 0x20, 42, 2::little-16, 0x86, 3::little-16, 0,
        0x42, 0xFF, 4::little-16, 0, 0xF0, 0xAA, 0xBB>>

    assert {:ok, decoded} = ZCL.decode_attributes(bytes)
    assert decoded.command == :read_response
    assert decoded.manufacturer == 0x1234
    assert decoded.direction == :server_to_client
    assert decoded.sequence == 9
    assert [first, second, third, fourth] = decoded.attributes
    assert first == %{id: 1, status: :success, type: 0x20, value: 42, raw: <<42>>}
    assert second == %{id: 2, status: {:error, 0x86}, type: nil, value: nil, raw: nil}
    assert third.value == :null
    assert fourth.value == {:unsupported, 0xF0}
    assert fourth.raw == <<0xAA, 0xBB>>
  end

  test "reports decode finite scalar and string values" do
    bytes =
      <<0, 11, 0x0A, 1::little-16, 0x10, 1, 2::little-16, 0x21, 0x34, 0x12, 3::little-16, 0x28,
        -2::signed-8, 4::little-16, 0x42, 3, "abc">>

    assert {:ok, %{command: :report, sequence: 11, attributes: attributes}} =
             ZCL.decode_attributes(bytes)

    assert Enum.map(attributes, & &1.value) == [true, 0x1234, -2, "abc"]

    more =
      <<0, 12, 0x0A, 5::little-16, 0x23, 0x12345678::little-32, 6::little-16, 0x29,
        -300::little-signed-16, 7::little-16, 0x41, 0xFF>>

    assert {:ok, %{attributes: extra}} = ZCL.decode_attributes(more)
    assert Enum.map(extra, & &1.value) == [0x12345678, -300, :null]
  end

  test "malformed and oversized frames fail without inventing values" do
    for bytes <- [
          <<>>,
          <<0, 1, 0x0A>>,
          <<1, 1, 0x0A, 1, 0, 0x20, 1>>,
          <<0, 1, 0x0A, 1, 0, 0x21, 1>>,
          <<0, 1, 0x0A, 1, 0, 0x10, 2>>,
          <<0, 1, 0x0A, 1, 0, 0x42, 3, 1>>,
          <<0, 1, 0x0A, 1, 0, 0x42, 65>>,
          <<0, 1, 0x0A, 1, 0, 0x20, 1, 2, 0, 0x20, 2>>
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes, 1)
    end

    assert {:error, %Error{}} = ZCL.decode_attributes(:binary.copy(<<1>>, 129))
    assert {:error, %Error{}} = ZCL.decode_attributes(<<0, 1, 0x0A, 1, 0, 0x20, 1>>, 0)
    assert {:error, %Error{}} = ZCL.decode_attributes(<<0, 1, 0x20, 1, 0, 0x20, 1>>)
    assert {:error, %Error{}} = ZCL.decode_attributes(<<0x04, 1, 0x0A>>)
    assert {:error, %Error{}} = ZCL.decode_attributes(<<0, 1, 0x0A, 1>>)
  end
end
