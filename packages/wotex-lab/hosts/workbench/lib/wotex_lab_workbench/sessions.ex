defmodule WotexLabWorkbench.Sessions do
  @moduledoc """
  The host's session registry: random per-session tokens, expiry and command
  admission.

  A session is opened by the HTTP layer, identified by a random token the
  browser holds in a signed cookie, and verified again on every LiveView
  mount and event. Expired or revoked sessions lose their room: the room
  process is stopped through `Wotex.Lab.stop_child/3`, which discards every
  granted decision and disposable Thing. Rooms are started only through
  `admit/2` for a command that needs one; opening or verifying a session
  starts nothing.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Observability.Panels
  alias WotexLabWorkbench.Room

  @commands ~w(start_room run cancel approve read register query export verify ask)a
  @themes ~w(system light dark contrast)
  @token_bytes 32
  @option_keys ~w(lab ttl_ms sweep_ms max_sessions name)a

  @type session :: %{
          id: String.t(),
          token: String.t(),
          created_at: integer(),
          expires_at: integer(),
          theme: String.t(),
          dashboard_panels: [String.t()],
          room: pid() | nil
        }

  @doc "Commands that may reach a room; every other event is refused."
  @spec commands() :: [atom()]
  def commands, do: @commands

  @doc "Themes a session may store."
  @spec themes() :: [String.t()]
  def themes, do: @themes

  @doc "Starts the registry with `:lab`, `:ttl_ms`, `:sweep_ms` and `:max_sessions`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with :ok <- validate_options(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
    end
  end

  @doc "Opens a session and returns it with its fresh token."
  @spec open(GenServer.server()) :: {:ok, session()} | {:error, Error.t()}
  def open(server \\ __MODULE__), do: GenServer.call(server, :open)

  @doc "Verifies a token and returns the live session without extending it."
  @spec verify(GenServer.server(), term()) :: {:ok, session()} | {:error, Error.t()}
  def verify(server \\ __MODULE__, token), do: GenServer.call(server, {:verify, token})

  @doc "Admits a command for a token; a room is started for commands that need one."
  @spec admit(GenServer.server(), term(), atom()) :: {:ok, session()} | {:error, Error.t()}
  def admit(server \\ __MODULE__, token, command),
    do: GenServer.call(server, {:admit, token, command})

  @doc "Stores the theme choice for a session."
  @spec put_theme(GenServer.server(), term(), term()) :: {:ok, session()} | {:error, Error.t()}
  def put_theme(server \\ __MODULE__, token, theme),
    do: GenServer.call(server, {:theme, token, theme})

  @doc "Stores a closed, bounded metric-panel arrangement for a session."
  @spec put_dashboard(GenServer.server(), term(), term()) ::
          {:ok, session()} | {:error, Error.t()}
  def put_dashboard(server \\ __MODULE__, token, panel_ids),
    do: GenServer.call(server, {:dashboard, token, panel_ids})

  @doc "Revokes a session and stops its room, discarding pending work."
  @spec revoke(GenServer.server(), term()) :: :ok | {:error, Error.t()}
  def revoke(server \\ __MODULE__, token), do: GenServer.call(server, {:revoke, token})

  @doc "The number of live sessions."
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server \\ __MODULE__), do: GenServer.call(server, :count)

  @impl GenServer
  def init(opts) do
    state = %{
      lab: Keyword.fetch!(opts, :lab),
      ttl_ms: Keyword.fetch!(opts, :ttl_ms),
      max_sessions: Keyword.fetch!(opts, :max_sessions),
      sweep_ms: Keyword.fetch!(opts, :sweep_ms),
      sessions: %{},
      monitors: %{}
    }

    Process.send_after(self(), :sweep, state.sweep_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:open, _, state) do
    if map_size(state.sessions) >= state.max_sessions do
      {:reply, {:error, Error.new(:session_limit, :session, "session capacity reached")}, state}
    else
      now = now_ms()
      token = Base.url_encode64(:crypto.strong_rand_bytes(@token_bytes), padding: false)
      id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

      session = %{
        id: "session-#{id}",
        token: token,
        created_at: now,
        expires_at: now + state.ttl_ms,
        theme: "system",
        dashboard_panels: Panels.defaults(),
        room: nil
      }

      {:reply, {:ok, session}, %{state | sessions: Map.put(state.sessions, token, session)}}
    end
  end

  def handle_call({:verify, token}, _, state) do
    case live(state, token) do
      {:ok, session, state} -> {:reply, {:ok, session}, state}
      {:error, error, state} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:admit, token, command}, _, state) when command in @commands do
    with {:ok, session, state} <- live(state, token),
         {:ok, session, state} <- room_for(state, session, command) do
      session = %{session | expires_at: now_ms() + state.ttl_ms}
      {:reply, {:ok, session}, put_in(state, [:sessions, token], session)}
    else
      {:error, error, state} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:admit, _, _}, _, state) do
    {:reply, {:error, Error.new(:unknown_command, :session, "command is not admitted")}, state}
  end

  def handle_call({:theme, token, theme}, _, state) do
    with {:ok, session, state} <- live(state, token),
         true <- theme in @themes do
      session = %{session | theme: theme}
      {:reply, {:ok, session}, put_in(state, [:sessions, token], session)}
    else
      false ->
        {:reply, {:error, Error.new(:invalid_theme, :session, "theme is not known")}, state}

      {:error, error, state} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:dashboard, token, panel_ids}, _, state) do
    with {:ok, session, state} <- live(state, token),
         {:ok, panels} <- Panels.select(panel_ids) do
      session = %{session | dashboard_panels: Enum.map(panels, & &1.id)}
      {:reply, {:ok, session}, put_in(state, [:sessions, token], session)}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
      {:error, error, state} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:revoke, token}, _, state) do
    case Map.fetch(state.sessions, token) do
      {:ok, session} -> {:reply, :ok, drop(state, session)}
      :error -> {:reply, {:error, unknown()}, state}
    end
  end

  def handle_call(:count, _, state), do: {:reply, map_size(state.sessions), state}

  @impl GenServer
  def handle_info(:sweep, state) do
    now = now_ms()

    state =
      state.sessions
      |> Map.values()
      |> Enum.filter(&(&1.expires_at <= now))
      |> Enum.reduce(state, fn session, acc -> drop(acc, session) end)

    Process.send_after(self(), :sweep, state.sweep_ms)
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _} ->
        {:noreply, state}

      {token, monitors} ->
        sessions =
          case Map.fetch(state.sessions, token) do
            {:ok, session} -> Map.put(state.sessions, token, %{session | room: nil})
            :error -> state.sessions
          end

        {:noreply, %{state | monitors: monitors, sessions: sessions}}
    end
  end

  defp live(state, token) when is_binary(token) and byte_size(token) <= 128 do
    case Map.fetch(state.sessions, token) do
      {:ok, session} ->
        if session.expires_at > now_ms() do
          {:ok, session, state}
        else
          {:error, Error.new(:expired_session, :session, "session expired"), drop(state, session)}
        end

      :error ->
        {:error, unknown(), state}
    end
  end

  defp live(state, _),
    do: {:error, Error.new(:invalid_token, :session, "session token is malformed"), state}

  defp room_for(state, %{room: pid} = session, _) when is_pid(pid),
    do: {:ok, session, state}

  defp room_for(state, session, command) when command in [:start_room, :run, :read, :verify] do
    case Wotex.Lab.start_child(state.lab, :sessions, {Room, id: session.id, lab: state.lab}) do
      {:ok, pid} ->
        monitor = Process.monitor(pid)
        session = %{session | room: pid}

        {:ok, session,
         %{
           state
           | monitors: Map.put(state.monitors, monitor, session.token),
             sessions: Map.put(state.sessions, session.token, session)
         }}

      {:error, reason} ->
        {:error,
         Error.new(:room_unavailable, :session, "room could not start",
           details: %{reason: reason_code(reason)}
         ), state}
    end
  end

  defp room_for(state, _, _),
    do: {:error, Error.new(:no_room, :session, "start a room first"), state}

  defp drop(state, session) do
    if is_pid(session.room) do
      _ = Wotex.Lab.stop_child(state.lab, :sessions, session.room)
    end

    monitors =
      state.monitors
      |> Enum.reject(fn {_, token} -> token == session.token end)
      |> Map.new()

    %{state | sessions: Map.delete(state.sessions, session.token), monitors: monitors}
  end

  defp reason_code(%{code: code}) when is_atom(code), do: code
  defp reason_code(:max_children), do: :max_children
  defp reason_code(_), do: :start_failed

  defp validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: validate_keyword_options(opts), else: invalid_options()
  end

  defp validate_options(_), do: invalid_options()

  defp validate_keyword_options(opts) do
    keys = Keyword.keys(opts)

    if unique_known_keys?(keys) and valid_required_options?(opts) do
      :ok
    else
      invalid_options()
    end
  end

  defp unique_known_keys?(keys),
    do: length(keys) == length(Enum.uniq(keys)) and Enum.all?(keys, &(&1 in @option_keys))

  defp valid_required_options?(opts) do
    ttl = Keyword.get(opts, :ttl_ms)
    sweep = Keyword.get(opts, :sweep_ms)
    maximum = Keyword.get(opts, :max_sessions)

    not is_nil(Keyword.get(opts, :lab)) and valid_intervals?(ttl, sweep) and
      integer_in?(maximum, 1..1_024)
  end

  defp valid_intervals?(ttl, sweep) when is_integer(ttl) and is_integer(sweep),
    do: ttl in 100..86_400_000 and sweep in 10..ttl

  defp valid_intervals?(_, _), do: false
  defp integer_in?(value, range), do: is_integer(value) and value in range

  defp invalid_options,
    do:
      {:error, Error.new(:invalid_session_config, :session, "session registry options are invalid")}

  defp unknown, do: Error.new(:unknown_session, :session, "session is unknown")

  defp now_ms, do: System.monotonic_time(:millisecond)
end
