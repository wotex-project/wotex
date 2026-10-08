defmodule Wotex.UDP.Owner do
  @moduledoc """
  An explicitly started process that owns one UDP socket and one owner epoch.

  Atomic publication bounds complete requests and queued send bytes in an
  owner-owned ETS queue. One coalesced wakeup and a ten-millisecond sweep
  recover publication without notification; request payloads never enter the
  mailbox. One asynchronous socket operation runs at a time. The owner
  monitors callers, cancels abandoned operations and checks original deadlines
  at dispatch and delivery. Close cancels pending work and releases the socket.
  Handle retrieval reads immutable process-local metadata without queueing work.
  No global registry or unsolicited datagram delivery is used.
  """

  use GenServer

  alias Wotex.UDP.{Admission, Backend, Config, Endpoint, Error, Handle}

  @metadata_key {__MODULE__, :metadata}
  @poll_ms 10

  @doc "Starts one socket owner linked to the caller. No global name is used."
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config), do: GenServer.start_link(__MODULE__, config)

  @doc "Starts an owner without linking until socket admission has succeeded."
  @spec start(Config.t()) :: GenServer.on_start()
  def start(%Config{} = config), do: GenServer.start(__MODULE__, config)

  @doc "Gets this local owner's immutable handle without entering its mailbox."
  @spec handle(pid()) :: {:ok, Handle.t()} | {:error, Error.t()}
  def handle(owner) do
    with {:ok, {handle, _}} <- metadata(owner), do: {:ok, handle}
  end

  @doc "Calls an operation only when its handle matches the live owner epoch."
  @spec call(Handle.t(), atom(), [term()]) :: term()
  def call(%Handle{owner: owner} = handle, operation, args) do
    with {:ok, {current, config}} <- metadata(owner),
         :ok <- same_handle(handle, current),
         :ok <- validate(config, operation, args) do
      submit(current, config, operation, args)
    end
  end

  def call(_, _, _), do: error(:invalid_handle, :owner)

  defp submit(handle, config, operation, args) do
    monitor = Process.monitor(handle.owner)
    reply = :erlang.alias([:explicit_unalias])
    id = make_ref()
    requested = call_timeout(operation, args, config.max_timeout_ms)
    timeout = if requested == 0, do: min(config.max_timeout_ms, 100), else: requested

    request = %{
      id: id,
      from: {self(), reply},
      operation: operation,
      args: args,
      deadline: now() + timeout,
      epoch: handle.epoch
    }

    try do
      case Admission.enqueue(handle.admission, request) do
        {:ok, notification} ->
          if notification, do: send(notification, {:udp_work, notification})
          await_reply(id, reply, monitor, handle.owner, operation, request.deadline + 100)

        error ->
          if Process.alive?(handle.owner), do: error, else: error(:owner_lost, :owner)
      end
    after
      :erlang.unalias(reply)
      Process.demonitor(monitor, [:flush])

      receive do
        {:udp_reply, ^id, _} -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp await_reply(id, reply, monitor, owner, operation, deadline) do
    receive do
      {:udp_reply, ^id, {:owner_closed, result}} when operation == :close ->
        await_closed(monitor, owner, result, deadline)

      {:udp_reply, ^id, result} ->
        result

      {:DOWN, ^monitor, :process, ^owner, _} ->
        error(:owner_lost, :owner)
    after
      max(deadline - now(), 0) ->
        :erlang.unalias(reply)
        error(:timeout, :owner)
    end
  end

  defp await_closed(monitor, owner, result, deadline) do
    receive do
      {:DOWN, ^monitor, :process, ^owner, _} -> result
    after
      max(deadline - now(), 0) -> error(:timeout, :owner)
    end
  end

  defp metadata(owner) when is_pid(owner) and node(owner) == node() do
    case :erlang.process_info(owner, {:dictionary, @metadata_key}) do
      {{:dictionary, @metadata_key}, {%Handle{owner: ^owner}, %Config{}} = metadata} ->
        {:ok, metadata}

      :undefined ->
        error(:owner_lost, :owner)

      _ ->
        error(:invalid_handle, :owner)
    end
  end

  defp metadata(_), do: error(:invalid_handle, :owner)

  defp same_handle(%Handle{epoch: epoch} = handle, %Handle{epoch: epoch} = current) do
    if handle == current, do: :ok, else: error(:invalid_handle, :owner)
  end

  defp same_handle(_, _), do: error(:stale_handle, :owner)

  @impl GenServer
  def init(config) do
    case Backend.open(config) do
      {:ok, socket} ->
        notification = :erlang.alias([:explicit_unalias])

        admission =
          Admission.new(config.max_pending_calls, config.max_queued_send_bytes, notification)

        epoch = make_ref()

        handle = %Handle{
          owner: self(),
          epoch: epoch,
          admission: admission,
          max_timeout_ms: config.max_timeout_ms,
          max_datagram_bytes: config.max_datagram_bytes,
          max_pending_calls: config.max_pending_calls,
          max_queued_send_bytes: config.max_queued_send_bytes
        }

        Process.put(@metadata_key, {handle, config})

        {:ok,
         %{
           socket: socket,
           epoch: epoch,
           admission: admission,
           config: config,
           pending: %{},
           queue: :queue.new(),
           active: nil,
           notification: notification,
           poll: poll()
         }}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_call(_, _, state), do: {:reply, error(:invalid_handle, :owner), state}

  @impl GenServer
  def handle_info({:udp_work, notification}, %{notification: notification} = state), do: pump(state)

  def handle_info({:admission_poll, token}, %{poll: token} = state),
    do: pump(%{state | poll: poll()})

  def handle_info({:deadline, id}, state) do
    case Map.fetch(state.pending, id) do
      {:ok, request} -> {:noreply, advance(finish(state, id, timeout_result(request)))}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Enum.find(state.pending, fn {_, request} -> request.monitor == monitor end) do
      {id, _} -> {:noreply, advance(finish(state, id, error(:closed, :owner)))}
      nil -> {:noreply, state}
    end
  end

  def handle_info({:"$socket", socket, :select, reference}, state) do
    if selected?(state, socket, reference),
      do: {:noreply, step(state)},
      else: {:noreply, state}
  end

  def handle_info({:"$socket", socket, :abort, {reference, reason}}, state) do
    if selected?(state, socket, reference) do
      result = {:error, Error.from_socket(state.pending[state.active].operation, reason)}
      {:noreply, advance(finish(state, state.active, result))}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{socket: nil}), do: :ok
  def terminate(_, state), do: Backend.close(state.socket)

  defp poll do
    token = make_ref()
    Process.send_after(self(), {:admission_poll, token}, @poll_ms)
    token
  end

  defp pump(state) do
    old = state.notification
    :erlang.unalias(old)

    receive do
      {:udp_work, ^old} -> :ok
    after
      0 -> :ok
    end

    notification = :erlang.alias([:explicit_unalias])
    requests = Admission.take(state.admission, notification)
    state = %{state | notification: notification}

    case Enum.reduce_while(requests, state, &ingest/2) do
      {:stopped, state} -> {:stop, :normal, state}
      state -> {:noreply, advance(state)}
    end
  end

  defp ingest(request, state) do
    cond do
      request.epoch != state.epoch ->
        reject(state, request, error(:stale_handle, :owner))

      not Process.alive?(elem(request.from, 0)) ->
        reject(state, request, error(:closed, :owner))

      expired?(request.deadline, request.operation, request.args) ->
        reject(state, request, error(:timeout, request.operation))

      request.operation == :close ->
        state =
          Enum.reduce(Map.keys(state.pending), state, fn id, acc ->
            finish(acc, id, error(:closed, :owner))
          end)

        result = Backend.close(state.socket)
        respond(request.from, request.id, {:owner_closed, result})
        {:halt, {:stopped, %{state | socket: nil}}}

      true ->
        request =
          Map.merge(request, %{
            monitor: Process.monitor(elem(request.from, 0)),
            timer:
              Process.send_after(self(), {:deadline, request.id}, max(request.deadline - now(), 0)),
            select: nil,
            datagrams: [],
            count: 0
          })

        {:cont,
         %{
           state
           | pending: Map.put(state.pending, request.id, request),
             queue: :queue.in(request.id, state.queue)
         }}
    end
  end

  defp reject(state, request, result) do
    Admission.release(state.admission, request.id)
    respond(request.from, request.id, result)
    {:cont, state}
  end

  defp respond({_, reply}, id, result), do: send(reply, {:udp_reply, id, result})

  defp selected?(%{active: nil}, _, _), do: false

  defp selected?(state, socket, reference) do
    state.socket.handle == socket and
      match?({:select_info, _, ^reference}, state.pending[state.active].select)
  end

  defp advance(%{active: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, id}, queue} -> step(%{state | queue: queue, active: id})
      {:empty, _} -> state
    end
  end

  defp advance(state), do: state

  defp step(state) do
    id = state.active
    request = state.pending[id]

    if expired?(request.deadline, request.operation, request.args) or
         not Process.alive?(elem(request.from, 0)) do
      advance(finish(state, id, timeout_result(request)))
    else
      result = dispatch(state.socket, request)
      accept(state, id, request, result)
    end
  end

  defp accept(state, id, request, {:select, info}) do
    put_in(state.pending[id], %{request | select: info})
  end

  defp accept(state, id, %{operation: :recv_batch, args: [maximum, _]} = request, {:ok, datagram}) do
    if expired?(request.deadline, request.operation, request.args) do
      advance(finish(state, id, timeout_result(request)))
    else
      request = %{
        request
        | datagrams: [datagram | request.datagrams],
          count: request.count + 1,
          select: nil
      }

      state = put_in(state.pending[id], request)

      if request.count == maximum,
        do: advance(finish(state, id, {:ok, Enum.reverse(request.datagrams)})),
        else: step(state)
    end
  end

  defp accept(state, id, request, {:error, %Error{kind: :timeout}}),
    do: advance(finish(state, id, timeout_result(request)))

  defp accept(state, id, request, result) do
    result =
      if expired?(request.deadline, request.operation, request.args),
        do: timeout_result(request),
        else: result

    advance(finish(state, id, result))
  end

  defp finish(state, id, result) do
    {request, pending} = Map.pop(state.pending, id)
    if request.select, do: Backend.cancel(state.socket, request.select)
    Process.cancel_timer(request.timer)
    Process.demonitor(request.monitor, [:flush])
    Admission.release(state.admission, id)
    respond(request.from, id, result)

    %{
      state
      | pending: pending,
        queue: :queue.filter(&(&1 != id), state.queue),
        active: if(state.active == id, do: nil, else: state.active)
    }
  end

  defp timeout_result(%{operation: :recv_batch, datagrams: [_ | _] = datagrams}),
    do: {:ok, Enum.reverse(datagrams)}

  defp timeout_result(request), do: error(:timeout, request.operation)

  defp dispatch(socket, %{operation: :local}), do: Backend.local(socket)

  defp dispatch(socket, %{operation: :send, args: [destination, data, 0]}),
    do: Backend.send(socket, destination, data, 0)

  defp dispatch(socket, %{operation: :send, args: [destination, data, _], select: nil}),
    do: Backend.send_nowait(socket, destination, data)

  defp dispatch(socket, %{operation: :send, args: [_, data, _], select: info}),
    do: Backend.continue_send(socket, data, info)

  defp dispatch(socket, %{operation: :recv, args: [0]}), do: Backend.recv(socket, 0)
  defp dispatch(socket, %{operation: :recv_batch, args: [_, 0]}), do: Backend.recv(socket, 0)

  defp dispatch(socket, %{operation: operation}) when operation in [:recv, :recv_batch],
    do: Backend.recv_nowait(socket)

  defp dispatch(socket, %{operation: :join, args: [group, interface]}),
    do: Backend.join(socket, group, interface)

  defp dispatch(socket, %{operation: :leave, args: [group, interface]}),
    do: Backend.leave(socket, group, interface)

  defp validate(_, operation, []) when operation in [:close, :local], do: :ok

  defp validate(config, :send, [%Endpoint{} = destination, data, timeout]) when is_binary(data) do
    cond do
      not Endpoint.valid?(destination) -> error(:invalid_endpoint, :send)
      byte_size(data) > config.max_datagram_bytes -> error(:datagram_too_large, :send)
      true -> validate_timeout(config, timeout)
    end
  end

  defp validate(config, :recv, [timeout]), do: validate_timeout(config, timeout)

  defp validate(config, :recv_batch, [count, timeout]) do
    if is_integer(count) and count > 0 and count <= config.max_batch_datagrams,
      do: validate_timeout(config, timeout),
      else: error(:invalid_batch_size, :recv_batch)
  end

  defp validate(_, operation, [%Endpoint{} = group, interface]) when operation in [:join, :leave] do
    valid_interface =
      (is_integer(interface) and interface in 1..2_147_483_647) or
        (is_tuple(interface) and tuple_size(interface) == 4 and
           match?({:ok, _}, Endpoint.unicast(interface, 1)))

    if Endpoint.valid?(group) and valid_interface,
      do: :ok,
      else: error(:invalid_endpoint, operation)
  end

  defp validate(_, _, _), do: error(:invalid_endpoint, :owner)

  defp validate_timeout(config, timeout) do
    if is_integer(timeout) and timeout in 0..config.max_timeout_ms,
      do: :ok,
      else: error(:invalid_deadline, :deadline)
  end

  defp expired?(deadline, _, _), do: deadline <= now()

  defp call_timeout(operation, args, _) when operation in [:send, :recv, :recv_batch],
    do: List.last(args)

  defp call_timeout(_, _, limit), do: limit
  defp now, do: System.monotonic_time(:millisecond)
  defp error(kind, operation), do: {:error, %Error{kind: kind, operation: operation, reason: nil}}
end
