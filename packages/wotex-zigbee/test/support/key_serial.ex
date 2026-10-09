defmodule Wotex.Zigbee.TestKeySerial do
  @moduledoc false

  @behaviour Wotex.Zigbee.SerialPort

  alias Wotex.Zigbee.TestSerialPeer

  @impl Wotex.Zigbee.SerialPort
  def open(identity, options, owner) do
    Process.put(:zigbee_key_test, options)
    TestSerialPeer.open(identity, options, owner)
  end

  @impl Wotex.Zigbee.SerialPort
  def write(port, <<0xFE, _, 0x25, id, _::binary>> = bytes) when id in [0x4E, 0x4F] do
    field = if id == 0x4E, do: :update_write, else: :switch_write

    case Keyword.get(Process.get(:zigbee_key_test), field, :ok) do
      :ok ->
        TestSerialPeer.write(port, bytes)

      :raise ->
        raise ArgumentError, "credential-canary"

      :error ->
        {:error, "credential-canary"}

      :malformed ->
        {:unknown, "credential-canary"}

      {:delay, milliseconds} ->
        :ok = TestSerialPeer.write(port, bytes)
        Process.sleep(milliseconds)
        :ok
    end
  end

  def write(port, bytes), do: TestSerialPeer.write(port, bytes)

  @impl Wotex.Zigbee.SerialPort
  def close(port) do
    send(Keyword.fetch!(Process.get(:zigbee_key_test), :test_pid), {:key_serial_close, port})
    TestSerialPeer.close(port)
  end
end
