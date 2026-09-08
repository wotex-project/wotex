defmodule Wotex.BLE.IdentityValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.BLE
  alias Wotex.BLE.{Address, BlueZ, Error, ObjectPath, Peer, TestClient, UUID, Value}

  @peer %{adapter: "/org/bluez/hci0", address: "ab:CD:01:23:45:67", address_type: :random}
  @address %{service: 0x180F, characteristic: 0x2A19}
  @path "/org/bluez/hci0/dev_AB_CD_01_23_45_67/service001/char002"
  @integers [
    {:uint8, 8, false},
    {:int8, 8, true},
    {:uint16, 16, false},
    {:int16, 16, true},
    {:uint32, 32, false},
    {:int32, 32, true},
    {:uint64, 64, false},
    {:int64, 64, true}
  ]

  test "WBL-P01 WBL-S01 WBL-V01 explicit peer identity is canonical and revalidated" do
    assert {:ok, %Peer{address: "AB:CD:01:23:45:67", address_type: :random} = peer} =
             Peer.new(@peer)

    assert {:ok, ^peer} = Peer.new(peer)
    assert {:ok, %{address_type: :public}} = Peer.new(%{@peer | address_type: :public})

    for input <- [
          nil,
          %{},
          Map.delete(@peer, :address_type),
          Map.put(@peer, :friendly_name, "sensor"),
          Map.put(@peer, :__struct__, Address),
          %{peer | adapter: "hci0"},
          %{peer | address: "sensor"},
          %{peer | address_type: "random"}
        ],
        do: assert({:error, %Error{code: :invalid_peer, effect: :none}} = Peer.new(input))

    for address <- ["00:11:22:33:44", "00:11:22:33:44:GG", "00-11-22-33-44-55", <<255::136>>, nil] do
      assert {:error, %{field: :address}} = Peer.new(%{@peer | address: address})
    end
  end

  test "WBL-S01 WBL-V01 D-Bus paths admit exact bounded syntax without asserting association" do
    for path <- ["/", "/a", "/0_1/abc", @path, "/" <> String.duplicate("a", 4095)],
        do: assert(ObjectPath.valid?(path))

    for path <- [
          "",
          "a",
          "//",
          "/a/",
          "/a//b",
          "/a-b",
          "/a.b",
          "/a\n",
          "/a\0",
          "/é",
          <<47, 255>>,
          "/" <> String.duplicate("a", 4096),
          nil
        ] do
      refute ObjectPath.valid?(path)
      assert {:error, %{field: :adapter}} = Peer.new(%{@peer | adapter: path})
    end
  end

  test "WBL-S01 WBL-N01 WBL-V01 optional target identity survives constructors and forged fields fail" do
    assert {:ok, address} =
             Address.new(Map.merge(@address, %{handle: 1, object_path: @path, generation: 0}))

    assert address.object_path == @path
    assert address.generation == 0
    assert address.handle == 1
    assert {:ok, ^address} = Address.new(address)
    assert {:ok, _} = Address.new(%{address | handle: 65_535, generation: 0xFFFF_FFFF_FFFF_FFFF})

    for handle <- [-1, 0, 65_536, 1.0, "1"],
        do: assert({:error, %{code: :invalid_handle}} = Address.new(%{address | handle: handle}))

    for generation <- [-1, 0x1_0000_0000_0000_0000, 1.0, :current],
        do:
          assert(
            {:error, %{code: :invalid_generation}} =
              Address.new(%{address | generation: generation})
          )

    assert {:error, %{code: :invalid_object_path}} =
             Address.new(%{address | object_path: "/bad/path/"})

    assert {:error, %{code: :invalid_uuid}} = Address.new(%{address | service: "sensor"})
    assert {:error, %{code: :invalid_uuid}} = Address.new(%{address | characteristic: nil})
  end

  test "WBL-N02 WBL-V01 compatibility topics never default missing or invalid UUIDs" do
    assert {:ok, address} = Address.from_topic("180f/2a19")
    assert {:ok, ^address} = Address.from_topic(address.service <> "/" <> address.characteristic)
    assert {:ok, ^address} = Address.from_topic("0x180F/0x2A19")

    for topic <- [
          nil,
          "",
          "180f",
          "/180f/2a19",
          "180f/2a19/",
          "180f//2a19",
          "/",
          "180f/no",
          String.duplicate("x", 74),
          <<255, 47, 255>>
        ],
        do: assert({:error, %{code: :invalid_address}} = Address.from_topic(topic))
  end

  test "WBL-S01 WBL-V01/WBL-V02 malformed messages fail before the client boundary" do
    assert {:ok, session} = BLE.connect(client: TestClient, mode: :raise)

    for message <- [
          nil,
          %{},
          @address,
          Map.put(@address, :type, :subscribe),
          Map.merge(@address, %{type: :write}),
          Map.merge(@address, %{type: :write, value: nil}),
          Map.merge(@address, %{type: :write, value: 42}),
          Map.merge(@address, %{type: :write, value: :binary.copy(<<1>>, 513)}),
          Map.merge(@address, %{type: :read, generation: -1}),
          Map.merge(@address, %{type: :read, object_path: "relative"})
        ] do
      assert {:error, %Error{effect: :none}} = Address.validate_message(message)
      assert {:error, %Error{effect: :none}} = BLE.send(session, message)
    end

    assert :ok = Address.validate_message(Map.merge(@address, %{type: :write, value: <<>>}))
    assert :ok = BLE.disconnect(session)
  end

  test "WBL-C02 WBL-V01 one-shot serialization rejects forged identities without opening an executable" do
    assert {:ok, handle} =
             BlueZ.connect(
               executable: "/missing/wotex-fixture-busctl",
               object_path: @path,
               service: 0x180F,
               characteristic: 0x2A19
             )

    read = Map.put(@address, :type, :read)

    for message <- [nil, %{}, Map.put(read, :handle, 0), Map.put(read, :generation, -1)],
        do: assert({:error, %Error{effect: :none}} = BlueZ.request(handle, message, 100))

    for selection <- [%{handle: 1}, %{generation: 0}] do
      assert {:error, %{code: :not_supported}} =
               BlueZ.request(handle, Map.merge(read, selection), 100)
    end

    assert {:error, %{code: :address_mismatch}} =
             BlueZ.request(handle, Map.put(read, :object_path, "/other/characteristic"), 100)

    assert {:error, %{code: :transport_unavailable}} =
             BlueZ.request(handle, Map.put(read, :object_path, @path), 100)

    for forged <- [
          nil,
          %{},
          %{handle | path: "relative"},
          %{handle | path: @path <> "\n"},
          %{handle | service: nil},
          %{handle | executable: String.duplicate("x", 4097)}
        ],
        do: assert({:error, %Error{effect: :none}} = BlueZ.request(forged, read, 100))

    for timeout <- [nil, :infinity, 0, 60_001],
        do: assert({:error, %{code: :invalid_options}} = BlueZ.request(handle, read, timeout))
  end

  for {type, bits, signed?} <- @integers do
    min = if signed?, do: -Integer.pow(2, bits - 1), else: 0
    max = Integer.pow(2, if(signed?, do: bits - 1, else: bits)) - 1

    test "WBL-S01 WBL-V02 #{type} boundaries and byte order" do
      type = unquote(type)
      width = div(unquote(bits), 8)

      for value <- Enum.uniq([unquote(min), unquote(max), 0, 1]) do
        for order <- [:big, :little] do
          assert {:ok, bytes} = Value.encode(value, type, byte_order: order)
          assert byte_size(bytes) == width
          assert {:ok, ^value} = Value.decode(bytes, type, byte_order: order)
        end
      end

      for value <- [unquote(min) - 1, unquote(max) + 1, nil, "1", 1.0, false],
          do: assert({:error, %{code: :invalid_value}} = Value.encode(value, type, []))

      for bytes <- [:binary.copy(<<0>>, width - 1), :binary.copy(<<0>>, width + 1)],
          do: assert({:error, %{code: :invalid_value}} = Value.decode(bytes, type, []))
    end

    property "WBL-S01 WBL-V02 #{type} encoding agrees with explicit integer width" do
      check all(value <- integer(unquote(min)..unquote(max))) do
        expected = <<value::size(unquote(bits))>>
        assert {:ok, ^expected} = Value.encode(value, unquote(type), byte_order: :big)
        assert {:ok, ^value} = Value.decode(expected, unquote(type), byte_order: :big)
        little = reverse_bytes(expected)
        assert {:ok, ^little} = Value.encode(value, unquote(type), [])
        assert {:ok, ^value} = Value.decode(little, unquote(type), [])
      end
    end
  end

  test "WBL-S01 WBL-V02 float widths/orders preserve finite IEEE values and signed zero" do
    for {type, bytes} <- [
          {:float32, <<0x41, 0xCC, 0, 0>>},
          {:float64, <<0x40, 0x39, 0x80, 0, 0, 0, 0, 0>>}
        ] do
      assert {:ok, ^bytes} = Value.encode(25.5, type, byte_order: :big)
      assert {:ok, 25.5} = Value.decode(bytes, type, byte_order: :big)
      little = reverse_bytes(bytes)
      assert {:ok, ^little} = Value.encode(25.5, type, [])
      assert {:ok, 25.5} = Value.decode(little, type, [])
      assert {:error, _} = Value.encode(25, type, [])
      assert {:error, _} = Value.decode(bytes <> <<0>>, type, byte_order: :big)
      assert {:error, _} = Value.decode(<<>>, type, [])
    end

    assert {:ok, <<0, 0, 0, 128>>} = Value.encode(-0.0, :float32, [])
    assert {:ok, zero} = Value.decode(<<0, 0, 0, 0>>, :float32, [])
    assert zero == 0.0
    assert {:error, _} = Value.encode(3.5e38, :float32, [])
    assert {:ok, <<0, 0, 128, 0>>} = Value.encode(1.175_494_350_822_287_5e-38, :float32, [])
  end

  test "WBL-S01 WBL-V02 infinities and NaNs fail for both float widths and orders" do
    for {type, bytes} <- [
          {:float32, <<0x7F, 0x80, 0, 0>>},
          {:float32, <<0xFF, 0x80, 0, 0>>},
          {:float32, <<0x7F, 0xC0, 0, 1>>},
          {:float32, <<0x7F, 0x80, 0, 1>>},
          {:float64, <<0x7F, 0xF0, 0, 0, 0, 0, 0, 0>>},
          {:float64, <<0xFF, 0xF0, 0, 0, 0, 0, 0, 0>>},
          {:float64, <<0x7F, 0xF8, 0, 0, 0, 0, 0, 1>>},
          {:float64, <<0x7F, 0xF0, 0, 0, 0, 0, 0, 1>>}
        ] do
      assert {:error, %{code: :invalid_value}} = Value.decode(bytes, type, byte_order: :big)
      little = reverse_bytes(bytes)
      assert {:error, %{code: :invalid_value}} = Value.decode(little, type, [])
    end
  end

  test "WBL-S01 WBL-V02 Boolean, UTF-8 and opaque values distinguish false, zero, empty and nil" do
    assert {:ok, <<0>>} = Value.encode(false, :boolean, [])
    assert {:ok, <<1>>} = Value.encode(true, :boolean, [])
    assert {:ok, false} = Value.decode(<<0>>, :boolean, [])
    assert {:ok, true} = Value.decode(<<1>>, :boolean, [])

    for value <- [0, 1, nil, "false", <<0>>],
        do: assert({:error, _} = Value.encode(value, :boolean, []))

    for bytes <- [<<>>, <<2>>, <<0, 0>>],
        do: assert({:error, _} = Value.decode(bytes, :boolean, []))

    for type <- [:utf8, :bytes], value <- ["", "temperature", "é", String.duplicate("é", 256)] do
      assert {:ok, ^value} = Value.encode(value, type, [])
      assert {:ok, ^value} = Value.decode(value, type, [])
    end

    assert {:ok, <<255>>} = Value.encode(<<255>>, :bytes, [])
    assert {:ok, <<255>>} = Value.decode(<<255>>, :bytes, [])

    for bytes <- [<<255>>, <<0xC3>>, <<0xC0, 0xAF>>] do
      assert {:error, _} = Value.encode(bytes, :utf8, [])
      assert {:error, _} = Value.decode(bytes, :utf8, [])
    end

    for value <- [nil, false, [1], String.duplicate("x", 513)], type <- [:bytes, :utf8] do
      assert {:error, _} = Value.encode(value, type, [])
      assert {:error, _} = Value.decode(value, type, [])
    end
  end

  test "WBL-S01 WBL-V02 codec selection and options cannot infer or smuggle settings" do
    for options <- [
          nil,
          %{},
          [:little],
          [byte_order: :native],
          [byte_order: "little"],
          [byte_order: :big, byte_order: :little],
          [scale: 2],
          [{:byte_order, :little} | :bad]
        ] do
      assert {:error, %{code: :invalid_value}} = Value.encode(1, :uint8, options)
      assert {:error, %{code: :invalid_value}} = Value.decode(<<1>>, :uint8, options)
    end

    for type <- [nil, 0x2A19, "uint8", :battery_level, %{codec: :uint8}] do
      assert {:error, %{code: :invalid_value}} = Value.encode(1, type, [])
      assert {:error, %{code: :invalid_value}} = Value.decode(<<1>>, type, [])
    end
  end

  property "WBL-C02 WBL-S01 arbitrary input bytes never crash UUID, topic, peer or codec parsing" do
    check all(bytes <- binary(max_length: 600)) do
      assert_result(UUID.normalize(bytes))
      assert_result(UUID.decode(bytes))
      assert_result(Address.from_topic(bytes))
      assert_result(Peer.new(%{@peer | address: bytes}))

      for type <- [:int16, :uint64, :float32, :float64, :boolean, :utf8, :bytes] do
        assert_result(Value.decode(bytes, type, []))
      end
    end
  end

  defp reverse_bytes(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  defp assert_result({:ok, _}), do: :ok
  defp assert_result({:error, %Error{effect: :none}}), do: :ok
end
