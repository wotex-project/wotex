defmodule WotexLabWorkbenchWeb.ReportController do
  @moduledoc """
  Exports the evidence report from the room owned by a verified browser session.

  The controller reads a room snapshot and delegates report admission and
  encoding to `WotexLabWorkbench.Report`. A successful response is a JSON
  attachment. The optional closed `run` query selects only that owned Run;
  an absent query exports the existing session report. Unknown runs receive
  404, malformed queries 400, oversized reports 413 and session refusals 403.
  The route never accepts a room identifier or reruns an experiment.
  """

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.{Report, Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @doc "Sends the report, or a plain-text refusal when the session has no room."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    with {:ok, %{room: room}} when is_pid(room) <-
           Sessions.verify(get_session(conn, SessionToken.key())),
         {:ok, snapshot, selected} <- select(Room.snapshot(room), params),
         report = scope(Report.build(snapshot), selected),
         {:ok, json} <- Report.encode(report) do
      filename = if selected, do: "wotex-lab-run-evidence.json", else: "wotex-lab-evidence.json"

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, json)
    else
      {:ok, _} -> refuse(conn, 404, "no room: start one from the workbench")
      {:error, :unknown_run} -> refuse(conn, 404, "run unavailable")
      {:error, :invalid_scope} -> refuse(conn, 400, "report query is malformed")
      {:error, :too_large} -> refuse(conn, 413, "report exceeds the byte ceiling")
      {:error, _} -> refuse(conn, 403, "session denied")
    end
  end

  defp select(snapshot, params) when map_size(params) == 0, do: {:ok, snapshot, nil}

  defp select(snapshot, %{"run" => id} = params) when map_size(params) == 1 and is_binary(id) do
    if byte_size(id) in 1..64 and String.valid?(id) do
      case Enum.find(snapshot.runs, &(&1.id == id)) do
        nil -> {:error, :unknown_run}
        run -> {:ok, %{snapshot | runs: [run], datasets: [], formal: [], policy: []}, id}
      end
    else
      {:error, :invalid_scope}
    end
  end

  defp select(_, _), do: {:error, :invalid_scope}

  defp scope(report, nil), do: report
  defp scope(report, id), do: Map.put(report, "scope", %{"kind" => "run", "run_id" => id})

  defp refuse(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
