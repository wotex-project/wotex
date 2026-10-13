# The package declares no application callback, and starting its
# application starts no process of its own. Runs in the full gate:
# `mix run --no-start bin/check_application_free.exs`.

defmodule Wotex.Profiles.Check.ApplicationFree do
  @moduledoc false

  @spec main() :: :ok
  def main do
    case Application.load(:wotex_profiles) do
      :ok -> :ok
      {:error, {:already_loaded, :wotex_profiles}} -> :ok
    end

    unless Application.spec(:wotex_profiles, :mod) in [nil, []] do
      IO.puts(:stderr, "wotex_profiles declares an application callback")
      System.halt(1)
    end

    {:ok, _started} = Application.ensure_all_started(:wotex_profiles)
    IO.puts("application-free check passed")
    :ok
  end
end

Wotex.Profiles.Check.ApplicationFree.main()
