defmodule Wotex.Matter.Bridge.Consumer do
  @moduledoc """
  Owns bounded, policy-gated ExposedThing execution for one bridge generation.

  Start this process explicitly with `start_link/1` or its child specification.
  Configuration requires `:generation`, one `:receiver` pid, a nonblocking
  `:clock` function returning BEAM monotonic milliseconds, an arity-two `:policy`
  and an explicit `:routes` map. It starts a private task supervisor; loading
  the module starts nothing. It opens no native process or network connection.

  Route keys are `{thing_bytes, endpoint, cluster, member, native_operation}`.
  At most 1024 routes cover sixteen distinct Thing/endpoint pairs. Each value
  has exactly `:exposed`, `:operation`, `:name`, `:input` and `:result`.
  `:exposed` is a validated `Wotex.Runtime.ExposedThing`; `:operation` is
  `:readproperty`, `:writeproperty` or `:invokeaction`, matching the native read,
  write or invoke. The named Interaction Affordance and handler must exist.

  Policy receives the complete decoded request and `Wotex.Runtime.Context`.
  Only `:allow` proceeds; `:deny` yields denial, and other returns or exceptions
  fail closed. The context retains the native snapshot and exact route under
  `:matter_bridge`, together with its generation-bound request id and projected
  BEAM deadline. Captured principal/fabric representations do not authenticate
  a caller or establish current authorization. The trusted native Port owner
  supplies that admission; the required consumer policy supplies its own checks.

  After approval, `:input` receives the owned payload and context and must return
  `{:ok, input}`. Consumer mapping owns field interpretation and unit conversion.
  The exact ExposedThing handler then runs. `:result` receives its return and
  context and must explicitly choose `:completed`, `:denied`, `:failed` or
  `:unknown`. It owns any approved-observation delivery before completion;
  handler returns do not automatically update state or establish physical truth.
  Mapping failures yield failure. Dispatch/result exceptions, invalid results
  and execution expiry yield unknown outcome without external exception text.

  Only the receiver may submit or collect results. Its trusted request stream
  must present strictly increasing, non-reused native ids; gaps are permitted.
  `submit/3` requires a qualified `Wotex.Matter.Bridge.ClockProjection` for that
  request. Policy, mapping, dispatch and result acceptance share its original
  deadline. No stage retries. Sixteen slots include both running tasks and
  completed results awaiting `take_result/2`; notifications therefore remain
  bounded even when the receiver stops collecting.

  One `{:wotex_matter_bridge_ready, owner, generation, id}` notification marks
  a staged result. Collection returns the exact native result frame and retires
  its slot once. Receiver death, clock failure, protocol failure or explicit
  close kills owned work. The native Port owner must monitor this process,
  close native custody on its loss, and resolve/refuse rejected submissions
  without retrying mutations. This execution owner does not supply Port
  bootstrap, live SDK checks, observations or authenticated peer evidence.
  """

  use GenServer

  alias Wotex.Matter.Bridge.{ClockProjection, ConsumerConfiguration, Execution, Wire}
  alias Wotex.Matter.Error
  alias Wotex.Runtime.Context

  @limit 16
  @type route_key ::
          {binary(), 3..65_534, non_neg_integer(), non_neg_integer(), :read | :write | :invoke}
  @type outcome :: :completed | :denied | :failed | :unknown
  @type route :: %{
          exposed: Wotex.Runtime.ExposedThing.t(),
          operation: :readproperty | :writeproperty | :invokeaction,
          name: String.t(),
          input: (term(), Context.t() -> {:ok, term()} | {:error, term()}),
          result: (term(), Context.t() -> outcome())
        }

  @doc "Starts one explicitly configured execution owner and its private task supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    with {:ok, configuration} <- ConsumerConfiguration.build(options),
         true <- Process.alive?(configuration.receiver),
         {:ok, now} <- sample(configuration.clock, nil) do
      GenServer.start_link(__MODULE__, Map.put(configuration, :last_ms, now))
    else
      {:error, error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  @doc "Uses temporary supervision so a lost generation is never restarted implicitly."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  @doc "Admits one ordered request under its original qualified deadline."
  @spec submit(pid(), binary(), ClockProjection.t()) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  def submit(owner, frame, projection) when is_pid(owner),
    do: call(owner, {:submit, frame, projection})

  def submit(_, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Collects a staged result once, retaining credit until this call."
  @spec take_result(pid(), pos_integer()) :: {:ok, binary()} | {:error, Error.t()}
  def take_result(owner, id) when is_pid(owner), do: call(owner, {:take_result, id})
  def take_result(_, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Closes execution and joins its owned tasks; no handler is retried."
  @spec close(pid()) :: :ok | {:error, Error.t()}
  def close(owner) when is_pid(owner) do
    GenServer.stop(owner, :normal)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, _ -> {:error, Error.new(:owner_closed)}
  end

  def close(_), do: {:error, Error.new(:invalid_handle)}

  @impl GenServer
  def init(configuration) do
    Process.flag(:trap_exit, true)

    case Task.Supervisor.start_link(max_children: @limit) do
      {:ok, tasks} ->
        {:ok,
         Map.merge(configuration, %{
           tasks: tasks,
           receiver_monitor: Process.monitor(configuration.receiver),
           pending: %{},
           references: %{},
           last_id: 0
         })}

      _ ->
        {:stop, Error.new(:invalid_options)}
    end
  end

  @impl GenServer
  def handle_call({:submit, frame, projection}, {receiver, _}, %{receiver: receiver} = state) do
    with {:ok, request} <- Wire.decode_request(frame, state.generation),
         true <- request.id > state.last_id,
         {:ok, now} <- sample(state.clock, state.last_ms) do
      state = %{state | last_id: request.id, last_ms: now}
      admit(request, projection, now, state)
    else
      :error -> {:stop, :normal, {:error, Error.new(:invalid_transport_context)}, state}
      _ -> {:stop, :normal, {:error, Error.new(:invalid_frame)}, state}
    end
  end

  def handle_call({:take_result, id}, {receiver, _}, %{receiver: receiver} = state) do
    case Map.get(state.pending, id) do
      %{frame: frame, task: nil} ->
        {:reply, {:ok, frame}, %{state | pending: Map.delete(state.pending, id)}}

      _ ->
        {:reply, {:error, Error.new(:invalid_request)}, state}
    end
  end

  def handle_call({:execution_clock, id, token}, {worker, _}, state) do
    case Map.get(state.pending, id) do
      %{token: ^token, task: %Task{pid: ^worker}, deadline: deadline} ->
        case sample(state.clock, state.last_ms) do
          {:ok, now} ->
            reply = if now < deadline, do: :ok, else: :elapsed
            {:reply, reply, %{state | last_ms: now}}

          _ ->
            {:stop, :normal, :elapsed, state}
        end

      _ ->
        {:reply, :elapsed, state}
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_request)}, state}

  @impl GenServer
  def handle_info({reference, outcome}, state) when is_reference(reference) do
    case Map.fetch(state.references, reference) do
      {:ok, id} ->
        entry = Map.fetch!(state.pending, id)
        {:noreply, %{state | pending: Map.put(state.pending, id, %{entry | outcome: outcome})}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{receiver_monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, _, _}, state) do
    case Map.fetch(state.references, reference) do
      {:ok, id} -> finish(id, Map.fetch!(state.pending, id).outcome || :unknown, state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:execution_expired, id, token}, state) do
    case Map.get(state.pending, id) do
      %{token: ^token, task: %Task{} = task} ->
        Task.shutdown(task, :brutal_kill)
        {:noreply, stage(id, :unknown, state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, tasks, _}, %{tasks: tasks} = state), do: {:stop, :normal, state}
  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    for {_, entry} <- state.pending, entry.timer, do: Process.cancel_timer(entry.timer)
    for {_, entry} <- state.pending, entry.task, do: Task.shutdown(entry.task, :brutal_kill)
    if Process.alive?(state.tasks), do: Supervisor.stop(state.tasks, :normal)
    :ok
  end

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{pending: map_size(state.pending), limit: @limit}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  defp admit(request, projection, now, state) do
    native_deadline = request.deadline_native_ms

    with true <- map_size(state.pending) < @limit,
         {:ok, deadline} <-
           ClockProjection.deadline(projection, state.generation, native_deadline, now) do
      path = request.path
      key = {request.thing, path.endpoint, path.cluster, path.member, request.operation}

      start_execution(request, Map.get(state.routes, key), deadline, now, state)
    else
      false -> {:reply, {:error, Error.new(:busy)}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  defp start_execution(request, nil, deadline, _, state) do
    entry = %{
      task: nil,
      timer: nil,
      deadline: deadline,
      token: make_ref(),
      frame: nil,
      outcome: nil
    }

    state = %{state | pending: Map.put(state.pending, request.id, entry)}
    {:reply, {:ok, request.id}, stage(request.id, :denied, state)}
  end

  defp start_execution(request, route, deadline, now, state) do
    owner = self()
    token = make_ref()
    context = context(request, route, deadline)
    policy = state.policy

    task =
      Task.Supervisor.async_nolink(
        state.tasks,
        fn -> Execution.run(owner, request.id, token, request, route, context, policy) end,
        shutdown: :brutal_kill
      )

    timer = Process.send_after(owner, {:execution_expired, request.id, token}, deadline - now)
    entry = %{task: task, timer: timer, deadline: deadline, token: token, frame: nil, outcome: nil}

    {:reply, {:ok, request.id},
     %{
       state
       | pending: Map.put(state.pending, request.id, entry),
         references: Map.put(state.references, task.ref, request.id)
     }}
  rescue
    RuntimeError -> {:reply, {:error, Error.new(:busy)}, state}
  end

  defp context(request, route, deadline) do
    Context.new!(
      request_id:
        "matter-bridge:" <>
          Base.encode16(request.generation, case: :lower) <> ":" <> Integer.to_string(request.id),
      deadline: deadline,
      metadata: %{
        matter_bridge: %{
          request: request,
          operation: route.operation,
          affordance_name: route.name
        }
      }
    )
  end

  defp finish(id, outcome, state) do
    entry = Map.fetch!(state.pending, id)

    case sample(state.clock, state.last_ms) do
      {:ok, now} ->
        outcome =
          if now < entry.deadline and outcome in [:completed, :denied, :failed, :unknown],
            do: outcome,
            else: :unknown

        {:noreply, stage(id, outcome, %{state | last_ms: now})}

      _ ->
        {:stop, :normal, state}
    end
  end

  defp stage(id, outcome, state) do
    entry = Map.fetch!(state.pending, id)
    if entry.timer, do: Process.cancel_timer(entry.timer)
    {:ok, frame} = Wire.encode_result(state.generation, id, outcome)
    ready = %{entry | task: nil, timer: nil, frame: frame}

    references =
      if entry.task, do: Map.delete(state.references, entry.task.ref), else: state.references

    send(state.receiver, {:wotex_matter_bridge_ready, self(), state.generation, id})
    %{state | pending: Map.put(state.pending, id, ready), references: references}
  end

  defp sample(clock, previous) do
    now = clock.()

    if is_integer(now) and now in -0x8000000000000000..0x7FFFFFFFFFFFFFFF and
         (is_nil(previous) or now >= previous),
       do: {:ok, now},
       else: :error
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp call(owner, message) do
    GenServer.call(owner, message)
  catch
    :exit, {:noproc, _} -> {:error, Error.new(:owner_closed)}
    :exit, _ -> {:error, Error.with_effect(Error.new(:owner_closed), :unknown)}
  end
end
