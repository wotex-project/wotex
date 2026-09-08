defmodule Wotex.BLE.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_ble, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    :ok
  end
end

Wotex.BLE.Check.ApplicationFree.main()
