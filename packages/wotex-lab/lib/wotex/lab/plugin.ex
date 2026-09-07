defmodule Wotex.Lab.Plugin do
  @moduledoc """
  Explicit composition port for trusted, instance-owned reference components.

  Implementations advertise Lab capabilities, not WoT semantics. A host must
  inspect the manifest and deliberately start returned child specs. Loading a
  module or receiving a remote scenario never activates a plugin.
  """

  @doc "Returns a stable string identifier without dynamically creating atoms."
  @callback id() :: String.t()

  @doc "Lists supported Lab capability IDs."
  @callback capabilities() :: [String.t()]

  @doc "Returns child specs from explicit instance-specific configuration."
  @callback child_specs(keyword()) :: [Supervisor.child_spec()]

  @doc "Returns public JSON-compatible identity, dependency and ownership metadata."
  @callback manifest() :: map()
end
