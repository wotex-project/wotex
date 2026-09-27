defmodule Wotex.Zigbee.SerialPort do
  @moduledoc """
  Byte transport contract for one explicitly selected coordinator.

  `open/3` must match `device_id` to a stable hardware identity before
  returning. A successful adapter sends `{:zigbee_serial, port, bytes}` to
  `owner` for received chunks and `{:zigbee_serial_down, port, reason}` on
  disconnection. `bytes` may split or coalesce MT frames. The adapter must
  never silently select a different USB device after reconnect.

  `Wotex.Zigbee.Serial.CircuitsUART` implements this contract for macOS and
  Linux hosts, including Nerves systems with a compatible serial device.
  Consumers may supply another adapter. The package owns MT framing; the
  consumer owns device selection, permissions and reconnect policy.
  """

  @type port_ref :: term()

  @callback open(binary(), keyword(), pid()) :: {:ok, port_ref()} | {:error, atom()}
  @callback write(port_ref(), binary()) :: :ok | {:error, atom()}
  @callback close(port_ref()) :: :ok
end
