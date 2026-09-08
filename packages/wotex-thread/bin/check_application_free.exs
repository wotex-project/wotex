defmodule Wotex.Thread.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    unless Application.spec(:wotex_thread, :mod) in [nil, [], :undefined] do
      System.halt(1)
    end

    :ok
  end
end

Wotex.Thread.Check.ApplicationFree.main()
