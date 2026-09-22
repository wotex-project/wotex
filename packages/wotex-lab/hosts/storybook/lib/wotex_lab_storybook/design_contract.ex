defmodule WotexLabStorybook.DesignContract do
  @moduledoc "Shared design identities exposed by the qualification host."

  @schema "wotex-design-system-contract/v1"

  @doc "Returns the shared production identities and the Wotex theme identity."
  @spec current() :: map()
  def current,
    do: Map.put(Wotex.Lab.DesignSystem.contract(), "schema_version", @schema)
end
