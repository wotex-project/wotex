defmodule Wotex.BLE.ObjectPath do
  @moduledoc "Bounded D-Bus object path syntax without object discovery."

  @doc "Checks an absolute D-Bus object path of at most 4096 bytes."
  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value) and byte_size(value) in 1..4096,
    do: Regex.match?(~r{\A/(?:[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*)?\z}, value)

  def valid?(_), do: false
end
