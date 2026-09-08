defmodule WotexLabWorkbenchWeb.Scope do
  @moduledoc """
  The `on_mount` hook that binds a LiveView to its session scope.

  The token from the signed cookie session is verified on every mount and
  assigned as `@scope`; an unknown, malformed or expired token mounts the
  view in a denied state that renders nothing but the reason and a link to
  start a new session. `admit/2` repeats the check for every event.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @type scope :: %{token: String.t(), session_id: String.t(), theme: String.t(), room: pid() | nil}

  @doc false
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    token = Map.get(session, SessionToken.key())

    case Sessions.verify(token) do
      {:ok, live} ->
        {:cont, assign(socket, :scope, scope(token, live))}

      {:error, %Error{code: code}} ->
        {:cont, socket |> assign(:scope, nil) |> assign(:denied, Atom.to_string(code))}
    end
  end

  @doc "Re-verifies the scope for a command and returns the live session."
  @spec admit(Phoenix.LiveView.Socket.t(), atom()) :: {:ok, scope()} | {:error, Error.t()}
  def admit(%{assigns: %{scope: %{token: token}}}, command) do
    with {:ok, live} <- Sessions.admit(token, command), do: {:ok, scope(token, live)}
  end

  def admit(_socket, _command), do: {:error, Error.new(:denied, :session, "no session scope")}

  @doc "Re-verifies a socket's session without admitting or starting a room command."
  @spec verify(Phoenix.LiveView.Socket.t()) :: {:ok, scope()} | {:error, Error.t()}
  def verify(%{assigns: %{scope: %{token: token}}}) do
    with {:ok, live} <- Sessions.verify(token), do: {:ok, scope(token, live)}
  end

  def verify(_socket), do: {:error, Error.new(:denied, :session, "no session scope")}

  defp scope(token, live),
    do: %{token: token, session_id: live.id, theme: live.theme, room: live.room}
end
