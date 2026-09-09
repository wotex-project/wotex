defmodule WotexLabWorkbenchWeb.SessionController do
  @moduledoc """
  Resets the browser cookie session and redirects to the Workbench entry point.

  The following request passes through normal session admission. This action
  drops browser session state; it does not directly revoke a server-side room
  or stop a run. Server-owned session expiry and resource cleanup remain with
  `WotexLabWorkbench.Sessions` and the owning room.
  """

  use WotexLabWorkbenchWeb, :controller

  @doc "Clears the session and redirects to the workbench."
  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end
end
