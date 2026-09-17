defmodule WotexLabWorkbench.Control.Limits do
  @moduledoc """
  Host-owned rate and concurrency admission for HTTP control mutations.

  The application starts this process only when the operator replaced the
  default `control_mutations: false` value with a limit list. `configure/1`
  validates that list: `max_requests` admissions per session in a fixed
  `window_ms` window, `session_concurrency` mutations in flight per session,
  `host_concurrency` in flight across the host and up to eight extra exact
  `origins`. Unknown or duplicate keys and out-of-range values are refused.

  `acquire/2` admits one mutation for a verified session identifier and
  monitors the calling request process; `release/2` or that process's exit
  frees the slot. A refused acquisition returns `rate_limited` with the
  remaining window in `details.retry_after_ms`, or `concurrency_limited`.
  Admission counts are kept per live window only, so an idle session's entry
  is discarded when its window ends. The process never reads a session, room
  or request body.
  """

  use GenServer

  alias Wotex.Lab.Error

  @defaults [
    max_requests: 30,
    window_ms: 60_000,
    session_concurrency: 1,
    host_concurrency: 8,
    origins: []
  ]
  @origin ~r/\Ahttps?:\/\/[A-Za-z0-9.-]{1,253}(?::[0-9]{1,5})?\z/

  @type options :: [
          max_requests: pos_integer(),
          window_ms: pos_integer(),
          session_concurrency: pos_integer(),
          host_concurrency: pos_integer(),
          origins: [String.t()]
        ]

  @doc "Validates a limit list and fills the defaults for omitted keys."
  @spec configure(term()) :: {:ok, options()} | {:error, Error.t()}
  def configure(opts) when is_list(opts) do
    keys = if Keyword.keyword?(opts), do: Keyword.keys(opts), else: [:invalid]

    with true <- Enum.uniq(keys) == keys and Enum.all?(keys, &Keyword.has_key?(@defaults, &1)),
         options = Keyword.merge(@defaults, opts),
         true <- valid?(options) do
      {:ok, options}
    else
      false -> invalid()
    end
  end

  def configure(_), do: invalid()

  @doc "Starts the limiter with a list admitted by `configure/1` and an optional `:name`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, limits} = Keyword.pop(opts, :name, __MODULE__)

    case configure(limits) do
      {:ok, options} -> GenServer.start_link(__MODULE__, options, name: name)
      {:error, error} -> {:error, error}
    end
  end

  @doc "The exact origins admitted in addition to the endpoint origin."
  @spec origins(GenServer.server()) :: [String.t()]
  def origins(server \\ __MODULE__), do: GenServer.call(server, :origins)

  @doc "Admits one mutation for a session and monitors the caller until release."
  @spec acquire(GenServer.server(), String.t()) :: {:ok, reference()} | {:error, Error.t()}
  def acquire(server \\ __MODULE__, session_id) when is_binary(session_id),
    do: GenServer.call(server, {:acquire, session_id})

  @doc "Releases a slot returned by `acquire/2`; unknown slots are ignored."
  @spec release(GenServer.server(), reference()) :: :ok
  def release(server \\ __MODULE__, slot) when is_reference(slot),
    do: GenServer.call(server, {:release, slot})

  @impl GenServer
  def init(options) do
    {:ok,
     %{
       limits: Map.new(options),
       sessions: %{},
       slots: %{},
       in_flight: 0
     }}
  end

  @impl GenServer
  def handle_call(:origins, _, state), do: {:reply, state.limits.origins, state}

  def handle_call({:acquire, session_id}, {caller, _}, state) do
    now = System.monotonic_time(:millisecond)
    state = expire(state, now)
    entry = Map.get(state.sessions, session_id, %{started: now, admitted: 0, in_flight: 0})
    limits = state.limits

    cond do
      entry.in_flight >= limits.session_concurrency or state.in_flight >= limits.host_concurrency ->
        {:reply,
         {:error, Error.new(:concurrency_limited, :control_api, "mutation already running")}, state}

      entry.admitted >= limits.max_requests ->
        retry = entry.started + limits.window_ms - now

        {:reply,
         {:error,
          Error.new(:rate_limited, :control_api, "mutation rate limit reached",
            details: %{retry_after_ms: max(retry, 1)},
            class: :rate_limited
          )}, state}

      true ->
        slot = Process.monitor(caller)
        entry = %{entry | admitted: entry.admitted + 1, in_flight: entry.in_flight + 1}

        {:reply, {:ok, slot},
         %{
           state
           | sessions: Map.put(state.sessions, session_id, entry),
             slots: Map.put(state.slots, slot, session_id),
             in_flight: state.in_flight + 1
         }}
    end
  end

  def handle_call({:release, slot}, _, state) do
    Process.demonitor(slot, [:flush])
    {:reply, :ok, free(state, slot)}
  end

  @impl GenServer
  def handle_info({:DOWN, slot, :process, _, _}, state), do: {:noreply, free(state, slot)}

  defp free(state, slot) do
    case Map.pop(state.slots, slot) do
      {nil, _} ->
        state

      {session_id, slots} ->
        sessions =
          Map.update!(state.sessions, session_id, fn entry ->
            %{entry | in_flight: entry.in_flight - 1}
          end)

        %{state | slots: slots, sessions: sessions, in_flight: state.in_flight - 1}
    end
  end

  defp expire(state, now) do
    window = state.limits.window_ms

    sessions =
      Map.new(state.sessions, fn
        {id, %{started: started} = entry} when now - started >= window ->
          {id, %{entry | started: now, admitted: 0}}

        pair ->
          pair
      end)
      |> Map.reject(fn {_, entry} -> entry.admitted == 0 and entry.in_flight == 0 end)

    %{state | sessions: sessions}
  end

  defp valid?(options) do
    integer_in?(options[:max_requests], 1..600) and
      integer_in?(options[:window_ms], 100..3_600_000) and
      integer_in?(options[:session_concurrency], 1..8) and
      integer_in?(options[:host_concurrency], 1..64) and
      options[:session_concurrency] <= options[:host_concurrency] and
      origins?(options[:origins])
  end

  defp origins?(origins) when is_list(origins) and length(origins) <= 8,
    do: Enum.all?(origins, &(is_binary(&1) and Regex.match?(@origin, &1)))

  defp origins?(_), do: false

  defp integer_in?(value, range), do: is_integer(value) and value in range

  defp invalid,
    do: {:error, Error.new(:invalid_control_limits, :control_api, "control limits are invalid")}
end
