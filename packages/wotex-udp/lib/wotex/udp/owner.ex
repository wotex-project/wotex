defmodule Wotex.UDP.Owner do
  @moduledoc """
  An explicitly started process that owns one UDP socket and one owner epoch.

  Atomic admission bounds pending calls and queued send bytes before they enter
  the mailbox. One asynchronous socket operation runs at a time. The owner
  monitors callers, cancels abandoned operations and checks original deadlines
  at dispatch and delivery. Close cancels pending work and releases the socket.
  Handle retrieval reads immutable process-local metadata without queueing work.
  No global registry or unsolicited datagram delivery is used.
  """

  use GenServer

  alias Wotex.UDP.{Admission, Backend, Config, Endpoint, Error, Handle}

  @metadata_key {__MODULE__, :metadata}

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
         :ok <- validate(config, operation, args),
         bytes = queued_bytes(operation, args),
         :ok <-
           Admission.acquire(
             current.admission,
             config.max_pending_calls,
             config.max_queued_send_bytes,
             bytes
           ) do
      timeout = call_timeout(operation, args, config.max_timeout_ms)
      deadline = now() + timeout
      call_owner(owner, {operation, current.epoch, args, deadline}, timeout + 100)
    end
  end

  def call(_, _, _), do: error(:invalid_handle, :owner)

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
        admission = :atomics.new(1, signed: false)
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
           active: nil
         }}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_call({operation, epoch, args, deadline}, from, state) do
    cond do
      epoch != state.epoch ->
        release(state, operation, args)
        {:reply, error(:stale_handle, :owner), state}

      expired?(deadline, operation, args) ->
        release(state, operation, args)
        {:reply, error(:timeout, operation), state}

      operation == :close ->
        state =
          Enum.reduce(Map.keys(state.pending), state, fn id, acc ->
            finish(acc, id, error(:closed, :owner))
          end)

        release(state, operation, args)
        result = Backend.close(state.socket)
        {:stop, :normal, result, %{state | socket: nil}}

      true ->
        id = make_ref()

        request = %{
          from: from,
          operation: operation,
          args: args,
          deadline: deadline,
          monitor: Process.monitor(elem(from, 0)),
          timer: Process.send_after(self(), {:deadline, id}, max(deadline - now(), 0)),
          select: nil,
          datagrams: [],
          count: 0
        }

        state = %{
          state
          | pending: Map.put(state.pending, id, request),
            queue: :queue.in(id, state.queue)
        }

        {:noreply, advance(state)}
    end
  end

  def handle_call(_, _, state), do: {:reply, error(:invalid_handle, :owner), state}

  @impl GenServer
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
    release(state, request.operation, request.args)
    GenServer.reply(request.from, result)

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
      (is_integer(interface) and interface in 0..4_294_967_295) or
        (is_tuple(interface) and tuple_size(interface) == 4 and
           match?({:ok, _}, Endpoint.bind(interface, 0)))

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

  defp expired?(deadline, operation, args) do
    if operation in [:send, :recv, :recv_batch] and List.last(args) == 0,
      do: deadline < now(),
      else: deadline <= now()
  end

  defp release(state, operation, args),
    do:
      Admission.release(
        state.admission,
        state.config.max_queued_send_bytes,
        queued_bytes(operation, args)
      )

  defp queued_bytes(:send, [_, data, _]), do: byte_size(data)
  defp queued_bytes(_, _), do: 0

  defp call_timeout(operation, args, _) when operation in [:send, :recv, :recv_batch],
    do: List.last(args)

  defp call_timeout(_, _, limit), do: limit
  defp now, do: System.monotonic_time(:millisecond)
  defp error(kind, operation), do: {:error, %Error{kind: kind, operation: operation, reason: nil}}

  defp call_owner(owner, request, timeout) do
    GenServer.call(owner, request, timeout)
  catch
    :exit, {:timeout, _} -> error(:timeout, :owner)
    :exit, _ -> error(:owner_lost, :owner)
  end
end
