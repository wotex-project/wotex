defmodule WotexLabWorkbenchWeb.SessionController do
  @moduledoc "Drops the cookie session so the next request opens a fresh one."

  use WotexLabWorkbenchWeb, :controller

  @doc "Clears the session and redirects to the workbench."
  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end
end
