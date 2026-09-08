defmodule WotexLabWorkbenchWeb.AssetController do
  @moduledoc """
  Serves the design-system stylesheet generated from
  `Wotex.Lab.DesignSystem.stylesheet/0` plus admitted token overrides.

  Overrides come from the host configuration `:token_overrides`, a map of
  token name to CSS value; names must exist in the design system's token
  set and values are restricted to a conservative character class, so the
  stylesheet never carries arbitrary text.
  """

  use WotexLabWorkbenchWeb, :controller

  alias Wotex.Lab.DesignSystem

  @value ~r/\A[A-Za-z0-9#%.,\- ()]{1,64}\z/

  @doc "The generated stylesheet."
  @spec tokens(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def tokens(conn, _params) do
    overrides = Application.get_env(:wotex_lab_workbench, :token_overrides, %{})

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, DesignSystem.stylesheet() <> overrides_css(overrides))
  end

  @doc "Renders admitted overrides as a scoped CSS block; unknown names and unsafe values are dropped."
  @spec overrides_css(map()) :: String.t()
  def overrides_css(overrides) when is_map(overrides) do
    known = DesignSystem.tokens() |> Map.values() |> Enum.flat_map(&Map.keys/1) |> MapSet.new()

    declarations =
      overrides
      |> Enum.filter(fn {name, value} ->
        is_binary(name) and MapSet.member?(known, name) and is_binary(value) and
          Regex.match?(@value, value)
      end)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {name, value} -> "  --wl-#{name}: #{value};" end)

    if declarations == "", do: "", else: "\n.wotex-lab {\n#{declarations}\n}\n"
  end
end
