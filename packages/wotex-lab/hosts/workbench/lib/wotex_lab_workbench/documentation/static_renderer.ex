defmodule WotexLabWorkbench.Documentation.StaticRenderer do
  @moduledoc """
  Renders the Workbench reader with shared DocShell content and browser behavior.

  Pagefind owns search in the static publication. The renderer therefore gets
  the validated search contract but not a duplicate copy of every search record
  on every generated page. The hosted reader applies the same policy when its
  admitted site selects Pagefind; embedded search adapters retain their records.
  """

  alias Phoenix.HTML
  alias WotexLabWorkbench.Documentation.Assets
  alias WotexLabWorkbenchWeb.DocumentationComponents

  @renderer PhoenixAssets.DocShell.StaticRenderer

  @doc "Returns the capabilities of the selected shared renderer."
  @spec capabilities() :: term()
  def capabilities, do: invoke(:capabilities, [])

  @doc "Returns shared renderer assets and the same local Lab assets used by hosted pages."
  @spec assets(term(), keyword()) :: term()
  def assets(site, options) do
    with {:ok, shared} <- invoke(:assets, [site, options]),
         {:ok, owned} <- Assets.all() do
      {:ok, shared ++ owned}
    end
  end

  @doc "Renders one page without embedding the complete static search corpus."
  @spec render_page(term(), map()) :: term()
  def render_page(page, context) do
    with :ok <-
           :erlang.apply(DocShell.Presentation.Renderer, :admit, [page, capabilities(), :static]) do
      site = site_context(context)
      body = reader(site, page, context)
      {:ok, document(page.title, page.locale, page.canonical_url, context, body)}
    end
  end

  @doc "Renders the not-found page with the same bounded static search context."
  @spec render_not_found(term(), map()) :: term()
  def render_not_found(site, context) do
    {:ok, document("Page not found", context.locale, nil, context, reader(site, nil, context))}
  end

  defp reader(site, page, context) do
    DocumentationComponents.reader(%{
      site: site,
      page: page,
      context: %{context | search: Map.put(context.search, "records", [])},
      return_path: "/",
      assets: context.assets,
      __changed__: nil
    })
  end

  defp site_context(context) do
    %{
      base_path: context.base_path,
      navigation: context.navigation,
      search: context.search["records"] || [],
      cohort_digest: context.cohort_digest,
      metadata: %{}
    }
  end

  defp document(title, locale, canonical, context, body) do
    canonical = canonical || canonical(context.canonical_origin, context.current_route)
    direction = if locale in ["ar", "fa", "he", "ur"], do: "rtl", else: "ltr"

    [
      "<!doctype html><html lang=\"",
      escape(locale),
      "\" dir=\"",
      direction,
      "\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>",
      escape(title),
      " · ",
      escape(context.site_title),
      "</title>",
      if(canonical, do: ["<link rel=\"canonical\" href=\"", escape(canonical), "\">"], else: []),
      for(
        name <- ["tokens.css", "doc-shell.css", "documentation.css"],
        do: ["<link rel=\"stylesheet\" href=\"", escape(Map.fetch!(context.assets, name)), "\">"]
      ),
      for(
        name <- ["doc-shell-browser.js", "documentation.js"],
        do: [
          "<script type=\"module\" src=\"",
          escape(Map.fetch!(context.assets, name)),
          "\"></script>"
        ]
      ),
      "</head><body>",
      HTML.Safe.to_iodata(body),
      "</body></html>"
    ]
  end

  defp canonical(nil, _), do: nil
  defp canonical(origin, route), do: String.trim_trailing(origin, "/") <> route

  defp escape(value) do
    value
    |> HTML.html_escape()
    |> HTML.Safe.to_iodata()
  end

  defp invoke(function, arguments), do: :erlang.apply(@renderer, function, arguments)
end
