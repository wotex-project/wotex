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

  Callbacks must return promptly within the consumer's operation budget. The
  owner checks the original deadline before and after writes and before
  delivering replies; it cannot preempt a blocking adapter callback. An outer
  call timeout reports unavailable owner completion, without proving whether
  the NCP received bytes. A returned callback failure never exposes its text.
  This also applies to serial open and version negotiation. A failed `open/3`
  must release any resources it acquired before returning or raising; no port
  reference is available to the owner on that path. An acquired port is closed
  once on startup failure or teardown. The explicit owner close reports a
  raised, thrown, exited or non-`:ok` close as a serial failure.
  """

  @type port_ref :: term()

  @callback open(binary(), keyword(), pid()) :: {:ok, port_ref()} | {:error, atom()}
  @callback write(port_ref(), binary()) :: :ok | {:error, atom()}
  @callback close(port_ref()) :: :ok
end
