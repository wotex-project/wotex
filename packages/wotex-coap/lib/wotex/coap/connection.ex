defmodule Wotex.CoAP.Connection do
  @moduledoc "Explicit UDP socket owner with bounded RFC 7252 request correlation and retransmission."

  use GenServer

  alias Wotex.CoAP.{
    Blockwise,
    Codec,
    Error,
    Exchange,
    Execution,
    Lifetime,
    Message,
    Observation,
    Subscription
  }

  alias Wotex.CoAP.Datagram.UDP

  @keys [
    :host,
    :port,
    :timeout,
    :ack_timeout,
    :owner,
    :scheme,
    :dtls_mode,
    :datagram,
    :execution,
    :observation_kind,
    :observation_options
  ]

  @doc "Starts a caller-safe linked owner for an explicitly selected datagram adapter."
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, Error.t()}
  def start_link(opts) do
    with {:ok, config} <- config(opts),
         {:ok, pid} <- GenServer.start(__MODULE__, Map.put(config, :creator, self())) do
      await_ready(pid, config.timeout)
    end
  end

  @doc "Runs one validated wire exchange with a finite deadline including queue time."
  @spec request(pid(), Message.t(), pos_integer()) :: {:ok, Message.t()} | {:error, Error.t()}
  def request(pid, message, timeout), do: submit(pid, message, timeout, :request, [])

  @doc "Preserves exclusive complete-body transfer under a single absolute deadline."
  @spec transfer(pid(), Message.t(), pos_integer(), keyword()) ::
          {:ok, Message.t()} | {:error, Error.t()}
  def transfer(pid, message, timeout, options \\ []),
    do: submit(pid, message, timeout, :transfer, options)

  @doc "Assembles an already received first report under one bounded continuation deadline."
  @spec continue(pid(), Message.t(), Message.t(), pos_integer(), keyword()) ::
          {:ok, Message.t()} | {:error, Error.t()}
  def continue(pid, request, first, timeout, options \\ []),
    do: submit(pid, request, timeout, {:continue, first}, options)

  @doc "Establishes one dedicated Observe relationship and returns only after its initial body."
  @spec observe(pid(), binary(), pid(), keyword(), pos_integer()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def observe(pid, path, receiver, options, timeout)
      when is_integer(timeout) and timeout in 1..60_000 do
    deadline = Execution.now_ms(Execution.context(pid)) + timeout

    with {:ok, config} <- Observation.options(path, receiver, options),
         :owned <- identity(pid),
         do: safe_observe(pid, config, deadline, timeout),
         else: (
           {:error, _} = error -> error
           _ -> failure(:invalid_session)
         )
  end

  def observe(_, _, _, _, _), do: failure(:invalid_observation_options)

  @doc "Cancels the recorded generation without allowing a foreign handle to redirect cleanup."
  @spec unobserve(pid(), Subscription.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def unobserve(pid, handle, timeout) when is_integer(timeout) and timeout in 1..60_000 do
    with :ok <- Subscription.validate(handle, pid) do
      case identity(pid) do
        :closed -> :ok
        :invalid -> failure(:invalid_subscription)
        :owned -> cancel_observation(pid, handle, timeout)
      end
    end
  end

  def unobserve(_, _, _), do: failure(:invalid_subscription)

  @doc false
  @spec observation_exchange(pid(), reference(), Message.t(), term(), pos_integer()) ::
          {:ok, Message.t()} | {:ok, Message.t(), integer()} | {:error, Error.t()}
  def observation_exchange(pid, capability, message, operation, timeout),
    do: submit(pid, message, timeout, {:observation, capability, operation}, [])

  @doc false
  @spec observation_abort(pid(), reference()) :: :ok | {:error, Error.t()}
  def observation_abort(pid, capability) do
    if identity(pid) == :owned,
      do: GenServer.call(pid, {:observation_abort, capability}, 1000),
      else: failure(:invalid_session)
  catch
    :exit, _ -> failure(:connection_closed)
  end

  @doc false
  @spec observation_terminal(pid(), reference(), Error.t()) :: :ok | {:error, Error.t()}
  def observation_terminal(pid, capability, %Error{} = error) do
    if identity(pid) == :owned,
      do: GenServer.call(pid, {:observation_terminal, capability, error}, 1000),
      else: failure(:connection_closed)
  catch
    :exit, _ -> failure(:connection_closed)
  end

  @doc "Closes only a validated local connection owner, with bounded cleanup escalation."
  @spec close(pid()) :: :ok | {:error, Error.t()}
  def close(pid) do
    case identity(pid) do
      :owned -> stop(pid)
      :closed -> :ok
      :invalid -> failure(:invalid_session)
    end
  end

  @doc false
  @spec abort(pid()) :: :ok | {:error, Error.t()}
  def abort(pid) do
    case identity(pid) do
      :owned ->
        monitor = Process.monitor(pid)
        Process.unlink(pid)
        if identity(pid) == :owned, do: Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> :ok
        after
          100 ->
            Process.demonitor(monitor, [:flush])
            failure(:cleanup_timeout)
        end

      :closed ->
        :ok

      :invalid ->
        failure(:invalid_session)
    end
  end

  @doc "Validates explicit configuration without opening a resource or selecting a fallback."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(options) do
    with {:ok, values} <- options(options, %{}), do: configuration(values)
  end

  @impl GenServer
  def init(config) do
    Process.flag(:trap_exit, true)
    :ok = Execution.install(config.execution)

    case initial_execution() do
      {:ok, mid} -> init_owner(config, mid)
      {:error, error} -> {:stop, error}
    end
  end

  defp init_owner(config, mid) do
    generation = make_ref()
    Process.put(:wotex_coap_owner, {__MODULE__, generation})
    owner = self()
    owner_monitor = Process.monitor(config.owner)
    creator_monitor = Process.monitor(config.creator)
    lifetime = Lifetime.start([config.owner, config.creator], 900)
    timer = Execution.schedule({:startup_deadline, generation}, config.timeout)
    worker = spawn_link(fn -> open(config, owner, generation) end)

    {:ok,
     %{
       config: config,
       generation: generation,
       phase: :opening,
       handle: nil,
       adapter_monitor: nil,
       open_worker: worker,
       startup_timer: timer,
       ready_from: nil,
       owner_monitor: owner_monitor,
       creator_monitor: creator_monitor,
       lifetime: lifetime,
       active: nil,
       calls: %{},
       queue: :queue.new(),
       mid: mid,
       history: %{},
       responses: %{},
       response_order: 0,
       observation: nil
     }}
  end

  defp initial_execution do
    case {Execution.now_ms(), Execution.initial_mid()} do
      {now, mid} when is_integer(now) and is_integer(mid) and mid in 0..65_535 -> {:ok, mid}
      _ -> failure(:invalid_execution)
    end
  catch
    _, _ -> failure(:invalid_execution)
  end

  @impl GenServer
  def handle_call(:close, _, state) do
    best_effort_cancel(state)
    result = if state.handle, do: adapter_call(state, :close), else: :ok
    {:stop, :normal, result, %{state | handle: nil}}
  end

  def handle_call(:ready, from, %{phase: :opening} = state),
    do: {:noreply, %{state | ready_from: from}}

  def handle_call(:ready, _, %{phase: :ready} = state) do
    Process.link(state.config.creator)
    {:reply, :ok, state}
  end

  def handle_call(:ready, _, %{phase: {:failed, error}} = state),
    do: {:stop, :normal, {:error, error}, state}

  def handle_call({:observe, config, deadline, timeout}, from, %{phase: :ready} = state) do
    cond do
      state.observation -> {:reply, failure(:observation_active), state}
      not is_nil(state.active) or map_size(state.calls) > 0 -> {:reply, failure(:busy), state}
      remaining(deadline) == 0 -> {:reply, failure(:timeout), state}
      true -> start_observation(state, config, deadline, timeout, from)
    end
  end

  def handle_call({:observation_owner, handle, deadline}, _, state) do
    case state.observation do
      %{handle: ^handle, pid: pid} ->
        {:reply, {:ok, pid}, watch_cancel(state, deadline)}

      _ ->
        {:reply, failure(:invalid_subscription), state}
    end
  end

  def handle_call({:observation_phase, capability, deadline}, _, state) do
    if state.observation && state.observation.capability == capability,
      do: {:reply, :ok, watch_observation(state, deadline)},
      else: {:reply, failure(:invalid_subscription), state}
  end

  def handle_call({:observation_established, capability}, _, state) do
    if state.observation && state.observation.capability == capability,
      do: {:reply, :ok, established_observation(state)},
      else: {:reply, failure(:invalid_subscription), state}
  end

  def handle_call({:observation_terminal, capability, error}, _, state) do
    if state.observation && state.observation.capability == capability,
      do: {:reply, :ok, emit_terminal(state, error)},
      else: {:reply, failure(:invalid_subscription), state}
  end

  def handle_call({:observation_abort, capability}, _, state) do
    if state.observation && state.observation.capability == capability do
      {:reply, :ok,
       if(state.active, do: finish(state, state.active, failure(:canceled)), else: state)}
    else
      {:reply, failure(:invalid_subscription), state}
    end
  end

  def handle_call(
        {:submit, message, kind, options, deadline, receipt},
        from,
        %{phase: :ready} = state
      ) do
    cond do
      not allowed?(state, kind) -> {:reply, failure(:observation_active), state}
      remaining(deadline) == 0 -> {:reply, failure(:timeout), state}
      map_size(state.calls) >= 64 -> {:reply, failure(:busy), state}
      true -> {:noreply, admit(state, from, message, kind, options, deadline, receipt)}
    end
  end

  def handle_call({:submit, _, _, _, _, _}, _, state),
    do: {:reply, failure(:connection_closed), state}

  def handle_call({:exchange, ref, message}, {worker, _} = from, %{active: ref} = state) do
    call = Map.fetch!(state.calls, ref)

    if worker == call.worker and is_nil(call.exchange),
      do: begin_exchange(state, ref, call, message, from),
      else: {:reply, failure(:invalid_exchange), state}
  end

  def handle_call({:exchange, _, _}, _, state), do: {:reply, failure(:connection_closed), state}

  @impl GenServer
  def handle_info({:opened, generation, result}, %{generation: generation, phase: :opening} = state) do
    Execution.cancel(state.startup_timer)
    startup(result, %{state | open_worker: nil})
  end

  def handle_info(
        {:startup_deadline, generation},
        %{generation: generation, phase: :opening} = state
      ) do
    stop_worker(state.open_worker)
    startup(failure(:timeout), %{state | open_worker: nil})
  end

  def handle_info(
        {:wotex_datagram, generation, {:data, host, port, bytes}},
        %{generation: generation, phase: :ready} = state
      ) do
    state =
      if host == state.config.host and port == state.config.port,
        do: incoming(state, bytes),
        else: state

    case adapter_call(state, :set_active_once) do
      :ok -> {:noreply, state}
      {:error, _} -> {:stop, :normal, state}
    end
  end

  def handle_info({:wotex_datagram, generation, _}, %{generation: generation} = state),
    do: {:stop, :normal, state}

  def handle_info({:retry, ref, exchange_ref}, %{active: ref} = state) do
    call = Map.fetch!(state.calls, ref)

    case call.exchange do
      %{reference: ^exchange_ref} = exchange -> retry(state, ref, call, exchange)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:deadline, ref}, %{active: ref} = state) do
    observation = match?({:observation, _, _}, Map.fetch!(state.calls, ref).kind)
    state = finish(state, ref, failure(:timeout))
    if observation, do: {:noreply, state}, else: {:stop, :normal, state}
  end

  def handle_info({:deadline, ref}, state), do: {:noreply, finish(state, ref, failure(:timeout))}

  def handle_info({:completed, ref, result}, %{active: ref} = state) do
    next =
      state
      |> finish(ref, result)
      |> next()

    {:noreply, next}
  end

  def handle_info(
        {:observation_deadline, reference},
        %{observation: %{deadline_ref: reference}} = state
      ) do
    if state.observation.from, do: GenServer.reply(state.observation.from, failure(:timeout))
    {:stop, :normal, emit_terminal(state, Error.new(:timeout))}
  end

  def handle_info({:cancel_deadline, reference}, %{observation: %{cancel_ref: reference}} = state),
    do: {:stop, :normal, emit_terminal(state, Error.new(:timeout))}

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    if monitor in [
         state.owner_monitor,
         state.creator_monitor,
         state.adapter_monitor,
         if(state.observation, do: state.observation.monitor)
       ],
       do: {:stop, :normal, state},
       else: caller_down(state, monitor)
  end

  def handle_info({:EXIT, worker, reason}, %{open_worker: worker, phase: :opening} = state)
      when reason != :normal,
      do: startup(failure(:datagram_failed), %{state | open_worker: nil})

  def handle_info({:EXIT, creator, _}, %{config: %{creator: creator}} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, worker, reason}, %{active: ref} = state)
      when is_reference(ref) and reason != :normal do
    if Map.fetch!(state.calls, ref).worker == worker,
      do: {:stop, :normal, state},
      else: {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:log, _} -> {:log, []}
      {key, _} -> {key, :redacted}
    end)
  end

  @impl GenServer
  def terminate(_, state) do
    stop_worker(state.open_worker)
    Execution.cancel(state.startup_timer)
    if state.active, do: stop_worker(Map.fetch!(state.calls, state.active).worker)
    best_effort_cancel(state)
    emit_terminal(state, Error.new(:connection_closed))

    if state.observation do
      Execution.cancel(state.observation.deadline_timer)
      if state.observation.cancel_timer, do: Execution.cancel(state.observation.cancel_timer)

      if state.observation.from,
        do: GenServer.reply(state.observation.from, failure(:connection_closed))

      Process.exit(state.observation.pid, :kill)
    end

    if state.handle, do: adapter_call(state, :close)
    Enum.each(state.calls, fn {_, call} -> reply(call, failure(:connection_closed)) end)
  end

  defp submit(pid, %Message{} = message, timeout, kind, options)
       when is_integer(timeout) and timeout in 1..60_000 do
    deadline = Execution.now_ms(Execution.context(pid)) + timeout

    with :ok <- validate(message, kind, options) do
      case identity(pid) do
        :owned -> call(pid, message, kind, options, deadline, timeout)
        :closed -> failure(:connection_closed)
        :invalid -> failure(:invalid_session)
      end
    end
  end

  defp submit(_, _, _, _, _), do: failure(:invalid_request)

  defp validate(message, :transfer, options), do: Blockwise.validate(message, options)

  defp validate(message, {:continue, first}, options),
    do: Blockwise.validate_continuation(message, first, options)

  defp validate(message, {:observation, capability, {:continue, first}}, [])
       when is_reference(capability),
       do: Blockwise.validate_continuation(message, first, block_size: 1024)

  defp validate(message, {:observation, capability, operation}, [])
       when is_reference(capability) and operation in [:register, :renew, :cancel],
       do: validate(message, :request, [])

  defp validate(%Message{type: type, code: code} = message, :request, [])
       when type in [:con, :non] and code in 1..4 do
    with :ok <- Codec.validate_options(message), {:ok, _} <- Codec.encode(message), do: :ok
  end

  defp validate(_, _, _), do: failure(:invalid_request)

  defp call(pid, message, kind, options, deadline, timeout) do
    receipt = make_ref()

    try do
      GenServer.call(pid, {:submit, message, kind, options, deadline, receipt}, timeout + 1000)
    catch
      :exit, {:noproc, _} -> failure(:connection_closed)
      :exit, {:normal, _} -> effect(failure(:connection_closed), message, admitted?(receipt))
      :exit, _ -> effect(failure(:connection_closed), message, true)
    after
      admitted?(receipt)
    end
  end

  defp admitted?(receipt) do
    receive do
      {:wotex_coap_admitted, ^receipt} -> true
    after
      0 -> false
    end
  end

  defp await_ready(pid, timeout) do
    case GenServer.call(pid, :ready, timeout + 1000) do
      :ok -> {:ok, pid}
      error -> error
    end
  catch
    :exit, _ ->
      close(pid)
      failure(:connection_failed)
  end

  defp open(config, owner, generation) do
    result =
      try do
        config.adapter.open(
          %{
            host: config.host,
            port: config.port,
            generation: generation,
            options: config.adapter_options
          },
          owner,
          config.timeout
        )
      catch
        _, _ -> failure(:datagram_failed)
      end

    send(owner, {:opened, generation, result})
  end

  defp startup(
         {:ok, %{pid: pid, generation: generation} = handle},
         %{generation: generation} = state
       )
       when is_pid(pid) do
    state = %{state | handle: handle, adapter_monitor: Process.monitor(pid)}

    case adapter_call(state, :set_active_once) do
      :ok ->
        if state.ready_from do
          Process.link(state.config.creator)
          GenServer.reply(state.ready_from, :ok)
        end

        {:noreply, %{state | phase: :ready, ready_from: nil}}

      {:error, error} ->
        startup({:error, error}, state)
    end
  end

  defp startup({:error, %Error{} = error}, state) do
    if state.ready_from,
      do: {:stop, :normal, reply_ready(state, error)},
      else: {:noreply, %{state | phase: {:failed, error}}}
  end

  defp startup(_, state), do: startup(failure(:datagram_failed), state)

  defp reply_ready(state, error) do
    GenServer.reply(state.ready_from, {:error, error})
    %{state | ready_from: nil}
  end

  defp admit(state, from, message, kind, options, deadline, receipt) do
    ref = make_ref()

    call = %{
      from: from,
      message: message,
      kind: kind,
      options: options,
      deadline: deadline,
      monitor: Process.monitor(elem(from, 0)),
      timer: Execution.schedule({:deadline, ref}, remaining(deadline)),
      started: System.monotonic_time(),
      sent: false,
      worker: nil,
      exchange: nil
    }

    send(elem(from, 0), {:wotex_coap_admitted, receipt})
    next(%{state | calls: Map.put(state.calls, ref, call), queue: :queue.in(ref, state.queue)})
  end

  defp next(%{active: nil} = state) do
    case :queue.out(state.queue) do
      {:empty, _} -> state
      {{:value, ref}, queue} -> activate(%{state | queue: queue}, ref)
    end
  end

  defp next(state), do: state

  defp activate(state, ref) do
    call = Map.fetch!(state.calls, ref)

    if remaining(call.deadline) == 0 or not Process.alive?(elem(call.from, 0)) do
      state
      |> finish(ref, failure(:timeout))
      |> next()
    else
      owner = self()
      token = call_token(state, call)

      case token do
        {:ok, token} ->
          call = %{call | message: %{call.message | token: token}}
          worker = spawn_link(fn -> transfer_worker(owner, ref, call) end)
          %{state | active: ref, calls: Map.put(state.calls, ref, %{call | worker: worker})}

        {:error, _} = error ->
          state
          |> finish(ref, error)
          |> next()
      end
    end
  end

  defp transfer_worker(owner, ref, call) do
    :ok = Execution.install(Execution.context(owner))

    exchange = fn wire, state ->
      {GenServer.call(owner, {:exchange, ref, wire}, remaining(call.deadline) + 1000), state}
    end

    result =
      case call.kind do
        :transfer ->
          elem(Blockwise.run(call.message, call.options, nil, exchange), 0)

        {kind, first} when kind == :continue ->
          elem(Blockwise.continue(call.message, first, call.options, nil, exchange), 0)

        {:observation, _, {:continue, first}} ->
          elem(Blockwise.continue(call.message, first, [block_size: 1024], nil, exchange), 0)

        {:observation, _, _} ->
          {result, _} = exchange.(call.message, nil)
          terminal(result)

        :request ->
          {result, _} = exchange.(call.message, nil)
          terminal(result)
      end

    send(owner, {:completed, ref, result})
  end

  defp terminal({:ok, %Message{code: 95}, _}), do: failure(:incomplete_response)
  defp terminal({:ok, %Message{code: 95}}), do: failure(:incomplete_response)
  defp terminal(result), do: result

  defp begin_exchange(state, ref, call, message, from) do
    now = Execution.now_ms()
    history = Map.reject(state.history, fn {_, timestamp} -> now - timestamp >= 247_000 end)
    interval = state.config.ack_timeout || 2000 + :rand.uniform(1001) - 1

    with {:ok, mid} <- next_mid(state.mid),
         message = %{message | message_id: mid},
         false <- Map.has_key?(history, mid),
         {:ok, exchange} <- Exchange.new(message, now, call.deadline, interval) do
      record = %{from: from, value: exchange, reference: make_ref(), timer: nil}
      state = %{state | mid: rem(mid + 1, 65_536), history: Map.put(history, mid, now)}
      call = %{call | sent: true, exchange: arm(record, ref)}
      state = put_call(state, ref, call)
      state = cancellation_started(state, call.kind)

      case transmit(state, exchange.bytes) do
        :ok -> {:noreply, state}
        {:error, error} -> {:noreply, exchange_reply(state, {:error, error})}
      end
    else
      true -> {:reply, failure(:exchange_unavailable), %{state | history: history}}
      error -> {:reply, error, %{state | history: history}}
    end
  end

  defp retry(state, ref, call, record) do
    case Exchange.tick(record.value, Execution.now_ms()) do
      :timeout ->
        {:noreply, exchange_reply(state, failure(:timeout))}

      {:wait, exchange} ->
        {:noreply, put_call(state, ref, %{call | exchange: arm(%{record | value: exchange}, ref)})}

      {:send, bytes, exchange} ->
        state = put_call(state, ref, %{call | exchange: arm(%{record | value: exchange}, ref)})

        case transmit(state, bytes) do
          :ok -> {:noreply, state}
          {:error, error} -> {:noreply, exchange_reply(state, {:error, error})}
        end
    end
  end

  defp arm(record, ref) do
    if record.timer, do: Execution.cancel(record.timer)

    %{
      record
      | timer:
          Execution.schedule(
            {:retry, ref, record.reference},
            remaining(Exchange.wake(record.value))
          )
    }
  end

  defp incoming(state, bytes) do
    with {:ok, reply} <- Codec.decode(bytes), :ok <- Codec.validate_options(reply) do
      state = expire_responses(state)
      key = {reply.message_id, reply.token}

      cond do
        reply.type == :con and Map.has_key?(state.responses, key) ->
          control(state, :ack, reply.message_id)
          state

        observation_report?(state, reply) ->
          notify_observation(state, reply)

        is_nil(state.active) ->
          unknown(state, reply)

        true ->
          correlate(state, reply)
      end
    else
      _ -> state
    end
  end

  defp correlate(state, reply) do
    case Map.fetch!(state.calls, state.active).exchange do
      nil ->
        unknown(state, reply)

      record ->
        case Exchange.incoming(record.value, reply) do
          :ignore ->
            unknown(state, reply)

          :ack ->
            call = Map.fetch!(state.calls, state.active)
            record = %{record | value: %{record.value | acknowledged: true}}
            put_call(state, state.active, %{call | exchange: arm(record, state.active)})

          result ->
            case accept_con(state, reply) do
              {:ok, state} -> exchange_reply(cancellation_confirmed(state, result), result)
              {:error, error} -> exchange_reply(state, {:error, error})
            end
        end
    end
  end

  defp accept_con(state, %Message{type: :con} = reply) do
    with :ok <- control(state, :ack, reply.message_id), do: {:ok, remember(state, reply)}
  end

  defp accept_con(state, _), do: {:ok, state}

  defp remember(state, reply) do
    responses =
      Map.put(
        state.responses,
        {reply.message_id, reply.token},
        {Execution.now_ms(), state.response_order}
      )

    responses =
      if map_size(responses) > 1024,
        do: Map.delete(responses, elem(Enum.min_by(responses, fn {_, {_, order}} -> order end), 0)),
        else: responses

    %{state | responses: responses, response_order: state.response_order + 1}
  end

  defp unknown(state, %Message{type: :con, message_id: mid}) do
    control(state, :rst, mid)
    state
  end

  defp unknown(state, _), do: state

  defp control(state, type, mid) do
    {:ok, bytes} = Codec.encode(%Message{type: type, code: 0, message_id: mid})
    transmit(state, bytes)
  end

  defp transmit(state, bytes), do: adapter_call(state, :send, [bytes])

  defp adapter_call(state, operation, extra \\ []) do
    case apply(state.config.adapter, operation, [state.handle | extra]) do
      :ok -> :ok
      {:error, %Error{}} = error -> error
      _ -> failure(:datagram_failed)
    end
  catch
    _, _ -> failure(:datagram_failed)
  end

  defp expire_responses(state) do
    now = Execution.now_ms()

    %{
      state
      | responses:
          Map.reject(state.responses, fn {_, {timestamp, _}} -> now - timestamp >= 247_000 end)
    }
  end

  defp exchange_reply(state, result) do
    call = Map.fetch!(state.calls, state.active)
    Execution.cancel(call.exchange.timer)
    GenServer.reply(call.exchange.from, received_at(call.kind, result))
    put_call(state, state.active, %{call | exchange: nil})
  end

  defp received_at({:observation, _, operation}, {:ok, message})
       when operation in [:register, :renew],
       do: {:ok, message, Execution.now_ms()}

  defp received_at(_, result), do: result

  defp finish(state, ref, result) do
    case Map.pop(state.calls, ref) do
      {nil, _} ->
        state

      {call, calls} ->
        stop_worker(call.worker)
        reply(call, result)

        %{
          state
          | active: if(state.active == ref, do: nil, else: state.active),
            calls: calls,
            queue: :queue.filter(&(&1 != ref), state.queue)
        }
    end
  end

  defp reply(call, result) do
    Process.demonitor(call.monitor, [:flush])
    Execution.cancel(call.timer)
    if call.exchange, do: Execution.cancel(call.exchange.timer)
    result = effect(result, call.message, call.sent)

    :telemetry.execute(
      [:wotex, :coap, :request, :stop],
      %{duration: System.monotonic_time() - call.started},
      %{code: call.message.code, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
    )

    GenServer.reply(call.from, result)
  end

  defp effect({:error, error}, message, sent),
    do:
      {:error, %{error | effect: if(sent and message.code in [2, 3, 4], do: :unknown, else: :none)}}

  defp effect(result, _, _), do: result

  defp caller_down(state, monitor) do
    case Enum.find(state.calls, fn {_, call} -> call.monitor == monitor end) do
      {ref, _} when ref == state.active -> {:stop, :normal, state}
      {ref, _} -> {:noreply, finish(state, ref, failure(:connection_closed))}
      nil -> {:noreply, state}
    end
  end

  defp put_call(state, ref, call), do: %{state | calls: Map.put(state.calls, ref, call)}
  defp stop_worker(nil), do: :ok
  defp stop_worker(pid), do: Process.exit(pid, :kill)
  defp remaining(deadline), do: max(0, deadline - Execution.now_ms())
  defp failure(code), do: {:error, Error.new(code)}

  defp call_token(state, %{kind: {:observation, _, operation}, message: message})
       when operation in [:register, :renew, :cancel],
       do:
         if(message.token == state.observation.handle_token,
           do: {:ok, message.token},
           else: failure(:invalid_subscription)
         )

  defp call_token(state, call),
    do: unique_token(state.responses, 8, excluded_token(call.kind))

  defp excluded_token({:observation, _, {:continue, first}}), do: first.token
  defp excluded_token({:continue, first}), do: first.token
  defp excluded_token(_), do: nil

  defp next_mid(proposed) do
    case Execution.message_id(proposed) do
      mid when is_integer(mid) and mid in 0..65_535 -> {:ok, mid}
      _ -> failure(:invalid_execution)
    end
  catch
    _, _ -> failure(:invalid_execution)
  end

  defp unique_token(_, 0, _), do: failure(:exchange_unavailable)

  defp unique_token(responses, remaining, excluded) do
    token = Execution.token()

    cond do
      not is_binary(token) or byte_size(token) not in 1..8 ->
        failure(:invalid_execution)

      token == excluded or Enum.any?(responses, fn {{_, previous}, _} -> previous == token end) ->
        unique_token(responses, remaining - 1, excluded)

      true ->
        {:ok, token}
    end
  catch
    _, _ -> failure(:invalid_execution)
  end

  defp allowed?(%{observation: nil}, {:observation, _, _}), do: false
  defp allowed?(%{observation: nil}, _), do: true

  defp allowed?(state, {:observation, capability, _}),
    do: state.observation.capability == capability

  defp allowed?(_, _), do: false

  defp safe_observe(pid, config, deadline, timeout) do
    GenServer.call(pid, {:observe, config, deadline, timeout}, timeout + 1000)
  catch
    :exit, _ -> failure(:connection_closed)
  end

  defp cancel_observation(pid, handle, timeout) do
    execution = Execution.context(pid)
    deadline = Execution.now_ms(execution) + timeout
    cancel_call(pid, handle, deadline, execution, timeout)
  end

  defp cancel_call(pid, handle, deadline, execution, timeout) do
    with {:ok, owner} <- GenServer.call(pid, {:observation_owner, handle, deadline}, timeout) do
      left = min(timeout, max(0, deadline - Execution.now_ms(execution)))

      case GenServer.call(owner, {:cancel, handle, deadline}, left + 1000) do
        :ok -> close(pid)
        error -> error
      end
    end
  catch
    :exit, _ ->
      close(pid)

      if Execution.now_ms(execution) >= deadline,
        do: failure(:timeout),
        else: failure(:connection_closed)
  end

  defp start_observation(state, config, deadline, timeout, from) do
    with {:ok, request} <-
           Observation.wire_request(config.request, state.config.observation_options),
         {:ok, token} <- unique_token(state.responses, 8, nil),
         {:ok, handle} <- Subscription.new(self(), make_ref(), state.generation) do
      capability = make_ref()
      request = %{request | token: token}

      config =
        Map.merge(config, %{
          request: request,
          handle: handle,
          capability: capability,
          from: from,
          deadline: deadline,
          timeout: timeout,
          execution: state.config.execution,
          kind: state.config.observation_kind
        })

      {:ok, owner} = Observation.start(config)

      deadline_ref = make_ref()

      deadline_timer =
        Execution.schedule({:observation_deadline, deadline_ref}, remaining(deadline))

      observation = %{
        pid: owner,
        deadline_ref: deadline_ref,
        deadline_timer: deadline_timer,
        cancel_ref: nil,
        cancel_timer: nil,
        monitor: Process.monitor(owner),
        handle: handle,
        capability: capability,
        handle_token: token,
        request: request,
        receiver: config.receiver,
        terminal: false,
        from: from,
        cancellation_started: false,
        cancellation_confirmed: false
      }

      {:noreply, %{state | observation: observation}}
    else
      error -> {:reply, error, state}
    end
  end

  defp established_observation(state) do
    Execution.cancel(state.observation.deadline_timer)
    %{state | observation: %{state.observation | from: nil, deadline_ref: nil}}
  end

  defp watch_cancel(%{observation: %{cancel_timer: timer}} = state, _) when is_reference(timer),
    do: state

  defp watch_cancel(state, deadline) do
    Execution.cancel(state.observation.deadline_timer)
    reference = make_ref()
    timer = Execution.schedule({:cancel_deadline, reference}, remaining(deadline))

    %{
      state
      | observation: %{
          state.observation
          | deadline_ref: nil,
            cancel_ref: reference,
            cancel_timer: timer
        }
    }
  end

  defp watch_observation(state, deadline) do
    Execution.cancel(state.observation.deadline_timer)
    reference = make_ref()
    timer = Execution.schedule({:observation_deadline, reference}, remaining(deadline))
    %{state | observation: %{state.observation | deadline_ref: reference, deadline_timer: timer}}
  end

  defp observation_report?(%{observation: nil}, _), do: false

  defp observation_report?(state, reply) do
    observation = state.observation
    matching = reply.token == observation.handle_token and reply.type in [:con, :non]

    if state.active do
      call = Map.fetch!(state.calls, state.active)
      exchange = call.exchange

      cancellation_notification?(call, reply, observation.handle_token) or
        (matching and (is_nil(exchange) or exchange.value.request.token != reply.token))
    else
      matching
    end
  end

  defp cancellation_notification?(%{kind: {:observation, _, :cancel}}, reply, token),
    do: reply.token == token and reply.type in [:con, :non, :ack] and Codec.option(reply, 6) != []

  defp cancellation_notification?(_, _, _), do: false

  defp notify_observation(state, reply) do
    case accept_con(state, reply) do
      {:ok, state} ->
        send(
          state.observation.pid,
          {:report, state.generation, reply, Execution.now_ms()}
        )

        state

      {:error, error} ->
        send(state.observation.pid, {:transport_failed, state.generation, error})
        state
    end
  end

  defp cancellation_started(state, {:observation, _, :cancel}),
    do: %{state | observation: %{state.observation | cancellation_started: true}}

  defp cancellation_started(state, _), do: state

  defp cancellation_confirmed(state, {:ok, reply}) do
    call = Map.fetch!(state.calls, state.active)

    if match?({:observation, _, :cancel}, call.kind) and reply.code in 64..94 and
         Codec.option(reply, 6) == [],
       do: confirmed_cancel(state),
       else: state
  end

  defp cancellation_confirmed(state, _), do: state

  defp confirmed_cancel(state) do
    if state.observation.cancel_timer, do: Execution.cancel(state.observation.cancel_timer)
    %{state | observation: %{state.observation | cancellation_confirmed: true, cancel_ref: nil}}
  end

  defp emit_terminal(%{observation: nil} = state, _), do: state

  defp emit_terminal(state, error) do
    observation = state.observation

    if not observation.terminal and not observation.cancellation_confirmed and
         Process.alive?(observation.receiver),
       do: send(observation.receiver, {:wotex_coap, observation.handle.reference, {:error, error}})

    %{state | observation: %{observation | terminal: true, from: nil}}
  end

  defp best_effort_cancel(%{observation: nil}), do: :ok
  defp best_effort_cancel(%{handle: nil}), do: :ok

  defp best_effort_cancel(state) do
    observation = state.observation
    now = Execution.now_ms()

    with false <- observation.cancellation_started,
         {:ok, mid} <- next_mid(state.mid),
         timestamp = Map.get(state.history, mid, now - 247_000),
         true <- now - timestamp >= 247_000 do
      request = %{
        observation.request
        | message_id: mid,
          options: [{6, <<1>>} | observation.request.options]
      }

      with {:ok, bytes} <- Codec.encode(request), do: transmit(state, bytes)
    end
  end

  defp identity(pid) when is_pid(pid) and node(pid) == node() and pid != self() do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_owner}) do
      :undefined ->
        :closed

      {{:dictionary, :wotex_coap_owner}, {__MODULE__, generation}} when is_reference(generation) ->
        :owned

      _ ->
        :invalid
    end
  end

  defp identity(_), do: :invalid

  defp stop(pid) do
    GenServer.call(pid, :close, 900)
  catch
    :exit, {reason, _} when reason in [:normal, :noproc] ->
      :ok

    :exit, {{:normal, {:sys, :terminate, _}}, _} ->
      :ok

    :exit, _ ->
      abort(pid)
      failure(:cleanup_timeout)
  end

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values) when key in @keys and not is_map_key(values, key),
    do: options(rest, Map.put(values, key, value))

  defp options(_, _), do: failure(:invalid_options)

  defp configuration(values) do
    with {:ok, host} <- address(Map.get(values, :host)),
         {datagram, config} = configuration_values(values, host),
         :ok <- valid_security_config?(values),
         :ok <- valid_port_config?(config.port),
         :ok <- valid_timeout_config?(config.timeout),
         :ok <- valid_ack_config?(config.ack_timeout),
         :ok <- valid_owner_config?(config.owner),
         :ok <- valid_execution_config?(config.execution, config.observation_kind, datagram),
         {:ok, observation_options} <-
           Observation.wire_options(Map.get(values, :observation_options, [])) do
      adapter_config(datagram, Map.put(config, :observation_options, observation_options))
    end
  end

  defp configuration_values(values, host) do
    datagram = Map.get(values, :datagram, {UDP, []})

    {datagram,
     %{
       host: host,
       port: Map.get(values, :port, 5683),
       timeout: Map.get(values, :timeout, 5000),
       ack_timeout: Map.get(values, :ack_timeout),
       owner: Map.get(values, :owner, self()),
       execution: Map.get(values, :execution, :system),
       observation_kind: Map.get(values, :observation_kind, :property)
     }}
  end

  defp valid_security_config?(values) do
    if Map.get(values, :scheme, :coap) == :coap and Map.get(values, :dtls_mode, :none) == :none,
      do: :ok,
      else: failure(:unsupported_security)
  end

  defp valid_port_config?(port) when is_integer(port) and port in 1..65_535, do: :ok
  defp valid_port_config?(_), do: failure(:invalid_port)

  defp valid_timeout_config?(timeout) when is_integer(timeout) and timeout in 1..60_000, do: :ok
  defp valid_timeout_config?(_), do: failure(:invalid_timeout)

  defp valid_ack_config?(ack) do
    if valid_ack?(ack), do: :ok, else: failure(:invalid_ack_timeout)
  end

  defp valid_owner_config?(owner) when is_pid(owner) and node(owner) == node(), do: :ok
  defp valid_owner_config?(_), do: failure(:invalid_owner)

  defp valid_execution_config?(execution, observation_kind, datagram) do
    valid? =
      valid_execution?(execution) and observation_kind in [:property, :event] and
        (execution == :system or not match?({UDP, _}, datagram))

    if valid?, do: :ok, else: failure(:invalid_execution)
  end

  defp valid_execution?(:system), do: true

  defp valid_execution?({module, _}) when is_atom(module) and module not in [nil, false, true],
    do: true

  defp valid_execution?(_), do: false

  defp valid_ack?(nil), do: true
  defp valid_ack?(value), do: is_integer(value) and value in 1..3000

  defp adapter_config({UDP, []}, config),
    do: {:ok, Map.merge(config, %{adapter: UDP, adapter_options: []})}

  defp adapter_config({UDP, _}, _), do: failure(:invalid_datagram_config)

  defp adapter_config({module, options}, config)
       when is_atom(module) and module not in [nil, false, true],
       do: {:ok, Map.merge(config, %{adapter: module, adapter_options: options})}

  defp adapter_config(_, _), do: failure(:invalid_datagram_config)

  defp address(host) when is_binary(host) and byte_size(host) <= 64 do
    with true <- String.valid?(host),
         {:ok, ip} <- :inet.parse_address(String.to_charlist(host)),
         do: address(ip),
         else: (_ -> failure(:invalid_host))
  end

  defp address(host) when is_tuple(host) do
    maximum = if tuple_size(host) == 4, do: 255, else: 65_535

    if tuple_size(host) in [4, 8] and
         Enum.all?(Tuple.to_list(host), &(is_integer(&1) and &1 in 0..maximum)),
       do: {:ok, host},
       else: failure(:invalid_host)
  end

  defp address(_), do: failure(:invalid_host)
end
