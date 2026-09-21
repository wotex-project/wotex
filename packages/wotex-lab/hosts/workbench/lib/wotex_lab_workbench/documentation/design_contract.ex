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
    design_system = PhoenixAssets.DesignSystem

    with true <-
           Code.ensure_loaded?(design_system) and
             function_exported?(design_system, :contract, 0),
         {:ok, theme_digest} <- DocShell.Json.Canonical.digest(Wotex.Lab.DesignSystem.tokens()) do
      {:ok,
       :erlang.apply(design_system, :contract, [])
       |> Map.put("schema_version", @schema)
       |> Map.put("wotex_theme_version", Wotex.Lab.DesignSystem.version())
       |> Map.put("wotex_theme_digest", theme_digest)}
    else
      false -> {:error, :phoenix_assets_design_system_required}
      {:error, _} = error -> error
    end
  end
end
