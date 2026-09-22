defmodule WotexLabWorkbench.Documentation.DesignContract do
  @moduledoc """
  Stable identities for the Wotex Lab UI contract shared by every surface.

  The values come from the installed production modules and assets. They are
  therefore available to the Workbench and hosted documentation without a
  Node installation or a source checkout, and the static Storybook builder can
  record the same identities in its own manifest.
  """

  @schema "wotex-design-system-contract/v1"

  @doc "Returns the production token, component, fixture, CSS and theme identities."
  @spec current() :: {:ok, map()}
  def current,
    do: {:ok, Map.put(Wotex.Lab.DesignSystem.contract(), "schema_version", @schema)}
end
