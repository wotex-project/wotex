defmodule WotexLabWorkbenchWeb.ReportController do
  @moduledoc """
  Exports the evidence report from the room owned by a verified browser session.

  The controller reads a room snapshot and delegates report admission and
  encoding to `WotexLabWorkbench.Report`. A successful response is a JSON
  attachment. A session without a room receives HTTP 404, an oversized report
  receives HTTP 413, and other tagged refusals receive HTTP 403. The route does
  not accept a room identifier from request parameters or rerun an experiment.
  """

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.{Report, Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @doc "Sends the report, or a plain-text refusal when the session has no room."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _) do
    with {:ok, %{room: room}} when is_pid(room) <-
           Sessions.verify(get_session(conn, SessionToken.key())),
         report = Report.build(Room.snapshot(room)),
         {:ok, json} <- Report.encode(report) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="wotex-lab-evidence.json"))
      |> send_resp(200, json)
    else
      {:ok, _} -> refuse(conn, 404, "no room: start one from the workbench")
      {:error, :too_large} -> refuse(conn, 413, "report exceeds the byte ceiling")
      {:error, _} -> refuse(conn, 403, "session denied")
    end
  end

  defp refuse(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
