defmodule Wotex.Lab.Metrics.Gateway do
  @moduledoc """
  One disposable, owner-bound local-history inspection capability.

  A trusted host explicitly starts this process with a live `:history` PID,
  authenticated `:scope` and `:owner` PID. Only that owner can submit requests,
  cancel queries, inspect counters or revoke access. Request text cannot
  replace any binding or budget. The gateway dies when its owner or its exact
  history dies; it never follows a restarted registered history into new data.

  Defaults are 30 seconds of scope lifetime, 12 admitted calls, two workers
  and the `Query` defaults. Hosts may reduce query limits, not enlarge them;
  scope lifetime has a 60-second ceiling and call count a 128-call ceiling.
  `query/2` returns a reference immediately after admission and delivers exactly
  one `{:metric_query, gateway, reference, result}` terminal message per call
  while alive. Owners must monitor the gateway: abrupt process/VM death can
  prevent delivery and means unavailable, not successful cancellation.
  Results remain inert; previously delivered messages
  cannot be recalled and frontends must ignore results for closed scopes.

  There is no accepted-work queue. Workers are linked and monitored; expiry,
  cancellation, owner death and shutdown kill pending work. The query deadline
  starts before submission, includes history admission waits and is checked
  again before delivering a result. This is an OTP lifecycle/deadline boundary,
  not a hard real-time guarantee or hostile-code/OS sandbox.

  This is an in-VM capability, not a network credential. The host must bind
  owner/scope from its authentication context, limit simultaneous gateways per
  session, and bound transport ingress. Arbitrary same-BEAM callers are trusted;
  GenServer calls alone do not bound a hostile population's mailbox traffic.
  No HTTP, database, model, automatic introspection or Action starts here.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{History, Query, Request}

  @options ~w(history scope owner ttl_ms max_calls query_limits)a

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @doc "Starts an explicitly bound inspection; invalid options start no process."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with {:ok, config} <- configure(opts), do: GenServer.start_link(__MODULE__, config)
  end

  @doc "Admits closed request fields and returns the asynchronous result reference."
  @spec query(pid(), term()) :: {:ok, reference()} | {:error, Error.t()}
  def query(gateway, request), do: call(gateway, {:query, request, now()})

  @doc "Cancels one admitted query without refunding its call budget."
  @spec cancel(pid(), reference()) :: :ok | {:error, Error.t()}
  def cancel(gateway, reference) when is_reference(reference),
    do: call(gateway, {:cancel, reference})

  def cancel(_gateway, _reference), do: failure(:invalid_request)

  @doc "Revokes this scope, cancels pending work and stops the temporary gateway."
  @spec revoke(pid()) :: :ok | {:error, Error.t()}
  def revoke(gateway), do: call(gateway, :revoke)

  @doc "Owner-only bounded counters; no request, scope identifier or result data."
  @spec stats(pid()) :: map() | {:error, Error.t()}
  def stats(gateway), do: call(gateway, :stats)

  @impl GenServer
  def init(config) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(config.owner)
    history_monitor = Process.monitor(config.history)
    expiry = make_ref()
    timer = Process.send_after(self(), {:expire, expiry}, config.ttl_ms)

    {:ok,
     Map.merge(config, %{
       owner_monitor: owner_monitor,
       history_monitor: history_monitor,
       expiry: expiry,
       expiry_timer: timer,
       expires_at: now() + config.ttl_ms,
       queries: %{},
       counters: %{admitted: 0, completed: 0, failed: 0, cancelled: 0, timed_out: 0}
     })}
  end

  @impl GenServer
  def handle_call(_request, {caller, _tag}, %{owner: owner} = state) when caller != owner,
    do: {:reply, failure(:scope_denied), state}

  def handle_call({:query, request, submitted_at}, _from, state) do
    with :ok <- capacity(state),
         {:ok, query} <- Request.decode(request, state.scope, state.limits),
         {:ok, _estimate} <- Query.estimate(query),
         deadline = min(submitted_at + query.limits.deadline_ms, state.expires_at),
         true <- now() < deadline do
      {reference, state} = launch(state, query, deadline)
      {:reply, {:ok, reference}, state}
    else
      false -> {:reply, failure(:deadline_exceeded), state}
      {:error, _error} = denied -> {:reply, denied, state}
    end
  end

  def handle_call({:cancel, reference}, _from, state) do
    if Map.has_key?(state.queries, reference) do
      {:reply, :ok, finish(state, reference, failure(:query_cancelled), :cancelled)}
    else
      {:reply, failure(:unknown_query), state}
    end
  end

  def handle_call(:revoke, _from, state),
    do: {:stop, :normal, :ok, close(state, :scope_revoked)}

  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.counters, %{
        active: map_size(state.queries),
        max_active: state.limits.concurrent,
        max_calls: state.max_calls
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info({:query_result, worker, reference, result}, state) do
    case Map.get(state.queries, reference) do
      %{worker: ^worker, deadline: deadline} ->
        {result, counter} = outcome(result, deadline)
        {:noreply, finish(state, reference, result, counter)}

      _unknown ->
        {:noreply, state}
    end
  end

  def handle_info({:deadline, reference}, state),
    do: {:noreply, finish(state, reference, failure(:deadline_exceeded), :timed_out)}

  def handle_info({:expire, expiry}, %{expiry: expiry} = state),
    do: {:stop, :normal, close(state, :scope_expired)}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.owner_monitor or monitor == state.history_monitor do
    code = if monitor == state.owner_monitor, do: :scope_revoked, else: :history_unavailable
    {:stop, :normal, close(state, code)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    reference =
      Enum.find_value(state.queries, fn {ref, query} -> if query.monitor == monitor, do: ref end)

    {:noreply, finish(state, reference, failure(:query_failed), :failed)}
  end

  # Worker DOWN messages carry the outcome. Parent exits are handled by OTP;
  # normal linked worker exits do not change this gateway's scope.
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_late, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    Process.cancel_timer(state.expiry_timer)
    close(state, :scope_revoked)
    :ok
  end

  defp launch(state, query, deadline) do
    gateway = self()
    reference = make_ref()
    history = state.history

    {worker, monitor} =
      :erlang.spawn_opt(
        fn -> send(gateway, {:query_result, self(), reference, History.query(history, query)}) end,
        [:link, :monitor]
      )

    timer = Process.send_after(self(), {:deadline, reference}, max(deadline - now(), 0))
    entry = %{worker: worker, monitor: monitor, timer: timer, deadline: deadline}

    {reference, count(%{state | queries: Map.put(state.queries, reference, entry)}, :admitted)}
  end

  defp finish(state, reference, result, counter) do
    case Map.pop(state.queries, reference) do
      {nil, _queries} ->
        state

      {entry, queries} ->
        stop_worker(entry)
        {result, counter} = before_delivery(result, counter, entry.deadline)
        send(state.owner, {:metric_query, self(), reference, result})
        count(%{state | queries: queries}, counter)
    end
  end

  defp stop_worker(entry) do
    Process.cancel_timer(entry.timer)
    monitor = Process.monitor(entry.worker)
    Process.exit(entry.worker, :kill)

    receive do
      {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
    after
      1_000 -> exit(:worker_shutdown_timeout)
    end

    Process.demonitor(entry.monitor, [:flush])
    Process.unlink(entry.worker)
  end

  defp close(state, code) do
    Enum.reduce(Map.keys(state.queries), state, fn reference, state ->
      finish(state, reference, failure(code), :cancelled)
    end)
  end

  defp outcome(result, deadline) do
    cond do
      now() >= deadline -> {failure(:deadline_exceeded), :timed_out}
      match?({:ok, _}, result) -> {result, :completed}
      true -> {result, :failed}
    end
  end

  defp before_delivery(result, :completed, deadline), do: outcome(result, deadline)
  defp before_delivery(result, counter, _deadline), do: {result, counter}

  defp count(state, counter),
    do: %{state | counters: Map.update!(state.counters, counter, &(&1 + 1))}

  defp capacity(state) do
    cond do
      now() >= state.expires_at -> failure(:scope_expired)
      state.counters.admitted >= state.max_calls -> failure(:query_budget_exhausted)
      map_size(state.queries) >= state.limits.concurrent -> failure(:too_many_queries)
      true -> :ok
    end
  end

  defp configure(opts) do
    with :ok <- Options.validate(opts, @options),
         config = Map.new(opts),
         true <- local_alive?(config[:owner]) and local_alive?(config[:history]),
         ttl = Map.get(config, :ttl_ms, 30_000),
         calls = Map.get(config, :max_calls, 12),
         true <- bounded?(ttl, 1, 60_000) and bounded?(calls, 1, 128),
         {:ok, probe} <-
           Query.new(
             scope: config[:scope],
             metric: :nx_queue_depth,
             aggregation: :last,
             limits: Map.get(config, :query_limits, %{})
           ),
         true <- reduced_limits?(probe.limits) do
      {:ok, Map.merge(config, %{ttl_ms: ttl, max_calls: calls, limits: probe.limits})}
    else
      _invalid -> failure(:invalid_gateway)
    end
  end

  defp reduced_limits?(limits) do
    Enum.all?(Query.default_limits(), fn
      {:min_step_ms, value} -> limits.min_step_ms >= value
      {key, value} -> limits[key] <= value
    end)
  end

  defp bounded?(value, floor, ceiling),
    do: is_integer(value) and value >= floor and value <= ceiling

  defp local_alive?(pid), do: is_pid(pid) and node(pid) == node() and Process.alive?(pid)

  defp now, do: System.monotonic_time(:millisecond)

  defp call(gateway, message) when is_pid(gateway) and node(gateway) == node() do
    GenServer.call(gateway, message, 5_000)
  catch
    :exit, _reason -> failure(:scope_unavailable)
  end

  defp call(_gateway, _message), do: failure(:scope_unavailable)

  defp failure(code),
    do: {:error, Error.new(code, :query, "inspection request is unavailable or refused")}
end
