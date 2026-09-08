defmodule WotexLabWorkbenchWeb.Plugs.SessionToken do
  @moduledoc """
  Issues a session token into the signed cookie session when none exists.

  A present token is left untouched even when it is unknown or expired, so
  a forged or stale token is shown as denied instead of being silently
  replaced; `/session/new` drops the cookie session explicitly.
  """

  @behaviour Plug

  import Plug.Conn

  alias WotexLabWorkbench.Sessions

  @key "workbench_token"

  @doc "The session key holding the token."
  @spec key() :: String.t()
  def key, do: @key

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, @key) do
      nil ->
        case Sessions.open() do
          {:ok, session} -> put_session(conn, @key, session.token)
          {:error, _error} -> conn
        end

      _token ->
        conn
    end
  end
end
