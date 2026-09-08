defmodule WotexLabWorkbenchWeb.ReportController do
  @moduledoc "Exports the bounded JSON evidence report for the caller's own session."

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.{Report, Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @doc "Sends the report, or a plain-text refusal when the session has no room."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    with {:ok, %{room: room}} when is_pid(room) <-
           Sessions.verify(get_session(conn, SessionToken.key())),
         {:ok, json} <- room |> Room.snapshot() |> Report.build() |> Report.encode() do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="wotex-lab-evidence.json"))
      |> send_resp(200, json)
    else
      {:ok, _session} -> refuse(conn, 404, "no room: start one from the workbench")
      {:error, :too_large} -> refuse(conn, 413, "report exceeds the byte ceiling")
      {:error, _error} -> refuse(conn, 403, "session denied")
    end
  end

  defp refuse(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
