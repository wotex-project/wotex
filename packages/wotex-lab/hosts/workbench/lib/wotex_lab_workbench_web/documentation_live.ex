defmodule WotexLabWorkbenchWeb.DocumentationLive do
  @moduledoc "Public, inert LiveView presentation of the release-built documentation site."

  use WotexLabWorkbenchWeb, :live_view

  alias WotexLabWorkbench.{Documentation, Sessions}
  alias WotexLabWorkbenchWeb.{DocumentationComponents, Plugs.SessionToken}

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    route = route(params)
    socket = assign(socket, :return_path, return_path(session))

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
    ~H"""
    <DocumentationComponents.reader
      site={@site}
      page={@page}
      context={@context}
      return_path={@return_path}
    />
    """
  end

  def render(%{site: site} = assigns) when site != nil do
    ~H"""
    <DocumentationComponents.reader site={@site} return_path={@return_path} />
    """
  end

  def render(assigns), do: unavailable(assigns)

  defp unavailable(assigns) do
    ~H"""
    <DocumentationComponents.reader return_path={@return_path} />
    """
  end

  defp return_path(session) do
    case Sessions.presentation(Map.get(session, SessionToken.key()), :read) do
      {:ok, %{path: path}} -> path
      _ -> "/"
    end
  end

  defp route(%{"path" => segments}) when is_list(segments) do
    case Enum.reject(segments, &(&1 == "")) do
      [] -> "/docs/"
      path -> "/docs/" <> Enum.join(path, "/") <> "/"
    end
  end

  defp route(_), do: "/docs/"
end
