defmodule Wotex.BLE.RuntimeFrameTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE.{Address, Characteristic, Error, RuntimeFrame, RuntimeRelay, Transport, UUID}

  test "WBL-I03 WBL-I05 stream codecs decode canonical bytes and retain exact native metadata" do
    {mapping, metadata} = fixture()

    assert {:ok, 4660, normalized} =
             RuntimeFrame.decode({:value, <<0x34, 0x12>>, metadata}, mapping)

    assert normalized.characteristic == Map.from_struct(metadata.characteristic)
    assert normalized.source == :bluez_value_change

    assert {:ok, 4660, ^normalized} =
             RuntimeFrame.decode({:value, <<0x12, 0x34>>, normalized}, %{mapping | byte_order: :big})

    assert {:ok, false, ^normalized} =
             RuntimeFrame.decode({:value, <<0>>, normalized}, %{mapping | value_type: :boolean})

    assert {:ok, <<>>, ^normalized} =
             RuntimeFrame.decode({:value, <<>>, normalized}, %{mapping | value_type: :bytes})

    assert {:ok, "", ^normalized} =
             RuntimeFrame.decode({:value, <<>>, normalized}, %{mapping | value_type: :utf8})
  end

  test "WBL-I05 malformed stream bytes and metadata fail with protocol classification" do
    {mapping, metadata} = fixture()

    for value <- [<<>>, <<1>>, <<1, 2, 3>>, :binary.copy(<<0>>, 513), false, 0, [], %{}] do
      assert {:error, %Error{code: :invalid_response, class: :protocol}} =
               RuntimeFrame.decode({:value, value, metadata}, mapping)
    end

    for forged <- [
          nil,
          %{},
          Map.put(metadata, :extra, self()),
          %{metadata | effective_mode: :indicate},
          %{metadata | characteristic: nil},
          %{metadata | characteristic: Map.put(metadata.characteristic, :extra, :secret)},
          %{metadata | characteristic: %{metadata.characteristic | generation: -1}},
          %{metadata | characteristic: %{metadata.characteristic | service_uuid: "180f"}},
          %{metadata | characteristic: %{metadata.characteristic | flags: ["notify" | :improper]}},
          %{
            metadata
            | characteristic: Map.delete(Map.from_struct(metadata.characteristic), :handle)
          }
        ] do
      assert {:error, %Error{code: :invalid_response}} =
               RuntimeFrame.validate(<<1, 0>>, forged, mapping)
    end
  end

  test "WBL-I05 mismatched concrete address and mode are unrelated frames" do
    {mapping, metadata} = fixture()

    for updates <- [
          %{service: uuid("180a")},
          %{characteristic: uuid("2a00")},
          %{object_path: "/other/path"},
          %{generation: 3},
          %{handle: 5}
        ] do
      assert :ignore =
               RuntimeFrame.decode({:value, <<1, 0>>, metadata}, %{
                 mapping
                 | address: struct(mapping.address, updates)
               })
    end

    assert :ignore = RuntimeFrame.decode({:value, <<1, 0>>, metadata}, %{mapping | mode: :notify})

    for frame <- [:keepalive, nil, {:unknown, :payload}],
        do: assert(:ignore == RuntimeFrame.decode(frame, mapping))

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.decode_frame(:anything, nil, nil)
  end

  test "WBL-I04 error frames strip arbitrary diagnostic data before Runtime normalization" do
    {mapping, _} = fixture()

    error = %Error{
      code: :timeout,
      class: :unavailable,
      details: %{secret: "FRAME_CANARY"},
      retryable: true,
      effect: :unknown
    }

    assert {:error,
            %Error{
              code: :timeout,
              class: :permanent,
              details: %{},
              retryable: false,
              effect: :unknown
            }} = RuntimeFrame.decode({:error, error}, mapping)

    assert {:error, %Error{code: :timeout, class: :timeout, details: %{}, effect: :none}} =
             RuntimeFrame.decode({:error, %{error | effect: :none}}, mapping)

    assert :ignore = RuntimeFrame.decode({:error, %{error | code: "FRAME_CANARY"}}, mapping)
  end

  test "WBL-I05 relay diagnostics retain no native data and dead generation closure performs no I/O" do
    pid = spawn(fn -> :ok end)
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
    handle = %RuntimeRelay{pid: pid, reference: make_ref(), generation: 1}
    assert :ok = RuntimeRelay.close(handle)
    refute inspect(handle) =~ inspect(handle.reference)

    assert RuntimeRelay.format_status(%{
             state: %{status: :bound, buffered: 0, session: "CANARY"},
             message: "CANARY",
             reason: "CANARY",
             log: ["CANARY"]
           }) == %{
             state: %{status: :bound, buffered: 0},
             message: :redacted,
             reason: :redacted,
             log: []
           }
  end

  defp fixture do
    {:ok, address} =
      Address.new(%{
        service: "180f",
        characteristic: "2a19",
        object_path: "/fixture/characteristic",
        generation: 1,
        handle: 1
      })

    {:ok, characteristic} =
      Characteristic.new(%{
        service_uuid: "180f",
        characteristic_uuid: "2a19",
        service_path: "/fixture/service",
        object_path: address.object_path,
        flags: ["read", "notify"],
        generation: 1,
        handle: 1
      })

    {%{address: address, mode: :auto, value_type: :uint16, byte_order: :little},
     %{
       source: :bluez_value_change,
       characteristic: characteristic,
       requested_mode: :auto,
       effective_mode: :notify
     }}
  end

  defp uuid(value) do
    {:ok, uuid} = UUID.normalize(value)
    uuid
  end
end
