defmodule Wotex.Zigbee.TestControlledSerial do
  @moduledoc false

  @behaviour Wotex.Zigbee.SerialPort

  alias Wotex.Zigbee.TestSerialPeer

  @impl Wotex.Zigbee.SerialPort
  def open(identity, options, owner) do
    Process.put(:zigbee_test_write_behavior, Keyword.fetch!(options, :write_behavior))
    TestSerialPeer.open(identity, options, owner)
  end

  @impl Wotex.Zigbee.SerialPort
  def write(port, <<0xFE, 0, 0x21, 2, _>> = bytes), do: TestSerialPeer.write(port, bytes)

  def write(port, bytes) do
    case Process.get(:zigbee_test_write_behavior) do
      :raise ->
        raise ArgumentError, "credential-canary"

      :throw ->
        throw("credential-canary")

      :exit ->
        exit("credential-canary")

      :malformed ->
        {:unexpected, "credential-canary"}

      :error ->
        {:error, "credential-canary"}

      {:delay, milliseconds} ->
        :ok = TestSerialPeer.write(port, bytes)
        Process.sleep(milliseconds)
        :ok
    end
  end

  @impl Wotex.Zigbee.SerialPort
  def close(port), do: TestSerialPeer.close(port)
end
