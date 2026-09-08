defmodule WotexLabWorkbench.Observability.Inspection do
  @moduledoc """
  Explicit local-operator access to the activated host's metric history.

  `open/1` creates one temporary query gateway per calling process, with a
  server-generated session identifier and the fixed `workbench` instance.
  At most 32 scopes exist, and they expire or disappear on owner/history death.
  The broker starts only with explicit local-history activation. Opening a
  scope performs no query, experiment, introspection or model call.

  This API is for a trusted in-VM operator. Browser sessions cannot open it:
  there is deliberately no route, LiveView event or MCP tool forwarding here.
  A browser session token or scrape credential must never authorize this
  host-wide history. Remote/tenant access needs its independently admitted
  authentication, ingress and isolation profile.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Gateway

  @max_scopes 32

  @doc "Starts the host broker with the explicitly configured history server."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:history]) do
      case resolve(Keyword.get(opts, :history)) do
        history when is_pid(history) -> GenServer.start_link(__MODULE__, history, name: __MODULE__)
        _unavailable -> failure(:history_unavailable)
      end
    end
  end

  @doc "Opens an owner-bound scope; accepts only reduced query limits, TTL and call budget."
  @spec open(keyword()) :: {:ok, pid()} | {:error, Error.t()}
  def open(opts \\ []) do
    with :ok <- Options.validate(opts, [:ttl_ms, :max_calls, :query_limits]),
         do: GenServer.call(__MODULE__, {:open, opts})
  catch
    :exit, _reason -> failure(:inspection_unavailable)
  end

  @doc "The number of live scopes, without owner IDs or query data."
  @spec count() :: non_neg_integer() | {:error, Error.t()}
  def count do
    GenServer.call(__MODULE__, :count)
  catch
    :exit, _reason -> failure(:inspection_unavailable)
  end

  @impl GenServer
  def init(history) do
    Process.flag(:trap_exit, true)
    {:ok, %{history: history, history_monitor: Process.monitor(history), owners: %{}}}
  end

  @impl GenServer
  def handle_call({:open, opts}, {owner, _tag}, state) do
    state = prune(state)

    with :ok <- capacity(state, owner),
         {:ok, gateway} <- Gateway.start_link(binding(state, owner) ++ opts) do
      entry = %{gateway: gateway, monitor: Process.monitor(gateway)}
      {:reply, {:ok, gateway}, put_in(state, [:owners, owner], entry)}
    else
      {:error, _error} = denied -> {:reply, denied, state}
    end
  end

  def handle_call(:count, _from, state) do
    state = prune(state)
    {:reply, map_size(state.owners), state}
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{history_monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, _monitor, :process, _pid, _reason}, state),
    do: {:noreply, prune(state)}

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.owners, fn {_owner, entry} -> stop(entry.gateway) end)
    :ok
  end

  defp binding(state, owner) do
    session = "inspection-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    [history: state.history, owner: owner, scope: %{instance: "workbench", session: session}]
  end

  defp capacity(state, owner) do
    cond do
      Map.has_key?(state.owners, owner) -> failure(:inspection_active)
      map_size(state.owners) >= @max_scopes -> failure(:inspection_capacity)
      true -> :ok
    end
  end

  defp prune(state) do
    owners =
      Map.reject(state.owners, fn {_owner, entry} ->
        if Process.alive?(entry.gateway) do
          false
        else
          Process.demonitor(entry.monitor, [:flush])
          true
        end
      end)

    %{state | owners: owners}
  end

  defp resolve(pid) when is_pid(pid) and node(pid) == node(),
    do: if(Process.alive?(pid), do: pid)

  defp resolve(name) when is_atom(name) and not is_nil(name), do: Process.whereis(name)
  defp resolve(_other), do: nil

  defp stop(gateway) do
    GenServer.stop(gateway, :normal, 1_000)
  catch
    :exit, _reason -> Process.exit(gateway, :kill)
  end

  defp failure(code),
    do: {:error, Error.new(code, :query, "local inspection is unavailable or refused")}
end
