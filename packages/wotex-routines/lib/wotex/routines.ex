defmodule Wotex.Routines do
  @moduledoc """
  Entry point of `wotex-routines`.
  """

  @version Mix.Project.config()[:version]

  @doc "The package version."
  @spec version() :: String.t()
  def version, do: @version
end
