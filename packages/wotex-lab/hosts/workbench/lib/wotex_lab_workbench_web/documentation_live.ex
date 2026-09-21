defmodule WotexLabWorkbenchWeb.DocumentationLive do
  @moduledoc "Public, inert LiveView presentation of the release-built documentation site."

  use WotexLabWorkbenchWeb, :live_view

  alias WotexLabWorkbench.Documentation

  @impl Phoenix.LiveView
  def mount(params, _, socket) do
    route = route(params)

    case Documentation.fetch_route(route) do
      {:ok, site, page, context} ->
        {:ok, assign(socket, site: site, page: page, context: context, missing: false)}

      {:redirect, target} ->
        {:ok, push_navigate(socket, to: target)}

      {:error, _} ->
        case Documentation.site() do
          {:ok, site} ->
            {:ok, assign(socket, site: site, page: nil, context: nil, missing: true)}

          {:error, reason} ->
            {:ok, assign(socket, site: nil, page: nil, context: nil, missing: reason)}
        end
    end
  end

  @impl Phoenix.LiveView
  def render(%{missing: false} = assigns) do
    module = PhoenixAssets.DocShell.Components

    if Code.ensure_loaded?(module) and function_exported?(module, :page, 1) do
      :erlang.apply(module, :page, [
        %{
          page: assigns.page,
          context: assigns.context,
          brand: [],
          footer: [],
          __changed__: nil
        }
      ])
    else
      unavailable(assigns)
    end
  end

  def render(%{site: site} = assigns) when site != nil do
    module = PhoenixAssets.DocShell.Components

    if Code.ensure_loaded?(module) and function_exported?(module, :not_found, 1) do
      :erlang.apply(module, :not_found, [%{site: site, __changed__: nil}])
    else
      unavailable(assigns)
    end
  end

  def render(assigns), do: unavailable(assigns)

  defp unavailable(assigns) do
    ~H"""
    <main id="doc-main" class="doc-shell-unavailable">
      <h1>Documentation unavailable</h1>
      <p>The built-in documentation artifact is not available in this release.</p>
    </main>
    """
  end

  defp route(%{"path" => segments}) when is_list(segments) do
    case Enum.reject(segments, &(&1 == "")) do
      [] -> "/docs/"
      path -> "/docs/" <> Enum.join(path, "/") <> "/"
    end
  end

  defp route(_), do: "/docs/"
end
