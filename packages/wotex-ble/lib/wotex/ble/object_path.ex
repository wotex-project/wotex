defmodule Wotex.BLE.ObjectPath do
  @moduledoc """
  Validates bounded absolute D-Bus object paths.

  `valid?/1` accepts the root path or a slash-separated sequence whose elements
  contain only ASCII letters, digits, and underscores. Values are limited to
  4096 bytes. Non-binaries, relative paths, empty elements, and other D-Bus
  syntax return `false` rather than raising.

  The predicate checks lexical form only. It does not query the system bus,
  discover BlueZ objects, resolve a device, or establish that a path implements
  a particular interface. `Wotex.BLE.Address` uses it for optional caller-owned
  object paths, while `Wotex.BLE.BlueZ` applies a narrower characteristic-path
  pattern to its concrete adapter configuration.

  ## Examples

      iex> Wotex.BLE.ObjectPath.valid?("/org/bluez/hci0")
      true
      iex> Wotex.BLE.ObjectPath.valid?("org/bluez/hci0")
      false
  """

  @doc "Checks an absolute D-Bus object path of at most 4096 bytes."
  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value) and byte_size(value) in 1..4096,
    do: Regex.match?(~r{\A/(?:[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*)?\z}, value)

  def valid?(_), do: false
end
