defmodule Wotex.Runtime do
  @moduledoc """
  Binding-neutral W3C Web of Things interaction mechanics.

  The package plans and dispatches protocol exchanges. It does not establish
  canonical Thing state or prove a physical Action effect.
  """

  @operations ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a

  @doc "Returns the supported W3C WoT operation names as atoms."
  @spec operations() :: [atom()]
  def operations, do: @operations
end
