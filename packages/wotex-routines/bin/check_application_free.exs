# The package declares no application callback, and starting its
# application starts no process of its own. Runs in the full gate:
# `mix run --no-start bin/check_application_free.exs`.

defmodule Wotex.Routines.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    case Application.load(:wotex_routines) do
      :ok -> :ok
      {:error, {:already_loaded, :wotex_routines}} -> :ok
    end

    unless Application.spec(:wotex_routines, :mod) in [nil, []] do
      IO.puts(:stderr, "wotex_routines declares an application callback")
      System.halt(1)
    end

    {:ok, _started} = Application.ensure_all_started(:wotex_routines)
    IO.puts("application-free check passed")
    :ok
  end
end

Wotex.Routines.Check.ApplicationFree.main()
