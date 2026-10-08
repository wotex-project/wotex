defmodule Wotex.Zigbee.TestStartupSerial do
  @moduledoc false

  @behaviour Wotex.Zigbee.SerialPort

  alias Wotex.Zigbee.TestSerialPeer

  @impl Wotex.Zigbee.SerialPort
  def open(identity, options, owner) do
    Process.put(:zigbee_startup_test, options)
    effect(:open, fn -> TestSerialPeer.open(identity, options, owner) end)
  end

  @impl Wotex.Zigbee.SerialPort
  def write(port, bytes), do: effect(:write, fn -> TestSerialPeer.write(port, bytes) end)

  @impl Wotex.Zigbee.SerialPort
  def close(port) do
    TestSerialPeer.close(port)
    effect(:close, fn -> :ok end)
  end

  defp effect(stage, success) do
    options = Process.get(:zigbee_startup_test)
    send(Keyword.fetch!(options, :test_pid), {:serial_callback, stage, self()})

    case Keyword.get(options, stage, :ok) do
      :ok -> success.()
      :raise -> raise ArgumentError, "credential-canary"
      :throw -> throw("credential-canary")
      :exit -> exit("credential-canary")
      :malformed -> {:unexpected, "credential-canary"}
      :error -> {:error, "credential-canary"}
      :hold -> hold(stage, success)
    end
  end

  defp hold(stage, success) do
    result = success.()

    receive do
      {:release_callback, ^stage} -> result
    after
      2_000 -> {:error, :test_release_timeout}
    end
  end
end
