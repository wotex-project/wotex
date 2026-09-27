# The package declares no application callback, and starting its
# application starts no process of its own. Runs in the full gate:
# `mix run --no-start bin/check_application_free.exs`.

defmodule Wotex.Zigbee.Check.ApplicationFree do
  @moduledoc """
  Verifies that starting the Hex application adds no package-owned process.
  Consumers explicitly start and supervise coordinator owners instead.
  """

  @spec main() :: :ok
  def main do
    case Application.load(:wotex_zigbee) do
      :ok -> :ok
      {:error, {:already_loaded, :wotex_zigbee}} -> :ok
    end

    unless Application.spec(:wotex_zigbee, :mod) in [nil, []] do
      IO.puts(:stderr, "wotex_zigbee declares an application callback")
      System.halt(1)
    end

    {:ok, _started} = Application.ensure_all_started(:wotex_zigbee)
    IO.puts("application-free check passed")
    :ok
  end
end

Wotex.Zigbee.Check.ApplicationFree.main()
