defmodule WotexLabStorybook.DesignContract do
  @moduledoc "Shared design identities exposed by the qualification host."

  @schema "wotex-design-system-contract/v1"

  @doc "Returns the shared production identities and the Wotex theme identity."
  @spec current() :: map()
  def current do
    {:ok, theme_digest} = DocShell.Json.Canonical.digest(Wotex.Lab.DesignSystem.tokens())

    PhoenixAssets.DesignSystem.contract()
    |> Map.put("schema_version", @schema)
    |> Map.put("wotex_theme_version", Wotex.Lab.DesignSystem.version())
    |> Map.put("wotex_theme_digest", theme_digest)
  end
end
