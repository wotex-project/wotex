defmodule WotexLabWorkbench.Documentation.StaticRenderer do
  @moduledoc """
  Applies the Workbench's static-search policy to the shared DocShell renderer.

  Pagefind owns search in the static publication. The renderer therefore gets
  the validated search contract but not a duplicate copy of every search record
  on every generated page. Hosted documentation keeps its server-provided
  fallback records through the ordinary hosted component path.
  """

  @renderer PhoenixAssets.DocShell.StaticRenderer

  @doc "Returns the capabilities of the selected shared renderer."
  @spec capabilities() :: term()
  def capabilities, do: invoke(:capabilities, [])

  @doc "Returns the shared renderer's static assets."
  @spec assets(term(), keyword()) :: term()
  def assets(site, options), do: invoke(:assets, [site, options])

  @doc "Renders one page without embedding the complete static search corpus."
  @spec render_page(term(), map()) :: term()
  def render_page(page, context) do
    invoke(:render_page, [page, static_search(context)])
  end

  @doc "Renders the not-found page with the same bounded static search context."
  @spec render_not_found(term(), map()) :: term()
  def render_not_found(site, context) do
    invoke(:render_not_found, [site, static_search(context)])
  end

  defp static_search(%{search: search} = context) when is_map(search) do
    %{context | search: Map.put(context.search, "records", [])}
  end

  defp invoke(function, arguments), do: :erlang.apply(@renderer, function, arguments)
end
