defmodule Wotex.Profiles do
  @moduledoc """
  Bounded external profiles and consumer-supplied semantic descriptors.

  Use `Wotex.Profiles.Profile`, `Wotex.Profiles.Definition`,
  `Wotex.Profiles.Definitions` and `Wotex.Profiles.Unit` for checked reader
  values. Parsing grants no device qualification or interaction authority.
  """

  @version Mix.Project.config()[:version]

  @doc "The package version."
  @spec version() :: String.t()
  def version, do: @version
end
