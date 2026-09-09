defmodule Wotex.Lab.Plugin do
  @moduledoc """
  Explicit composition port for trusted, instance-owned reference components.

  Implementations advertise Lab capabilities, not WoT semantics. A host must
  inspect the manifest and deliberately start returned child specs. Loading a
  module or receiving a remote scenario never activates a plugin.

  Implementations provide a stable string ID, a finite capability list,
  instance-specific child specifications, and JSON-compatible manifest data.
  The host remains responsible for validating identifier uniqueness,
  capability ownership, dependency versions, resource limits, cleanup terms,
  and instance scope before starting any child.

  This behavior is a trusted in-process extension seam. It must not be used to
  turn scenario strings into modules or child specifications, and inspection
  should not open connections or mutate host configuration. Network bindings,
  numerical semantics, and Web of Things affordances remain owned by their
  respective libraries.
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
