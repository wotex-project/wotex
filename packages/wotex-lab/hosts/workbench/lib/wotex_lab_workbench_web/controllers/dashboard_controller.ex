defmodule WotexLabWorkbenchWeb.DashboardController do
  @moduledoc """
  Downloads a selected set of inert dashboard definitions for a verified session.

  The controller accepts only the panel and selection parameters, delegates
  panel admission to `WotexLabWorkbench.Observability.Panels`, and returns a
  JSON attachment with caching disabled. Invalid selections return HTTP 400;
  failed session admission returns HTTP 403. The export contains catalogue
  queries and presentation settings, with no session or host measurements.
  """

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.Observability.Panels
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @doc "Sends a bounded inert dashboard export for a verified workbench session."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    with {:ok, _session} <- Sessions.verify(get_session(conn, SessionToken.key())),
         true <-
           map_size(params) <= 2 and Enum.all?(Map.keys(params), &(&1 in ["panels", "selection"])),
         true <- Map.get(params, "selection") in [nil, "custom"],
         {:ok, dashboard} <- Panels.dashboard(selection(params)) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="wotex-lab-dashboard.json"))
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, Jason.encode!(dashboard))
    else
      {:error, %Wotex.Lab.Error{code: :invalid_panels}} ->
        send_resp(conn, 400, "invalid panel selection")

      false ->
        send_resp(conn, 400, "unsupported dashboard parameter")

      _denied ->
        send_resp(conn, 403, "session denied")
    end
  end

  defp selection(%{"selection" => "custom"} = params), do: Map.get(params, "panels", [])
  defp selection(params), do: Map.get(params, "panels", Panels.defaults())
end
