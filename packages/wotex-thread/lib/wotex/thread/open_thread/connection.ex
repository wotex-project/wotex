defmodule Wotex.Thread.OpenThread.Connection do
  @moduledoc """
  Owns one explicitly started OpenThread bridge process and its request queue.

  The GenServer monitors the supplied owner, validates the native ready frame,
  sends one `flow_open` frame with a fresh random 128-bit session generation
  before `open`, and returns an opaque handle for one acquired generation. The
  generation is an identity token, never a credential. Calls
  have finite admission deadlines and correlated replies. Ordinary work uses
  at most 63 pending slots, reserving the 64th for a stop operation that can
  precede queued work and cancel an outstanding commissioning operation.

  An owner or submitted caller dying, a submitted deadline expiring, or a broken
  native channel closes the generation instead of replaying uncertain work.
  Submitted mutations report an unknown effect when completion is lost; queued
  work has not been sent. Closing waits for bounded native teardown, and the
  host retains responsibility for its SDK, interface, settings and radio children.
  Status inspection redacts configuration and pending request contents.

  Consumers configure `Wotex.Thread.OpenThread` or its child specification.
  This connection is a per-session implementation component, with no global
  registry, automatic reconnection or dependency-load startup.
  """

  use GenServer
  alias Wotex.Thread.{Error, Session, Subscription}
  alias Wotex.Thread.OpenThread.{Config, Frame, ReportLedger, Request, StreamOwner}

  @owner_key {__MODULE__, :owner}
  @closed_limit 1024

  @derive {Inspect, only: [:pid, :generation]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct @enforce_keys
  @opaque t :: %__MODULE__{pid: pid(), reference: reference(), generation: 1}

  @doc false
  @spec start(term(), :link | :unlinked) :: {:ok, pid()} | {:error, Error.t()}
  def start(options, link) do
    entered = now()

    with {:ok, config} <- Config.new(options) do
      args = {config, entered + config.timeout, self()}

      result =
        case link do
          :link -> GenServer.start_link(__MODULE__, args)
          :unlinked -> GenServer.start(__MODULE__, args)
        end

      case result do
        {:ok, pid} -> {:ok, pid}
        {:error, %Error{}} = error -> error
        _ -> {:error, Error.new(:transport_unavailable)}
      end
    end
  end

  @doc false
  @spec session(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  def session(pid) when is_pid(pid) and node(pid) == node(), do: call(pid, :session, 61_000)
  def session(_), do: {:error, Error.new(:invalid_handle)}

  @doc false
  @spec request(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def request(handle, message, timeout) do
    entered = now()

    with :ok <- validate(handle),
         true <- is_integer(timeout) and timeout in 1..60_000,
         {:ok, _} <- Request.encode(message) do
      receipt = make_ref()

      call(
        handle.pid,
        {handle.reference, :request, message, entered + timeout, receipt},
        timeout + 1000
      )
    else
      false -> {:error, Error.new(:invalid_options)}
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec subscribe(term(), term(), term(), term()) :: {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(handle, receiver, queue_limit, timeout) do
    entered = now()

    with :ok <- validate(handle),
         true <-
           is_pid(receiver) and node(receiver) == node() and is_integer(queue_limit) and
             queue_limit in 1..10_000 and is_integer(timeout) and timeout in 1..60_000 do
      call(
        handle.pid,
        {handle.reference, :subscribe, receiver, queue_limit, entered + timeout},
        timeout + 1000
      )
    else
      false -> {:error, Error.new(:invalid_subscription)}
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec unsubscribe(term(), term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(handle, subscription, timeout) do
    entered = now()

    with :ok <- validate(handle),
         :ok <- Subscription.validate(subscription),
         true <- subscription.pid == handle.pid and is_integer(timeout) and timeout in 1..60_000 do
      message =
        {handle.reference, :unsubscribe, subscription.reference, subscription.generation,
         entered + timeout}

      # A terminated owner generation has no live stream left to cancel.
      case call(handle.pid, message, timeout + 1000) do
        {:error, %Error{code: :connection_closed}} -> :ok
        result -> result
      end
    else
      false -> {:error, Error.new(:invalid_subscription)}
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec disconnect(term()) :: :ok | {:error, Error.t()}
  def disconnect(handle) do
    with :ok <- validate(handle) do
      case call(handle.pid, {handle.reference, :close}, 1100) do
        {:error, %Error{code: :connection_closed}} -> :ok
        result -> result
      end
    end
  end

  @impl GenServer
  def init({config, deadline, starter}) do
    Process.flag(:trap_exit, true)

    cond do
      now() >= deadline ->
        {:stop, Error.new(:timeout)}

      not Process.alive?(config.owner) or not Process.alive?(starter) ->
        {:stop, Error.new(:owner_down)}

      true ->
        init_owner(config, deadline, starter)
    end
  end

  defp init_owner(config, deadline, starter) do
    reference = make_ref()
    Process.put(@owner_key, reference)

    state = %{
      config: config,
      deadline: deadline,
      owner_ref: Process.monitor(config.owner),
      starter_ref: Process.monitor(starter),
      handle: %__MODULE__{pid: self(), reference: reference, generation: 1},
      status: :starting,
      port: nil,
      buffer: <<>>,
      waiters: %{},
      pending: %{},
      queue: :queue.new(),
      active: nil,
      control: nil,
      controls: :queue.new(),
      counter: 0,
      close_waiters: [],
      close_ack: false,
      failure: nil,
      session_generation: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      line_bytes: 0,
      ledger: ReportLedger.new(),
      subscriptions: %{},
      streams: %{},
      reports: %{},
      monitors: %{},
      closed: MapSet.new(),
      closed_order: :queue.new(),
      start_timer: Process.send_after(self(), :startup_timeout, max(deadline - now(), 0))
    }

    case open_port(config.executable) do
      {:ok, port} -> {:ok, %{state | port: port}}
      :error -> {:stop, Error.new(:transport_unavailable)}
    end
  end

  @impl GenServer
  def handle_call(:session, _, %{status: :ready} = state) do
    {:reply, {:ok, session_value(state)}, state}
  end

  def handle_call(:session, from, %{status: status} = state) when status in [:starting, :opening] do
    if map_size(state.waiters) < 64 do
      reference = Process.monitor(elem(from, 0))
      {:noreply, %{state | waiters: Map.put(state.waiters, reference, from)}}
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call({reference, :close}, from, %{handle: %{reference: reference}} = state) do
    if length(state.close_waiters) < 64 do
      state = %{state | close_waiters: [from | state.close_waiters]}
      {:noreply, close(state, nil)}
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call(
        {reference, :request, message, deadline, receipt},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      )
      when is_reference(receipt) do
    case Request.encode(message) do
      {:ok, {operation, parameters}} ->
        cond do
          not is_integer(deadline) or deadline <= now() ->
            {:reply, {:error, Error.new(:timeout)}, state}

          map_size(state.pending) >= admission_limit(operation) ->
            {:reply, {:error, Error.new(:busy)}, state}

          true ->
            {:noreply, admit(state, from, operation, parameters, deadline, receipt)}
        end

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {reference, :subscribe, receiver, queue_limit, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      ) do
    cond do
      deadline <= now() ->
        {:reply, {:error, Error.new(:timeout)}, state}

      map_size(state.pending) >= admission_limit("subscribe_state") ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        extra = %{subscriber: {receiver, queue_limit}}
        parameters = %{queue_limit: queue_limit}
        {:noreply, admit(state, from, "subscribe_state", parameters, deadline, make_ref(), extra)}
    end
  end

  def handle_call(
        {reference, :unsubscribe, subscription, generation, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      ) do
    case Map.fetch(state.subscriptions, subscription) do
      {:ok, %{generation: ^generation, status: :active}} ->
        if deadline > now(),
          do: {:noreply, cancel(state, subscription, from, deadline)},
          else: {:reply, {:error, Error.new(:timeout)}, state}

      {:ok, %{generation: ^generation, status: :closing, waiters: waiters}}
      when length(waiters) < 64 ->
        {:noreply, put_in(state.subscriptions[subscription].waiters, [from | waiters])}

      {:ok, %{generation: ^generation}} ->
        {:reply, {:error, Error.new(:busy)}, state}

      _ ->
        if MapSet.member?(state.closed, {subscription, generation}),
          do: {:reply, :ok, state},
          else: {:reply, {:error, Error.new(:invalid_subscription)}, state}
    end
  end

  def handle_call(_, _, %{status: :closing} = state),
    do: {:reply, {:error, Error.new(:connection_closed)}, state}

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_handle)}, state}

  @impl GenServer
  def handle_info({port, {:data, {:eol, bytes}}}, %{port: port} = state) do
    if byte_size(state.buffer) + byte_size(bytes) < 131_072 do
      case Frame.decode(state.buffer <> bytes) do
        {:ok, frame} ->
          line_bytes = byte_size(state.buffer) + byte_size(bytes) + 1
          {:noreply, frame(frame, %{state | buffer: <<>>, line_bytes: line_bytes})}

        :error ->
          {:noreply, close(state, Error.new(:invalid_response))}
      end
    else
      {:noreply, close(state, Error.new(:response_limit))}
    end
  end

  def handle_info({port, {:data, {:noeol, bytes}}}, %{port: port} = state) do
    if byte_size(state.buffer) + byte_size(bytes) < 131_072,
      do: {:noreply, %{state | buffer: state.buffer <> bytes}},
      else: {:noreply, close(state, Error.new(:response_limit))}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    failure =
      cond do
        state.failure ->
          state.failure

        state.buffer != <<>> ->
          Error.new(:invalid_response)

        state.status != :closing or not state.close_ack or code != 0 ->
          Error.new(:connection_closed)

        true ->
          nil
      end

    {:stop, :normal, reply_all(%{state | failure: failure, port: nil})}
  end

  def handle_info(:startup_timeout, %{status: status} = state) when status in [:starting, :opening],
    do: {:noreply, close(state, Error.new(:timeout))}

  def handle_info({:deadline, id}, state) do
    cond do
      id in [state.active, state.control] ->
        {:noreply, close(state, Error.new(:timeout))}

      # An internal stream cancellation that cannot be sent leaves no owner to retry it.
      is_map_key(state.pending, id) and is_nil(state.pending[id].from) ->
        {:noreply, close(state, Error.new(:timeout))}

      Map.has_key?(state.pending, id) ->
        {:noreply, complete(state, id, {:error, Error.new(:timeout)})}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, reference, :process, _, _}, state) do
    cond do
      reference in [state.owner_ref, state.starter_ref] ->
        {:noreply, close(state, Error.new(:owner_down))}

      Map.has_key?(state.waiters, reference) ->
        {:noreply, %{state | waiters: Map.delete(state.waiters, reference)}}

      Map.has_key?(state.monitors, reference) ->
        {:noreply, stream_process_down(state, reference)}

      true ->
        {:noreply, caller_down(state, reference)}
    end
  end

  def handle_info(
        {:wotex_thread_report_admitted, owner, subscription, sequence, token, admission},
        %{status: :ready} = state
      ) do
    with {:ok, %{owner: ^owner, status: :active} = record} <-
           Map.fetch(state.subscriptions, subscription),
         {:ok, {^subscription, ^token, value, flags}} <- Map.fetch(state.reports, sequence) do
      receiver_capacity =
        case Process.info(record.receiver, :message_queue_len) do
          {:message_queue_len, length} -> length < record.queue_limit
          nil -> false
        end

      if admission == :ok and receiver_capacity do
        send(record.receiver, {:wotex_thread, subscription, {:ok, value, %{changed_flags: flags}}})
        emit_subscription(:deliver, :ok)
        {:noreply, consume_report(state, subscription, sequence, token)}
      else
        state =
          state
          |> terminal(subscription, Error.new(:receiver_overflow))
          |> consume_report(subscription, sequence, token)

        {:noreply, cancel(state, subscription, nil, now() + 1000)}
      end
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info(:terminate_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-TERM")
    {:noreply, state}
  end

  def handle_info(:kill_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-KILL")
    Process.send_after(self(), :cleanup_deadline, 100)
    {:noreply, %{state | failure: Error.new(:cleanup_timeout)}}
  end

  def handle_info(:cleanup_deadline, %{status: :closing} = state),
    do: {:stop, :normal, reply_all(%{state | failure: Error.new(:cleanup_timeout)})}

  def handle_info({:EXIT, port, :normal}, %{port: port} = state), do: {:noreply, state}

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: {:noreply, close(state, Error.new(:connection_closed))}

  def handle_info({:EXIT, pid, _}, state) when is_pid(pid),
    do: {:noreply, close(state, Error.new(:owner_down))}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    if state.port && Port.info(state.port), do: Port.close(state.port)
    :ok
  end

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} ->
        {:state,
         %{
           status: state.status,
           pending: map_size(state.pending),
           subscriptions: map_size(state.subscriptions)
         }}

      {:message, _} ->
        {:message, :redacted}

      {:reason, _} ->
        {:reason, :redacted}

      {:log, _} ->
        {:log, []}

      entry ->
        entry
    end)
  end

  defp validate(%__MODULE__{pid: pid, reference: reference, generation: 1} = handle)
       when map_size(handle) == 4 and is_pid(pid) and node(pid) == node() and
              is_reference(reference),
       do: :ok

  defp validate(_), do: {:error, Error.new(:invalid_handle)}

  defp frame(message, %{status: :starting} = state) do
    if Frame.ready?(message) and now() < state.deadline do
      parameters = %{
        radio_url: state.config.radio_url,
        interface: state.config.interface,
        storage_path: state.config.storage_path,
        storage_mode: Atom.to_string(state.config.storage_mode),
        allow_network_creation: state.config.allow_network_creation
      }

      # Flow initialization precedes open; its generation identifies this IPC session only.
      if send_line(state.port, %{
           version: 1,
           event: "flow_open",
           session_generation: state.session_generation
         }) and send_frame(state.port, "open", "open", parameters, state.deadline),
         do: %{state | status: :opening},
         else: close(state, Error.new(:connection_closed))
    else
      close(state, Error.new(:invalid_response))
    end
  end

  defp frame(message, %{status: :opening} = state) do
    case timed_response(message, "open", "open", state.deadline) do
      {:ok, _} ->
        Process.cancel_timer(state.start_timer)
        Process.demonitor(state.starter_ref, [:flush])

        Enum.each(state.waiters, fn {monitor, from} ->
          Process.demonitor(monitor, [:flush])
          GenServer.reply(from, {:ok, session_value(state)})
        end)

        %{state | status: :ready, waiters: %{}, starter_ref: nil}

      {:error, error} ->
        close(state, error)

      :invalid ->
        close(state, Error.new(:invalid_response))
    end
  end

  defp frame(%{"id" => id} = message, %{status: :ready} = state)
       when is_binary(id) and (id == state.active or id == state.control) do
    pending = state.pending[id]
    operation = pending.operation

    case timed_response(message, id, operation, pending.deadline) do
      :invalid ->
        close(state, Error.new(:invalid_response))

      {:error, %Error{code: code} = error}
      when code in [:timeout, :connection_closed, :invalid_response] ->
        close(state, error)

      {:ok, %{subscription_id: ^id, generation: generation}} when operation == "subscribe_state" ->
        if Map.has_key?(state.streams, {id, generation}),
          do: close(state, Error.new(:invalid_response)),
          else: advance(open_subscription(state, id, generation, pending))

      {:ok, _} when operation == "subscribe_state" ->
        close(state, Error.new(:invalid_response))

      {:ok, nil} when operation == "unsubscribe" ->
        unsubscribed(state, id)

      {:error, %Error{code: :subscription_not_found}} when operation == "unsubscribe" ->
        unsubscribed(state, id)

      {:ok, value} = result ->
        if Request.matches_result?(pending.operation, pending.parameters, value),
          do: advance(complete(state, id, result)),
          else: close(state, Error.new(:invalid_response))

      {:error, _} = result ->
        advance(complete(state, id, result))
    end
  end

  defp frame(%{"event" => _} = message, %{status: :ready} = state),
    do: stream_frame(Frame.stream(message), state)

  # A closing generation discards stream traffic; its receivers get one terminal error.
  defp frame(%{"event" => _}, %{status: :closing} = state), do: state

  defp frame(message, %{status: :closing, close_ack: false} = state) do
    case Frame.response(message, "close", "close") do
      {:ok, nil} -> %{state | close_ack: true}
      _ -> %{state | failure: state.failure || Error.new(:invalid_response)}
    end
  end

  defp frame(_, state), do: close(state, Error.new(:invalid_response))

  defp timed_response(message, id, operation, deadline) do
    if now() < deadline,
      do: Frame.response(message, id, operation),
      else: {:error, Error.new(:timeout)}
  end

  defp admission_limit(operation) when operation in ["commissioner_stop", "joiner_stop"], do: 64
  # At most one cancellation per live stream (64) is outstanding beyond ordinary work.
  defp admission_limit("unsubscribe"), do: 128
  defp admission_limit(_), do: 63

  defp admit(state, from, operation, parameters, deadline, receipt, extra \\ %{}) do
    id = Integer.to_string(state.counter + 1)

    pending =
      Map.merge(
        %{
          from: from,
          receipt: receipt,
          operation: operation,
          parameters: parameters,
          deadline: deadline,
          monitor: if(from, do: Process.monitor(elem(from, 0))),
          timer: Process.send_after(self(), {:deadline, id}, max(deadline - now(), 0))
        },
        extra
      )

    queue =
      if operation in ["commissioner_stop", "joiner_stop", "unsubscribe"],
        do: :controls,
        else: :queue

    state
    |> Map.put(:counter, state.counter + 1)
    |> Map.put(:pending, Map.put(state.pending, id, pending))
    |> Map.put(queue, :queue.in(id, Map.fetch!(state, queue)))
    |> advance()
  end

  defp advance(%{control: nil, status: :ready} = state) do
    cond do
      not :queue.is_empty(state.controls) -> advance_queue(state, :controls, :control)
      state.active == nil -> advance_queue(state, :queue, :active)
      true -> state
    end
  end

  defp advance(state), do: state

  defp advance_queue(state, queue_key, slot) do
    case :queue.out(Map.fetch!(state, queue_key)) do
      {{:value, id}, queue} ->
        state = Map.put(state, queue_key, queue)
        pending = Map.fetch!(state.pending, id)

        cond do
          pending.from && not Process.alive?(elem(pending.from, 0)) ->
            advance(complete(state, id, {:error, Error.new(:owner_down)}))

          is_nil(pending.from) and pending.deadline <= now() ->
            close(state, Error.new(:timeout))

          pending.deadline <= now() ->
            advance(complete(state, id, {:error, Error.new(:timeout)}))

          submit(state.port, id, pending) ->
            Map.put(state, slot, id)

          true ->
            close(state, Error.new(:connection_closed))
        end

      {:empty, _} ->
        state
    end
  end

  defp submit(port, id, pending) do
    if Request.mutation?(pending.operation),
      do: send(elem(pending.from, 0), {:wotex_thread_submitted, pending.receipt})

    send_frame(port, id, pending.operation, pending.parameters, pending.deadline)
  end

  defp complete(state, id, result) do
    {pending, rest} = Map.pop(state.pending, id)
    Process.cancel_timer(pending.timer)
    if pending.monitor, do: Process.demonitor(pending.monitor, [:flush])

    result =
      if id in [state.active, state.control],
        do: mutation_result(result, pending.operation),
        else: result

    if pending.from, do: GenServer.reply(pending.from, result)

    %{
      state
      | pending: rest,
        queue: :queue.filter(&(&1 != id), state.queue),
        controls: :queue.filter(&(&1 != id), state.controls),
        control: if(state.control == id, do: nil, else: state.control),
        active: if(state.active == id, do: nil, else: state.active)
    }
  end

  defp caller_down(state, monitor) do
    case Enum.find(state.pending, fn {_, request} -> request.monitor == monitor end) do
      {id, _} when id == state.active or id == state.control -> close(state, Error.new(:owner_down))
      {id, _} -> complete(state, id, {:error, Error.new(:owner_down)})
      nil -> state
    end
  end

  # The host registered the listener and follows this reply with the initial report.
  defp open_subscription(state, id, generation, pending) do
    {receiver, queue_limit} = pending.subscriber
    reference = make_ref()

    with {:ok, ledger} <- ReportLedger.open(state.ledger, {id, generation}, queue_limit),
         {:ok, owner} <- StreamOwner.start(self(), reference, receiver, queue_limit) do
      receiver_monitor = Process.monitor(receiver)
      owner_monitor = Process.monitor(owner)

      record = %{
        id: id,
        generation: generation,
        receiver: receiver,
        owner: owner,
        queue_limit: queue_limit,
        status: :active,
        waiters: [],
        receiver_monitor: receiver_monitor,
        owner_monitor: owner_monitor
      }

      handle = %Subscription{pid: self(), reference: reference, generation: generation}
      emit_subscription(:open, :ok)

      %{
        state
        | ledger: ledger,
          subscriptions: Map.put(state.subscriptions, reference, record),
          streams: Map.put(state.streams, {id, generation}, reference),
          monitors:
            state.monitors
            |> Map.put(receiver_monitor, {:receiver, reference})
            |> Map.put(owner_monitor, {:owner, reference})
      }
      |> complete(id, {:ok, handle})
    else
      _ -> close(state, Error.new(:invalid_response))
    end
  end

  # Marks a stream closing and submits its cancellation. A nil caller is internal.
  defp cancel(state, reference, from, deadline) do
    record = Map.fetch!(state.subscriptions, reference)
    parameters = %{subscription_id: record.id, generation: record.generation}
    state = put_in(state.subscriptions[reference].status, :closing)
    admit(state, from, "unsubscribe", parameters, deadline, make_ref())
  end

  # Cancellation completes only after its barrier removed the stream.
  defp unsubscribed(state, id) do
    %{parameters: %{subscription_id: stream_id, generation: generation}} = state.pending[id]

    if Map.has_key?(state.streams, {stream_id, generation}),
      do: close(state, Error.new(:invalid_response)),
      else: advance(complete(state, id, :ok))
  end

  defp stream_frame({:report, session, id, generation, sequence, value, flags}, state) do
    token = make_ref()

    with true <- session == state.session_generation,
         {:ok, reference} <- Map.fetch(state.streams, {id, generation}),
         {:ok, ledger} <-
           ReportLedger.register(state.ledger, {id, generation}, sequence, state.line_bytes, token) do
      state = %{state | ledger: ledger}
      record = state.subscriptions[reference]

      case record.status do
        :active ->
          send(record.owner, {:wotex_thread_report, self(), reference, sequence, token})
          %{state | reports: Map.put(state.reports, sequence, {reference, token, value, flags})}

        :closing ->
          state
          |> Map.put(:reports, Map.put(state.reports, sequence, {reference, token, value, flags}))
          |> consume_report(reference, sequence, token)
      end
    else
      _ -> close(state, Error.new(:invalid_response))
    end
  end

  defp stream_frame({:stream_error, session, id, generation, code}, state) do
    with true <- session == state.session_generation,
         {:ok, reference} <- Map.fetch(state.streams, {id, generation}) do
      # Reports the host sent before its error keep their order ahead of the terminal
      # delivery; the host then retires the stream and a cancellation joins that barrier.
      state = state |> drain_reports(reference) |> terminal(reference, Error.new(code))
      put_in(state.subscriptions[reference].status, :closing)
    else
      _ -> close(state, Error.new(:invalid_response))
    end
  end

  defp stream_frame({:retired, session, id, generation, last}, state) do
    with true <- session == state.session_generation,
         {:ok, reference} <- Map.fetch(state.streams, {id, generation}),
         %{status: :closing} = record <- state.subscriptions[reference],
         {:ok, ledger} <- ReportLedger.retire(state.ledger, {id, generation}, last) do
      reports = Map.reject(state.reports, fn {_, {owner, _, _, _}} -> owner == reference end)
      Enum.each(record.waiters, &GenServer.reply(&1, :ok))
      stop_owner(record)
      emit_subscription(:close, :ok)

      %{
        state
        | ledger: ledger,
          reports: reports,
          subscriptions: Map.delete(state.subscriptions, reference),
          streams: Map.delete(state.streams, {id, generation}),
          monitors: Map.drop(state.monitors, [record.receiver_monitor, record.owner_monitor])
      }
      |> remember_closed(reference, generation)
      |> acknowledge()
    else
      _ -> close(state, Error.new(:invalid_response))
    end
  end

  defp stream_frame(:invalid, state), do: close(state, Error.new(:invalid_response))

  defp stream_process_down(state, monitor) do
    {role, reference} = Map.fetch!(state.monitors, monitor)
    state = %{state | monitors: Map.delete(state.monitors, monitor)}

    case state.subscriptions[reference] do
      %{status: :active} ->
        state =
          if role == :owner, do: terminal(state, reference, Error.new(:owner_down)), else: state

        cancel(state, reference, nil, now() + 1000)

      _ ->
        state
    end
  end

  # Delivers a terminating stream's validated reports in sequence order without owner
  # admission; receiver capacity still bounds delivery and later reports are consumed.
  defp drain_reports(state, reference) do
    state.reports
    |> Enum.filter(fn {_, {owner, _, _, _}} -> owner == reference end)
    |> Enum.sort()
    |> Enum.reduce(state, fn {sequence, {_, token, value, flags}}, current ->
      record = current.subscriptions[reference]

      case {record.status, Process.info(record.receiver, :message_queue_len)} do
        {:active, {:message_queue_len, length}} when length < record.queue_limit ->
          send(record.receiver, {:wotex_thread, reference, {:ok, value, %{changed_flags: flags}}})
          emit_subscription(:deliver, :ok)
          consume_report(current, reference, sequence, token)

        {:active, _} ->
          current
          |> terminal(reference, Error.new(:receiver_overflow))
          |> put_in([:subscriptions, reference, :status], :closing)
          |> consume_report(reference, sequence, token)

        _ ->
          consume_report(current, reference, sequence, token)
      end
    end)
  end

  # Sends at most one terminal delivery for a live stream.
  defp terminal(state, reference, error) do
    case state.subscriptions[reference] do
      %{status: :active, receiver: receiver} ->
        send(receiver, {:wotex_thread, reference, {:error, error}})
        emit_subscription(:close, error.code)
        state

      _ ->
        state
    end
  end

  defp consume_report(state, reference, sequence, token) do
    %{id: id, generation: generation} = state.subscriptions[reference]

    case ReportLedger.consume(state.ledger, {id, generation}, sequence, token) do
      {:ok, ledger} ->
        acknowledge(%{state | ledger: ledger, reports: Map.delete(state.reports, sequence)})

      :ignore ->
        state
    end
  end

  # Installs the advanced ledger only after its cumulative acknowledgement is written.
  defp acknowledge(state) do
    case ReportLedger.advance(state.ledger) do
      {nil, _} ->
        state

      {ack, ledger} ->
        frame = %{
          version: 1,
          event: "report_ack",
          session_generation: state.session_generation,
          report_sequence: ack.report_sequence,
          acknowledged_bytes: ack.acknowledged_bytes
        }

        if send_line(state.port, frame),
          do: %{state | ledger: ledger},
          else: close(state, Error.new(:connection_closed))
    end
  end

  # Closed handles are remembered for this generation within a fixed bound.
  defp remember_closed(state, reference, generation) do
    key = {reference, generation}
    order = :queue.in(key, state.closed_order)
    closed = MapSet.put(state.closed, key)

    if :queue.len(order) > @closed_limit do
      {{:value, oldest}, order} = :queue.out(order)
      %{state | closed: MapSet.delete(closed, oldest), closed_order: order}
    else
      %{state | closed: closed, closed_order: order}
    end
  end

  defp stop_owner(record) do
    Process.demonitor(record.receiver_monitor, [:flush])
    Process.demonitor(record.owner_monitor, [:flush])
    Process.exit(record.owner, :kill)
  end

  defp emit_subscription(event, result) do
    :telemetry.execute([:wotex, :thread, :subscription, event], %{count: 1}, %{result: result})
  end

  defp close(%{status: :closing} = state, error), do: %{state | failure: state.failure || error}

  defp close(state, error) do
    Process.cancel_timer(state.start_timer)
    send_frame(state.port, "close", "close", %{}, now() + 900)
    Process.send_after(self(), :terminate_bridge, 40)
    Process.send_after(self(), :kill_bridge, 900)
    %{state | status: :closing, failure: error}
  end

  defp reply_all(state) do
    error = state.failure || Error.new(:connection_closed)

    Enum.each(state.waiters, fn {monitor, from} ->
      Process.demonitor(monitor, [:flush])
      GenServer.reply(from, {:error, error})
    end)

    Enum.each(
      state.close_waiters,
      &GenServer.reply(&1, if(state.failure, do: {:error, state.failure}, else: :ok))
    )

    # Each live stream receives one terminal error; joined cancellations succeed.
    stream_error = if state.failure, do: error, else: Error.new(:connection_closed)

    state =
      Enum.reduce(state.subscriptions, state, fn {reference, record}, current ->
        current = terminal(current, reference, stream_error)
        Enum.each(record.waiters, &GenServer.reply(&1, :ok))
        stop_owner(record)
        current
      end)

    Enum.reduce(
      Map.keys(state.pending),
      %{state | waiters: %{}, close_waiters: [], subscriptions: %{}, streams: %{}, reports: %{}},
      &complete(&2, &1, {:error, error})
    )
  end

  defp session_value(state),
    do: %Session{
      client: Wotex.Thread.OpenThread,
      handle: state.handle,
      timeout: state.config.timeout
    }

  defp open_port(executable) do
    {:ok,
     Port.open({:spawn_executable, executable}, [
       :binary,
       :exit_status,
       {:line, 131_071},
       args: [],
       env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
     ])}
  rescue
    _ -> :error
  end

  defp send_frame(port, id, operation, parameters, deadline) do
    timeout = deadline - now()

    timeout > 0 and
      send_line(port, %{
        version: 1,
        id: id,
        operation: operation,
        parameters: parameters,
        timeout_ms: min(timeout, 60_000)
      })
  end

  defp send_line(port, frame) do
    Port.command(port, Jason.encode!(frame) <> "\n", [:nosuspend])
  rescue
    _ -> false
  end

  defp signal_port(port, signal) do
    case port && Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("/bin/kill", [signal, Integer.to_string(pid)],
          stderr_to_stdout: true,
          env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
        )

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp call(pid, message, timeout) do
    case owner_status(pid, message) do
      :owned -> GenServer.call(pid, message, timeout)
      :closed -> {:error, Error.new(:connection_closed)}
      :invalid -> {:error, Error.new(:invalid_handle)}
    end
  catch
    :exit, {:timeout, _} -> call_failure(message, :cleanup_timeout)
    :exit, _ -> call_failure(message, :connection_closed)
  after
    drain_receipt(message)
  end

  defp mutation_result({:error, %Error{} = error}, operation) do
    if Request.mutation?(operation),
      do: {:error, %{error | effect: :unknown, retryable: false}},
      else: {:error, error}
  end

  defp mutation_result(result, _), do: result

  defp call_failure(message, code) do
    error = Error.new(code)
    if drain_receipt(message), do: {:error, %{error | effect: :unknown}}, else: {:error, error}
  end

  defp drain_receipt({_, :request, _, _, receipt}) do
    receive do
      {:wotex_thread_submitted, ^receipt} -> true
    after
      0 -> false
    end
  end

  defp drain_receipt(_), do: false

  defp owner_status(pid, message) when pid != self() do
    case :erlang.process_info(pid, {:dictionary, @owner_key}) do
      {{:dictionary, @owner_key}, reference} when is_reference(reference) ->
        if message == :session or elem(message, 0) == reference, do: :owned, else: :invalid

      :undefined ->
        :closed

      _ ->
        :invalid
    end
  end

  defp owner_status(_, _), do: :invalid

  defp now, do: System.monotonic_time(:millisecond)
end
