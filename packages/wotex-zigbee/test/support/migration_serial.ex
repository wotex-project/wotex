defmodule Wotex.Zigbee.TestMigrationSerial do
  @moduledoc false

  @behaviour Wotex.Zigbee.SerialPort

  alias Wotex.Zigbee.TestSerialPeer

  @impl Wotex.Zigbee.SerialPort
  def open(identity, options, owner) do
    Process.put(:zigbee_migration_test, options)
    TestSerialPeer.open(identity, options, owner)
  end

  @impl Wotex.Zigbee.SerialPort
  def write(port, <<0xFE, _, 0x25, 0x37, _::binary>> = bytes) do
    case Keyword.get(Process.get(:zigbee_migration_test), :migration_write, :ok) do
      :ok ->
        TestSerialPeer.write(port, bytes)

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

  def write(port, bytes), do: TestSerialPeer.write(port, bytes)

  @impl Wotex.Zigbee.SerialPort
  def close(port) do
    send(
      Keyword.fetch!(Process.get(:zigbee_migration_test), :test_pid),
      {:migration_serial_close, port}
    )

    TestSerialPeer.close(port)
  end
end
