defmodule WotexLabWorkbench.Documentation.DesignContract do
  @moduledoc """
  Stable identities for the Phoenix Assets UI contract shared by every surface.

  The values come from the installed production modules and assets. They are
  therefore available to the Workbench and hosted documentation without a
  Node installation or a source checkout, and the static Storybook builder can
  record the same identities in its own manifest.
  """

  @schema "wotex-design-system-contract/v1"

  @doc "Returns the production token, component, fixture, CSS and theme identities."
  @spec current() :: {:ok, map()} | {:error, term()}
  def current do
    with {:ok, theme_digest} <- DocShell.Json.Canonical.digest(Wotex.Lab.DesignSystem.tokens()) do
      {:ok,
       PhoenixAssets.DesignSystem.contract()
       |> Map.put("schema_version", @schema)
       |> Map.put("wotex_theme_version", Wotex.Lab.DesignSystem.version())
       |> Map.put("wotex_theme_digest", theme_digest)}
    end
  end
end
