defmodule WotexLabWorkbenchWeb.HealthController do
  @moduledoc """
  Answers orchestration probes with the required host supervision state.

  `WotexLabWorkbench.Health` determines whether the required processes are
  alive. The response contains only schema version and availability, uses
  HTTP 200 or 503, and disables caching. It exposes no session data and makes
  no claim about external services, protocol peers or experimental correctness.
  """

  use WotexLabWorkbenchWeb, :controller

  alias WotexLabWorkbench.Health

  @doc "Returns 200 when the required host supervision tree is alive, otherwise 503."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    {status, body} =
      case Health.status() do
        :ok -> {200, %{"schema_version" => "1.0.0", "status" => "ok"}}
        {:error, :unavailable} -> {503, %{"schema_version" => "1.0.0", "status" => "unavailable"}}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(body)
  end
end
