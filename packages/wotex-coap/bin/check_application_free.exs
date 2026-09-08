defmodule Wotex.CoAP.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_coap, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    :ok
  end
end

Wotex.CoAP.Check.ApplicationFree.main()
