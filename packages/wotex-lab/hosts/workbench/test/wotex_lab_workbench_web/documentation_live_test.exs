defmodule WotexLabWorkbenchWeb.DocumentationLiveTest do
  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  if Code.ensure_loaded?(DocShell.Presentation.Site) and
       Code.ensure_loaded?(PhoenixAssets.DocShell.Components) do
    setup do
      previous = Application.get_env(:wotex_lab_workbench, :documentation_site)
      previous_search = Application.get_env(:wotex_lab_workbench, :documentation_search_root)
      search_root = temporary_search_root()
      Application.put_env(:wotex_lab_workbench, :documentation_site, site_fixture())
      Application.put_env(:wotex_lab_workbench, :documentation_search_root, search_root)

      on_exit(fn ->
        File.rm_rf!(search_root)

        if previous,
          do: Application.put_env(:wotex_lab_workbench, :documentation_site, previous),
          else: Application.delete_env(:wotex_lab_workbench, :documentation_site)

        if previous_search,
          do:
            Application.put_env(:wotex_lab_workbench, :documentation_search_root, previous_search),
          else: Application.delete_env(:wotex_lab_workbench, :documentation_search_root)
      end)

      :ok
    end

    test "public documentation renders the shared site without allocating Lab state", %{conn: conn} do
      before = Sessions.count()
      conn = get(conn, "/docs/start/")
      html = html_response(conn, 200)

      assert html =~ "Wotex documentation"
      assert html =~ "Portable documentation from the release artifact."
      assert html =~ "data-cohort-digest=\"sha256:"
      assert html =~ ~r/data-pa-token-digest="sha256:[0-9a-f]{64}"/
      assert html =~ ~r/data-pa-component-digest="sha256:[0-9a-f]{64}"/
      assert html =~ ~r/data-pa-fixture-digest="sha256:[0-9a-f]{64}"/
      assert html =~ ~r/data-pa-css-digest="sha256:[0-9a-f]{64}"/
      assert html =~ "Skip to documentation"
      assert html =~ "data-doc-search-contract="
      assert Sessions.count() == before
      assert get_session(conn, SessionToken.key()) == nil
      refute html =~ "Start disposable room"
    end

    test "root redirect, not-found shell and local shared assets remain public", %{conn: conn} do
      root = get(conn, "/docs")
      assert redirected_to(root, 302) == "/docs/start/"

      missing = get(recycle(root), "/docs/not-present/")
      assert html_response(missing, 200) =~ "Page not found"

      css = get(recycle(missing), "/docs-assets/doc-shell.css")
      assert response(css, 200) =~ ".doc-shell"
      assert get_resp_header(css, "content-type") |> hd() =~ "text/css"
      assert get_resp_header(css, "etag") |> hd() =~ ~r/sha256:[0-9a-f]{64}/

      browser = get(recycle(css), "/docs-assets/doc-shell-browser.js")
      assert response(browser, 200) =~ "data-doc-search"
      refute response(browser, 200) =~ "sourceMappingURL"

      pagefind = get(recycle(browser), "/docs-search/pagefind/pagefind.js")
      assert response(pagefind, 200) == "export const search = () => []"
      assert get_resp_header(pagefind, "content-type") |> hd() =~ "text/javascript"

      assert get(recycle(pagefind), "/docs-search/../site.etf").status == 404
    end
  end

  defp site_fixture do
    content = [
      %{
        "tag" => "p",
        "attrs" => %{},
        "content" => ["Portable documentation from the release artifact."],
        "meta" => %{}
      }
    ]

    {:ok, content_digest} = DocShell.Json.Canonical.digest(content)

    page =
      struct!(DocShell.Presentation.Page,
        id: "family_docs:start",
        collection_id: "family_docs",
        document_id: "start",
        kind: "guide",
        route: "/docs/start/",
        title: "Start",
        locale: "en",
        template: :document,
        content: content,
        content_digest: content_digest,
        source_revision: String.duplicate("a", 40),
        source_path: "docs/README.md",
        source_url:
          "https://github.com/wotex-project/wotex/tree/#{String.duplicate("a", 40)}/docs/README.md",
        edit_url: "https://github.com/wotex-project/wotex/edit/main/docs/README.md",
        package_version: "0.1.0",
        status: "stable",
        tags: ["start"]
      )

    navigation =
      struct!(DocShell.Presentation.NavigationItem,
        id: page.id,
        title: page.title,
        path: page.route
      )

    search =
      struct!(DocShell.Presentation.SiteSearchEntry,
        id: "family_docs:start:page",
        page_id: page.id,
        route: page.route,
        title: page.title,
        text: "Portable documentation from the release artifact.",
        locale: "en",
        kind: "guide",
        collection: "family_docs",
        version: "0.1.0",
        status: "stable",
        tags: ["start"]
      )

    struct!(DocShell.Presentation.Site,
      schema_version: "doc-shell-site/v1",
      generation_id: "workbench-test",
      cohort_digest: "sha256:" <> String.duplicate("b", 64),
      profile: "release",
      title: "Wotex documentation",
      base_path: "/docs/",
      default_locale: "en",
      locales: ["en"],
      pages: %{page.id => page},
      routes: %{page.route => page.id},
      navigation: [navigation],
      search: [search],
      redirects: %{"/docs/" => page.route},
      metadata: %{
        "search_contract" => %{
          "schema_version" => "doc-shell-search-query/v1",
          "algorithm" => "pagefind/v1",
          "path" => "/docs-search/pagefind/pagefind.js"
        }
      }
    )
  end

  defp temporary_search_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-documentation-search-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir_p!(Path.join(root, "pagefind"))
    File.write!(Path.join(root, "pagefind/pagefind.js"), "export const search = () => []")
    root
  end
end
