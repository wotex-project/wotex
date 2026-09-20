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
  alias WotexLabWorkbench.Documentation

  @doc "The generated stylesheet."
  @spec tokens(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def tokens(conn, _) do
    overrides = Application.get_env(:wotex_lab_workbench, :token_overrides, %{})

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, DesignSystem.stylesheet() <> overrides_css(overrides))
  end

  @doc "Serves one local DocShell renderer asset with its content digest."
  @spec documentation(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def documentation(conn, %{"name" => name}) do
    case Documentation.asset(name) do
      {:ok, media_type, bytes, digest} ->
        conn
        |> put_resp_content_type(media_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("etag", ~s("#{digest}"))
        |> send_resp(200, bytes)

      {:error, _} ->
        send_resp(conn, 404, "not found")
    end
  end

  @doc "Serves one release-built Pagefind asset from its bounded local tree."
  @spec documentation_search(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def documentation_search(conn, %{"path" => path}) do
    case Documentation.search_asset(path) do
      {:ok, media_type, bytes, digest} ->
        conn
        |> put_resp_content_type(media_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("etag", ~s("#{digest}"))
        |> send_resp(200, bytes)

      {:error, _} ->
        send_resp(conn, 404, "not found")
    end
  end

  @doc "Renders admitted overrides as a scoped CSS block; unknown names and unsafe values are dropped."
  @spec overrides_css(map()) :: String.t()
  def overrides_css(overrides) when is_map(overrides) do
    admitted =
      overrides
      |> Enum.reduce(%{}, fn {name, value}, valid ->
        case phoenix_design_system(:validate_overrides, [%{name => value}]) do
          {:ok, override} -> Map.merge(valid, override)
          {:error, _} -> valid
        end
      end)

    declarations =
      case phoenix_design_system(:override_style, [admitted]) do
        {:ok, value} -> value
        {:error, _} -> ""
      end

    if declarations == "",
      do: "",
      else: "\n.wotex-lab[data-pa-design-system]{#{declarations}}\n"
  end

  defp phoenix_design_system(function, arguments) do
    module = PhoenixAssets.DesignSystem

    if Code.ensure_loaded?(module),
      do: apply(module, function, arguments),
      else: {:error, :design_system_artifact_unavailable}
  end
end
