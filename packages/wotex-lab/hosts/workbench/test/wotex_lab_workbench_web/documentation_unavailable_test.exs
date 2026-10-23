defmodule WotexLabWorkbenchWeb.DocumentationUnavailableTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Documentation, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "an unavailable corpus keeps a public reading shell and includes only available assets", %{
    conn: conn
  } do
    previous = Application.get_env(:wotex_lab_workbench, :documentation_site)
    Application.put_env(:wotex_lab_workbench, :documentation_site, :unavailable)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:wotex_lab_workbench, :documentation_site),
        else: Application.put_env(:wotex_lab_workbench, :documentation_site, previous)
    end)

    count = Sessions.count()
    conn = get(conn, "/docs/start/")
    html = html_response(conn, 200)
    assert html =~ "Documentation unavailable"
    assert html =~ ~s(aria-label="Return to workbench")
    assert get_session(conn, SessionToken.key()) == nil
    assert Sessions.count() == count

    for name <- ~w(doc-shell.css doc-shell-browser.js) do
      case Documentation.asset(name) do
        {:ok, _, _, "sha256:" <> digest} -> assert html =~ "/docs-assets/#{name}?v=#{digest}"
        {:error, _} -> refute html =~ "/docs-assets/#{name}"
      end
    end

    assert html =~ "/docs-assets/documentation.css?v="
  end
end
