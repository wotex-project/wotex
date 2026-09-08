defmodule Wotex.BLE.BlueZTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.BLE.{Address, BlueZ, UUID}
  @path "/org/bluez/hci0/dev_00_11_22_33_44_55/service0001/char0002"
  @message %{type: :read, service: 0x180F, characteristic: 0x2A19}

  test "UUID and address widths preserve ATT byte order" do
    assert {:ok, uuid} = UUID.normalize(0x180F)

    for value <- ["180F", "0x180f", "0000180f", uuid],
        do: assert({:ok, uuid} == UUID.normalize(value))

    assert {:ok, ^uuid} = UUID.decode(<<0x0F, 0x18>>)
    assert {:ok, bytes} = UUID.encode(uuid)
    assert byte_size(bytes) == 16
    assert {:ok, ^uuid} = UUID.decode(bytes)

    for value <- [nil, -1, "xxx", "", "1-80f", "0x0x180f", 0x1_0000_0000],
        do: assert(match?({:error, _}, UUID.normalize(value)))

    assert {:error, _} = UUID.decode(<<1, 2, 3, 4>>)
    assert {:error, _} = UUID.encode(nil)
    assert {:ok, _} = Address.new(Map.put(@message, :handle, 65_535))
    assert {:error, _} = Address.new(Map.put(@message, :handle, 0))

    assert {:error, _} =
             Address.validate_message(
               Map.merge(@message, %{type: :write, value: :binary.copy(<<1>>, 513)})
             )
  end

  test "busctl byte arrays must exactly match counts and octets" do
    assert {:ok, <<0, 42, 255>>} = BlueZ.decode("ay 3 0 42 255\n")
    assert {:ok, <<>>} = BlueZ.decode("ay 0")

    for text <- [
          "ay 1 256",
          "ay 2 1",
          "ay 513",
          "ay x",
          "ay 1 x",
          "ay 1 1x",
          "s value",
          nil,
          String.duplicate("x", 4097)
        ],
        do: assert(match?({:error, _}, BlueZ.decode(text)))
  end

  test "native command boundary owns processes, has deadlines and checks remote errors" do
    path = Path.join(System.tmp_dir!(), "wotex-busctl-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    opts = [executable: path, object_path: @path, service: 0x180F, characteristic: 0x2A19]
    assert {:ok, handle} = BlueZ.connect(opts)
    assert {:error, %{code: :transport_unavailable}} = BlueZ.request(handle, @message, 100)

    script(
      path,
      "case \"$7\" in ReadValue) printf 'ay 1 42\\n';; WriteValue) exit 0;; *) exit 2;; esac"
    )

    assert {:ok, <<42>>} = BlueZ.request(handle, @message, 1000)

    assert {:ok, :written} =
             BlueZ.request(handle, Map.merge(@message, %{type: :write, value: <<42>>}), 1000)

    assert {:error, _} = BlueZ.request(handle, Map.put(@message, :characteristic, 1), 100)
    assert {:error, _} = BlueZ.request(handle, Map.put(@message, :type, :notify), 100)
    script(path, "exit 1")
    assert {:error, %{code: :remote_error}} = BlueZ.request(handle, @message, 1000)
    script(path, "exec sleep 1")
    assert {:error, %{code: :timeout}} = BlueZ.request(handle, @message, 10)
    script(path, "printf '%05000d' 0")
    assert {:error, %{code: :response_limit}} = BlueZ.request(handle, @message, 1000)
    assert :ok = BlueZ.disconnect(handle)

    for opts <- [
          [],
          [executable: "relative"],
          Keyword.put(opts, :object_path, "/bad"),
          Keyword.put(opts, :service, "bad")
        ],
        do: assert(match?({:error, _}, BlueZ.connect(opts)))
  end

  property "UUID integers round trip through 128-bit ATT representation" do
    check all(value <- integer(0..0xFFFF_FFFF)) do
      {:ok, uuid} = UUID.normalize(value)
      assert {:ok, bytes} = UUID.encode(value)
      assert {:ok, ^uuid} = UUID.decode(bytes)
    end
  end

  defp script(path, body) do
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o700)
  end
end
