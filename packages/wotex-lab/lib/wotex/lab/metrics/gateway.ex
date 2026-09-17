defmodule Wotex.Lab.Metrics.Gateway do
  @moduledoc """
  One disposable, owner-bound metric inspection capability.

  A trusted host explicitly starts this process with an authenticated `:scope`,
  an `:owner` PID and exactly one source: a live `:history` PID or a `:durable`
  executor. Only that owner can submit requests, cancel queries, inspect
  counters or revoke access. Request text cannot replace any binding or budget.
  The gateway dies when its owner or its exact history dies; it never follows a
  restarted registered history into new data.

  A `:durable` binding answers each admitted descriptor through
  `Wotex.Lab.Metrics.DurableQuery.query/3` with that one-argument host executor
  and the optional `:capture_interval_ms` (5,000 by default, 1,000 to 60,000).
  The executor runs inside the query worker, so cancellation, expiry, owner
  death and the deadline stop it together with the worker. Receiver, database,
  endpoint, credential and response bounds belong to the executor; the gateway
  itself opens no connection.

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
  No model, automatic introspection or Action starts here, and only a
  host-bound durable executor performs network access.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{DurableQuery, History, Query, Request}

  @options ~w(history durable capture_interval_ms scope owner ttl_ms max_calls query_limits)a

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

  def cancel(_, _), do: failure(:invalid_request)

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
    history_monitor = if config.history, do: Process.monitor(config.history)
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
  def handle_call(_, {caller, _}, %{owner: owner} = state) when caller != owner,
    do: {:reply, failure(:scope_denied), state}

  def handle_call({:query, request, submitted_at}, _, state) do
    with :ok <- capacity(state),
         {:ok, query} <- Request.decode(request, state.scope, state.limits),
         {:ok, _} <- Query.estimate(query),
         deadline = min(submitted_at + query.limits.deadline_ms, state.expires_at),
         true <- now() < deadline do
      {reference, state} = launch(state, query, deadline)
      {:reply, {:ok, reference}, state}
    else
      false -> {:reply, failure(:deadline_exceeded), state}
      {:error, _} = denied -> {:reply, denied, state}
    end
  end

  def handle_call({:cancel, reference}, _, state) do
    if Map.has_key?(state.queries, reference) do
      {:reply, :ok, finish(state, reference, failure(:query_cancelled), :cancelled)}
    else
      {:reply, failure(:unknown_query), state}
    end
  end

  def handle_call(:revoke, _, state),
    do: {:stop, :normal, :ok, close(state, :scope_revoked)}

  def handle_call(:stats, _, state) do
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

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:deadline, reference}, state),
    do: {:noreply, finish(state, reference, failure(:deadline_exceeded), :timed_out)}

  def handle_info({:expire, expiry}, %{expiry: expiry} = state),
    do: {:stop, :normal, close(state, :scope_expired)}

  def handle_info({:DOWN, monitor, :process, _, _}, state)
      when monitor == state.owner_monitor or monitor == state.history_monitor do
    code = if monitor == state.owner_monitor, do: :scope_revoked, else: :history_unavailable
    {:stop, :normal, close(state, code)}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    reference =
      Enum.find_value(state.queries, fn {ref, query} -> if query.monitor == monitor, do: ref end)

    {:noreply, finish(state, reference, failure(:query_failed), :failed)}
  end

  # Worker DOWN messages carry the outcome. Parent exits are handled by OTP;
  # normal linked worker exits do not change this gateway's scope.
  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}
  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    Process.cancel_timer(state.expiry_timer)
    close(state, :scope_revoked)
    :ok
  end

  defp launch(state, query, deadline) do
    gateway = self()
    reference = make_ref()
    answer = answer(state, query)

    {worker, monitor} =
      :erlang.spawn_opt(
        fn -> send(gateway, {:query_result, self(), reference, answer.()}) end,
        [:link, :monitor]
      )

    timer = Process.send_after(self(), {:deadline, reference}, max(deadline - now(), 0))
    entry = %{worker: worker, monitor: monitor, timer: timer, deadline: deadline}

    {reference, count(%{state | queries: Map.put(state.queries, reference, entry)}, :admitted)}
  end

  defp answer(%{durable: executor, capture_interval_ms: interval}, query)
       when is_function(executor, 1),
       do: fn -> DurableQuery.query(query, executor, capture_interval_ms: interval) end

  defp answer(%{history: history}, query), do: fn -> History.query(history, query) end

  defp finish(state, reference, result, counter) do
    case Map.pop(state.queries, reference) do
      {nil, _} ->
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
      {:DOWN, ^monitor, :process, _, _} -> :ok
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
  defp before_delivery(result, counter, _), do: {result, counter}

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
         {:ok, source} <- source(config),
         true <- local_alive?(config[:owner]),
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
      {:ok,
       config
       |> Map.merge(source)
       |> Map.merge(%{ttl_ms: ttl, max_calls: calls, limits: probe.limits})}
    else
      _ -> failure(:invalid_gateway)
    end
  end

  defp source(%{history: history} = config) when not is_map_key(config, :durable) do
    if local_alive?(history) and not is_map_key(config, :capture_interval_ms),
      do: {:ok, %{history: history, durable: nil}},
      else: :error
  end

  defp source(%{durable: executor} = config)
       when is_function(executor, 1) and not is_map_key(config, :history) do
    case Map.get(config, :capture_interval_ms, 5_000) do
      interval when is_integer(interval) and interval in 1_000..60_000 ->
        {:ok, %{history: nil, durable: executor, capture_interval_ms: interval}}

      _ ->
        :error
    end
  end

  defp source(_), do: :error

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
    :exit, _ -> failure(:scope_unavailable)
  end

  defp call(_, _), do: failure(:scope_unavailable)

  defp failure(code),
    do: {:error, Error.new(code, :query, "inspection request is unavailable or refused")}
end
