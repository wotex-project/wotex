defmodule WotexLabWorkbenchWeb.ControlController do
  @moduledoc """
  The bounded JSON implementation of the generated read-only control schema.

  Static catalogue operations are public and inert. Evidence is available only
  with an exact bearer token for the room that retained it. Responses are never
  cached and errors retain the family's stable code/phase/path/message shape.
  """

  use WotexLabWorkbenchWeb, :controller

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Control, Sessions}

  @doc "Lists the admitted scenario descriptors."
  @spec scenarios(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def scenarios(conn, _params), do: reply(conn, 200, %{"scenarios" => Control.scenarios()})

  @doc "Reads one admitted scenario descriptor."
  @spec scenario(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def scenario(conn, %{"id" => id}) do
    case Control.fetch_scenario(id) do
      {:ok, descriptor} -> reply(conn, 200, descriptor)
      {:error, %Error{code: :invalid_scenario_id} = reason} -> error(conn, 400, reason)
      {:error, error} -> error(conn, 404, error)
    end
  end

  @doc "Reads one evidence record from the caller's existing session room."
  @spec evidence(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def evidence(conn, %{"record_id" => record_id}) do
    with {:ok, token} <- bearer(conn),
         {:ok, %{room: room}} when is_pid(room) <- Sessions.verify(token),
         {:ok, record} <- Control.fetch_evidence(room, record_id) do
      reply(conn, 200, record)
    else
      {:ok, _session} ->
        error(conn, 404, api_error(:unknown_evidence, "evidence record is not retained"))

      {:error, %Error{code: :unknown_evidence} = reason} ->
        error(conn, 404, reason)

      {:error, %Error{code: :invalid_record_id} = reason} ->
        error(conn, 400, reason)

      {:error, %Error{} = reason} ->
        error(conn, 403, reason)

      {:error, :missing_bearer} ->
        error(conn, 401, api_error(:missing_bearer, "bearer token is required"))
    end
  end

  @doc "Reads the versioned metric catalogue."
  @spec metrics_catalogue(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def metrics_catalogue(conn, _params), do: reply(conn, 200, Control.metrics_catalogue())

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) in 16..128 -> {:ok, token}
      _missing_or_ambiguous -> {:error, :missing_bearer}
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(body)
  end

  defp error(conn, status, %Error{} = reason) do
    reply(conn, status, %{
      "code" => Atom.to_string(reason.code),
      "phase" => Atom.to_string(reason.phase),
      "path" => reason.path,
      "message" => reason.message
    })
  end

  defp api_error(code, message), do: Error.new(code, :control_api, message)
end
