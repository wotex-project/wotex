defmodule WotexLabWorkbenchWeb.DocumentationComponents do
  @moduledoc "The compact documentation shell shared by hosted and static Lab pages."

  use WotexLabWorkbenchWeb, :html

  alias Wotex.Lab.DesignSystem

  attr(:site, :any, default: nil)
  attr(:page, :any, default: nil)
  attr(:context, :map, default: %{})
  attr(:return_path, :string, default: "/")
  attr(:assets, :map, default: %{})

  @doc "Composes admitted DocShell content and controls within the Lab reader."
  @spec reader(map()) :: Phoenix.LiveView.Rendered.t()
  def reader(assigns) do
    {title_content, content} = content(assigns.page)
    home = home(assigns.site)

    assigns =
      assigns
      |> assign(:renderer?, Code.ensure_loaded?(PhoenixAssets.DocShell.Components))
      |> assign(:token_version, DesignSystem.version())
      |> assign(:home, home)
      |> assign(:api, api(assigns.site))
      |> assign(:packages, packages(assigns.site))
      |> assign(:title_content, title_content)
      |> assign(:content, content)
      |> assign(:navigation, if(assigns.site, do: assigns.site.navigation, else: []))
      |> assign(:current_route, if(assigns.page, do: assigns.page.route, else: ""))
      |> assign(:search, search(assigns.site, assigns.context))
      |> assign(:filter_values, filter_values(assigns.site))

    ~H"""
    <div
      class="wotex-lab doc-shell lab-docs"
      data-wotex-design-system={@token_version}
      data-wotex-theme="system"
      data-doc-theme="system"
      data-doc-section={section(@page)}
      data-pa-doc-shell
      data-doc-copy-icon={asset(@assets, "copy.svg", "/icons/copy.svg")}
      data-content-digest={@page && @page.content_digest}
      data-cohort-digest={@site && @site.cohort_digest}
      lang={if @page, do: @page.locale, else: "en"}
      dir={if @page && @page.locale in ["ar", "fa", "he", "ur"], do: "rtl", else: "ltr"}
    >
      <a class="doc-skip-link" href="#doc-main">Skip to documentation</a>
      <header class="doc-site-header" data-pagefind-ignore>
        <button
          :if={@site}
          class="doc-icon doc-mobile-nav"
          type="button"
          data-doc-nav-toggle
          aria-label="Browse documentation"
          aria-controls="doc-navigation"
          aria-expanded="false"
        ><img src={asset(@assets, "menu.svg", "/icons/menu.svg")} width="16" height="16" alt="" /></button>
        <a class="doc-brand" href={@home} aria-label="WoTEx documentation"><img
          src={asset(@assets, "wotex.svg", "/brand/wotex.svg")}
          width="28"
          height="20"
          alt=""
        /><span>Docs</span></a>
        <nav :if={@site} class="doc-primary-nav" aria-label="Documentation sections">
          <a href={@home}>Guides</a><a :if={@api != []} href="#doc-api" data-doc-index="api">API</a><a
            :if={@packages != []}
            href="#doc-packages"
            data-doc-index="packages"
          >Packages</a>
        </nav>
        <button
          :if={@site && @renderer?}
          class="doc-search-trigger"
          type="button"
          data-doc-search-open
          aria-label="Search documentation"
        ><img src={asset(@assets, "search.svg", "/icons/search.svg")} width="16" height="16" alt="" /><span>Search documentation</span><kbd>⌘ K</kbd></button>
        <a class="doc-return" href={@return_path} aria-label="Return to workbench"><span>Return to workbench</span><img
          src={asset(@assets, "arrow-up-right.svg", "/icons/arrow-up-right.svg")}
          width="14"
          height="14"
          alt=""
        /></a>
      </header>
      <div class="doc-layout">
        <aside :if={@site && @renderer?} id="doc-navigation" class="doc-sidebar" data-doc-nav>
          <nav class="doc-drawer-sections" aria-label="Documentation sections">
            <a href={@home}>Guides</a><a
              :if={@api != []}
              href="#doc-api"
              data-doc-index="api"
            >API</a><a :if={@packages != []} href="#doc-packages" data-doc-index="packages">Packages</a>
          </nav>
          <.shared
            component={:navigation}
            arguments={%{items: @navigation, current_route: @current_route}}
          />
          <details class="doc-reader-settings">
            <summary>Appearance</summary><div role="group" aria-label="Reader theme">
              <button
                :for={theme <- ~w(system light dark contrast)}
                type="button"
                data-doc-theme-value={theme}
              >{String.capitalize(theme)}</button>
            </div>
          </details>
        </aside>
        <main id="doc-main" tabindex="-1">
          <noscript :if={@site && @renderer?}><details>
            <summary>Browse documentation</summary><.shared
              component={:navigation}
              arguments={%{items: @navigation, current_route: @current_route}}
            />
          </details></noscript>
          <.shared
            :if={@site && @renderer?}
            component={:search}
            arguments={
              %{search: @search, presentation: :inline, trigger: false, filter_values: @filter_values}
            }
          >
            <:header>
              <header class="doc-search-heading">
                <h1>Search</h1><button
                  class="doc-icon"
                  type="button"
                  data-doc-search-close
                  aria-label="Close search"
                ><img src={asset(@assets, "x.svg", "/icons/x.svg")} width="16" height="16" alt="" /></button>
              </header>
            </:header>
            <:controls>
              <div class="doc-search-scopes" aria-label="Search in">
                <button
                  :for={
                    {label, value} <- [
                      {"All docs", ""},
                      {"Guides", "scope:guide"},
                      {"API", "scope:api"},
                      {"Packages", "scope:package"}
                    ]
                  }
                  type="button"
                  data-doc-search-scope={value}
                  aria-pressed={value == ""}
                >{label}</button>
              </div>
            </:controls>
          </.shared>
          <div class="doc-reader-content" data-pagefind-body={@page != nil}>
            <.shared :if={@page} component={:breadcrumbs} arguments={%{items: @page.breadcrumbs}} />
            <header :if={@page} class="doc-page-header">
              {@title_content}
              <h1 :if={!@title_content}>{@page.title}</h1><p :if={@page.description}>
                {@page.description}
              </p><span class="doc-page-version">{@page.package_version}</span>
            </header>
            <details :if={@page && @page.headings != []} class="doc-inline-contents">
              <summary>On this page</summary><.shared
                component={:table_of_contents}
                arguments={%{headings: @page.headings}}
              />
            </details>
            <article :if={@page}>{@content}</article>
            <h1 :if={!@page}>{if @site, do: "Page not found", else: "Documentation unavailable"}</h1>
            <a :if={@site && !@page} href={@home}>Documentation home</a>
            <.shared
              :if={@page}
              component={:reading_flow}
              arguments={%{previous: @page.previous, next: @page.next}}
            />
            <.shared :if={@page} component={:provenance} arguments={%{page: @page}} />
          </div>
          <details
            :if={@api != []}
            class="doc-catalogue"
            data-doc-catalogue="api"
            data-pagefind-ignore
          >
            <summary>API</summary><section id="doc-api" aria-label="API references">
              <h1 tabindex="-1">API</h1>
              <label class="doc-catalogue-filter">Filter API references<input
                type="search"
                data-doc-catalogue-filter="api"
                autocomplete="off"
              /></label>
              <p role="status" data-doc-catalogue-status></p>
              <section :for={{collection, entries} <- @api} data-doc-catalogue-group>
                <h2>{String.replace(collection, "_", "-")}</h2>
                <ul>
                  <li :for={entry <- entries} data-doc-catalogue-item>
                    <a href={entry.route}>{entry.title}<span>{entry.version}</span></a>
                  </li>
                </ul>
              </section>
            </section>
          </details>
          <details
            :if={@packages != []}
            class="doc-catalogue"
            data-doc-catalogue="packages"
            data-pagefind-ignore
          >
            <summary>Packages</summary><section id="doc-packages" aria-label="Packages">
              <h1 tabindex="-1">Packages</h1>
              <label class="doc-catalogue-filter">Filter packages<input
                type="search"
                data-doc-catalogue-filter="packages"
                autocomplete="off"
              /></label>
              <p role="status" data-doc-catalogue-status></p>
              <ul>
                <li :for={package <- @packages} data-doc-catalogue-item>
                  <a href={package.route}>{String.replace(package.collection_id, "_", "-")}<span>{package.package_version}</span></a>
                </li>
              </ul>
            </section>
          </details>
        </main>
        <div :if={@page && @renderer?} class="doc-contents">
          <.shared component={:table_of_contents} arguments={%{headings: @page.headings}} />
        </div>
      </div>
    </div>
    """
  end

  attr(:component, :atom, required: true)
  attr(:arguments, :map, required: true)
  slot(:header)
  slot(:controls)

  defp shared(assigns) do
    arguments = Map.put(assigns.arguments, :__changed__, nil)

    arguments =
      if assigns.component == :search,
        do: Map.merge(arguments, %{header: assigns.header, controls: assigns.controls}),
        else: arguments

    :erlang.apply(PhoenixAssets.DocShell.Components, assigns.component, [arguments])
  end

  defp content(nil), do: {nil, nil}

  defp content(%{content: [%{"tag" => "h1", "content" => children} = heading | rest]} = page) do
    if String.trim(plain_text(children)) == String.trim(page.title),
      do: {render_ast([heading]), render_ast(rest)},
      else: {nil, render_ast(page.content)}
  end

  defp content(page) do
    {nil, render_ast(page.content)}
  end

  defp render_ast(nodes) do
    if Code.ensure_loaded?(PhoenixAssets.DocShell.Ast),
      do: :erlang.apply(PhoenixAssets.DocShell.Ast, :render, [nodes])
  end

  defp plain_text(nodes) do
    Enum.map_join(nodes, fn
      text when is_binary(text) -> text
      %{"content" => children} -> plain_text(children)
      _ -> ""
    end)
  end

  defp home(nil), do: "/docs/start/"

  defp home(site) do
    paths = navigation_paths(site.navigation)
    Enum.find(paths, &String.ends_with?(&1, "/start/")) || List.first(paths) || site.base_path
  end

  defp navigation_paths(items),
    do:
      Enum.flat_map(items, fn item ->
        if(item.path == "", do: [], else: [item.path]) ++ navigation_paths(item.children)
      end)

  defp api(nil), do: []

  defp api(site) do
    site.search
    |> Enum.filter(&(&1.kind in ["module", "openapi"]))
    |> Enum.map(
      &%{
        route: URI.parse(&1.route).path,
        title: &1.title,
        collection: &1.collection,
        version: &1.version
      }
    )
    |> Enum.uniq_by(& &1.route)
    |> Enum.sort_by(&{&1.collection, &1.title})
    |> Enum.group_by(& &1.collection)
    |> Enum.sort_by(fn {collection, _} -> collection end)
  end

  defp packages(nil), do: []

  defp packages(site) do
    site.search
    |> Enum.filter(&("scope:package" in &1.tags))
    |> Enum.map(
      &%{route: URI.parse(&1.route).path, collection_id: &1.collection, package_version: &1.version}
    )
    |> Enum.sort_by(& &1.collection_id)
    |> Enum.uniq_by(& &1.collection_id)
  end

  defp search(nil, _), do: %{"records" => []}

  defp search(site, context) do
    search =
      Map.get(context, :search, %{
        "records" => site.search,
        "contract" => Map.get(site.metadata, "search_contract", %{"algorithm" => "embedded/v1"})
      })

    if get_in(search, ["contract", "algorithm"]) == "pagefind/v1",
      do: Map.put(search, "records", []),
      else: search
  end

  defp section(nil), do: "guides"
  defp section(%{kind: kind}) when kind in ["module", "openapi"], do: "api"
  defp section(page), do: if("scope:package" in page.tags, do: "packages", else: "guides")

  defp filter_values(nil), do: %{}

  defp filter_values(site) do
    for {field, key} <- [
          {"collection", :collection},
          {"kind", :kind},
          {"locale", :locale},
          {"audience", :audience},
          {"version", :version},
          {"tag", :tags},
          {"status", :status}
        ],
        into: %{} do
      {field,
       site.search
       |> Enum.flat_map(&List.wrap(Map.get(&1, key)))
       |> Enum.filter(&is_binary/1)
       |> Enum.uniq()
       |> Enum.sort()}
    end
  end

  defp asset(assets, name, fallback), do: Map.get(assets, name, fallback)
end
