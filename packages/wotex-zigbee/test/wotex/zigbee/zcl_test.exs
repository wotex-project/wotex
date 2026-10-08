defmodule Wotex.Zigbee.ZCLTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, ZCL}

  @profile Path.expand("../../support/profiles/zcl-global-r8.json", __DIR__)

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

  test "pinned non-value and endpoint vectors preserve raw bytes and subsequent record boundaries" do
    profile = :json.decode(File.read!(@profile))
    assert profile["source"]["revision"] == "8"
    assert profile["source"]["document"] == "07-5123"

    for type <- profile["adoption"]["types"], command <- [1, 0x0A] do
      vectors = [
        {type["non_value_hex"], :null},
        {type["minimum_hex"], type["minimum"]},
        {type["maximum_hex"], type["maximum"]}
      ]

      for {hex, expected} <- vectors, hex != nil do
        raw = Base.decode16!(hex, case: :mixed)
        record = record(command, 1, type["id"], raw)
        next = record(command, 2, 0x20, <<42>>)

        assert {:ok, %{attributes: [first, second]}} =
                 ZCL.decode_attributes(<<8, 7, command, record::binary, next::binary>>)

        assert first == %{id: 1, type: type["id"], value: expected, raw: raw, status: :success}
        assert second.value == 42
        assert second.raw == <<42>>
      end
    end
  end

  test "numeric full-range policy is explicit per attribute and preserves integer endpoints" do
    profile = :json.decode(File.read!(@profile))

    for type <- profile["adoption"]["types"],
        Map.has_key?(type, "full_range_non_value"),
        command <- [1, 0x0A] do
      raw = Base.decode16!(type["non_value_hex"], case: :mixed)
      first = record(command, 1, type["id"], raw)
      second = record(command, 2, type["id"], raw)
      bytes = <<8, 7, command, first::binary, second::binary>>
      assert {:ok, %{attributes: [full, nullable]}} = ZCL.decode_attributes(bytes, 32, [1])
      assert full.value == type["full_range_non_value"]
      assert full.raw == raw
      assert nullable.value == :null
      assert nullable.raw == raw
    end

    bytes = <<8, 7, 0x0A, 1::little-16, 0x20, 0xFF>>
    assert {:ok, %{attributes: [%{value: :null}]}} = ZCL.decode_attributes(bytes, 32, [2])
    assert {:ok, _} = ZCL.decode_attributes(bytes, 32, Enum.to_list(1..32))
  end

  test "malformed full-range policies and nonnumeric selections are refused" do
    bytes = <<8, 7, 0x0A, 1::little-16, 0x20, 0xFF>>

    for ids <- [nil, %{}, [1, 1], [-1], [0x10000], ["1"], Enum.to_list(1..33)] do
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes, 32, ids)
    end

    for {type, raw} <- [{0x10, <<1>>}, {0x41, <<0>>}, {0x42, <<0xFF>>}, {0xF0, <<0xAA>>}] do
      bytes = <<8, 7, 0x0A, 1::little-16, type, raw::binary>>
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes, 32, [1])
    end
  end

  test "every forbidden boolean encoding is malformed and truncated numeric values cannot become null" do
    for value <- 2..254 do
      bytes = <<8, 7, 0x0A, 1::little-16, 0x10, value>>
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes)
    end

    for {type, partial} <- [
          {0x20, <<>>},
          {0x21, <<0xFF>>},
          {0x23, <<0xFF, 0xFF, 0xFF>>},
          {0x28, <<>>},
          {0x29, <<0>>}
        ],
        policy <- [[], [1]] do
      bytes = <<8, 7, 0x0A, 1::little-16, type, partial::binary>>
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes, 32, policy)
    end
  end

  test "short strings distinguish empty and null while preserving arbitrary encoded character bytes" do
    for type <- [0x41, 0x42] do
      raw = :binary.copy(<<0xFF>>, 64)
      bytes = <<8, 7, 0x0A, 1::little-16, type, 64, raw::binary>>

      assert {:ok, %{attributes: [%{value: ^raw, raw: <<64, ^raw::binary>>}]}} =
               ZCL.decode_attributes(bytes)

      oversized = :binary.copy(<<0>>, 65)
      bytes = <<8, 7, 0x0A, 1::little-16, type, 65, oversized::binary>>
      assert {:error, %Error{kind: :invalid_frame}} = ZCL.decode_attributes(bytes)
    end
  end

  test "an unsupported width keeps the complete opaque tail without inferring subsequent records" do
    tail = <<0xAA, 2::little-16, 0x20, 42>>
    bytes = <<8, 7, 0x0A, 1::little-16, 0xF0, tail::binary>>

    assert {:ok, %{attributes: [%{type: 0xF0, value: {:unsupported, 0xF0}, raw: ^tail}]}} =
             ZCL.decode_attributes(bytes)
  end

  defp record(1, id, type, raw), do: <<id::little-16, 0, type, raw::binary>>
  defp record(0x0A, id, type, raw), do: <<id::little-16, type, raw::binary>>
end
