defmodule WotexLabWorkbench do
  @moduledoc """
  The reference Phoenix LiveView workbench host for `wotex_lab`.

  The host owns its endpoint, PubSub, one explicit `Wotex.Lab` instance and
  the optional formal profile. It consumes the Lab and the WoTEx profile
  packages through public APIs only; nothing in the Lab library starts
  because this application exists. Every experiment, disposable Thing and
  simulated effect belongs to a session room that a server-admitted command
  started and that expires with the browser session.
  """

  @version Mix.Project.config()[:version]

  @doc "The host version recorded as the evidence revision."
  @spec version() :: String.t()
  def version, do: @version

  @doc "The explicit Lab instance name owned by this host."
  @spec lab() :: atom()
  def lab, do: WotexLabWorkbench.Lab
end
