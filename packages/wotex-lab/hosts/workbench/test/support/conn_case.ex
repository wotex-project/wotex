defmodule WotexLabWorkbenchWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint WotexLabWorkbenchWeb.Endpoint

      import Phoenix.{ConnTest, LiveViewTest}
      import Plug.Conn
      import WotexLabWorkbenchWeb.ConnCase, only: [track_session: 1]
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc false
  @spec track_session(Plug.Conn.t()) :: Plug.Conn.t()
  def track_session(conn) do
    token = Plug.Conn.get_session(conn, WotexLabWorkbenchWeb.Plugs.SessionToken.key())

    if is_binary(token) do
      on_exit(fn -> WotexLabWorkbench.Sessions.revoke(token) end)
    end

    conn
  end
end
