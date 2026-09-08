defmodule Wotex.Modbus.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_modbus, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    :ok
  end
end

Wotex.Modbus.Check.ApplicationFree.main()
