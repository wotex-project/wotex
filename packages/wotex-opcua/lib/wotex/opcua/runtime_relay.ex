defmodule Wotex.OPCUA.RuntimeRelay do
  @moduledoc """
  Owns one OPC UA Value observation on behalf of a Runtime subscription owner.

  The `Wotex.OPCUA.Transport` subscribe callback starts one unlinked relay per call. The
  relay opens its own Session through the configured client and subscribes with
  itself as the native receiver, so the client's receiver bound (64 messages)
  limits reports that wait while establishment completes. Until a
  `Wotex.OPCUA.RuntimeHandle` is returned, a separate watcher kills the relay
  when the Runtime owner or the establishing caller exits; the linked native
  owner then releases its process and Session.

  Once bound, each report is forwarded to the owner as
  `{:wotex_transport_frame, {:value, value, metadata}}` while the owner's
  message queue is below `max_queue_length`. Overflow, a terminal native error
  or an abnormal client exit sends one `{:error, error}` frame and one
  `:session_lost` (for `subscription_lost` and `sequence_gap`) or
  `:transport_down` status, then releases the subscription and Session. Owner
  death or `close/1` releases them without a frame. Cancellation and Session
  close share one 900 ms budget. The relay keeps no Runtime execution context and never
  resubscribes.
  """

  use GenServer
  alias Wotex.OPCUA
  alias Wotex.OPCUA.{Error, RuntimeHandle}

  @native_queue 64
  @release_ms 900
  @marker :wotex_opcua_runtime_relay

  @doc false
  @spec open(map()) :: {:ok, RuntimeHandle.t()} | {:error, Error.t()}
  def open(%{owner: owner, deadline: deadline} = options) when is_pid(owner) do
    generation = make_ref()

    case GenServer.start(__MODULE__, Map.merge(options, %{generation: generation, caller: self()})) do
      {:ok, relay} -> await_open(relay, generation, deadline)
      _ -> {:error, Error.new(:connection_failed)}
    end
  end

  defp await_open(relay, generation, deadline) do
    GenServer.call(relay, {:open, generation}, max(deadline - now(), 0) + 2 * @release_ms)
  catch
    :exit, _ ->
      Process.exit(relay, :kill)
      {:error, Error.new(:connection_failed)}
  end

  @doc false
  @spec close(term()) :: :ok | {:error, Error.t()}
  def close(%RuntimeHandle{pid: pid, generation: generation})
      when is_pid(pid) and is_reference(generation) and node(pid) == node() do
    case :erlang.process_info(pid, {:dictionary, @marker}) do
      {{:dictionary, @marker}, ^generation} -> call_close(pid, generation)
      :undefined -> :ok
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

  def close(_), do: {:error, Error.new(:invalid_subscription)}

  defp call_close(pid, generation) do
    GenServer.call(pid, {:close, generation}, @release_ms + 200)
  catch
    :exit, {reason, _} when reason in [:noproc, :normal] ->
      :ok

    :exit, _ ->
      Process.exit(pid, :kill)
      {:error, Error.new(:cleanup_failed)}
  end

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)
    Process.put(@marker, options.generation)
    relay = self()
    watcher = spawn(fn -> watch(relay, options.owner, options.caller) end)

    {:ok,
     Map.merge(options, %{
       phase: :opening,
       watcher: watcher,
       session: nil,
       subscription: nil,
       owner_monitor: nil
     })}
  end

  @impl GenServer
  def handle_call({:open, generation}, _, %{generation: generation, phase: :opening} = state) do
    with {:ok, session} <- connect(state),
         {:ok, subscription} <- subscribe(%{state | session: session}) do
      send(state.watcher, {:bound, self()})

      {:reply, {:ok, %RuntimeHandle{pid: self(), generation: generation}},
       %{
         state
         | phase: :bound,
           session: session,
           subscription: subscription,
           owner_monitor: Process.monitor(state.owner)
       }}
    else
      {:error, error, session} ->
        release(%{state | session: session}, false)
        {:stop, :normal, {:error, error}, state}

      {:error, error} ->
        {:stop, :normal, {:error, error}, state}
    end
  end

  def handle_call({:close, generation}, _, %{generation: generation, phase: :bound} = state) do
    result = release(state, true)
    {:stop, :normal, result, %{state | session: nil, subscription: nil}}
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info(
        {:wotex_opcua, reference, {:ok, value, metadata}},
        %{phase: :bound, subscription: %{reference: reference}} = state
      )
      when is_map(value) and is_map(metadata) do
    case Process.info(state.owner, :message_queue_len) do
      {:message_queue_len, length} when length < state.max_queue_length ->
        send(state.owner, {:wotex_transport_frame, {:value, value, metadata}})
        {:noreply, state}

      _ ->
        terminal(state, Error.new(:receiver_overflow), true)
    end
  end

  def handle_info(
        {:wotex_opcua, reference, {:error, %Error{} = error}},
        %{phase: :bound, subscription: %{reference: reference}} = state
      ),
      do: terminal(state, error, false)

  def handle_info({:wotex_opcua, reference, _}, %{subscription: %{reference: reference}} = state),
    do: terminal(state, Error.new(:invalid_native_frame), true)

  def handle_info({:DOWN, monitor, :process, _, _}, %{owner_monitor: monitor} = state) do
    release(state, true)
    {:stop, :normal, %{state | session: nil, subscription: nil}}
  end

  def handle_info({:EXIT, _, reason}, %{phase: :bound} = state) when reason != :normal,
    do: terminal(state, Error.new(:native_process_terminated), false)

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:log, _} -> {:log, []}
      {key, _} -> {key, :redacted}
    end)
  end

  defp connect(state) do
    case remaining(state.deadline) do
      0 ->
        {:error, Error.new(:deadline_exceeded)}

      timeout ->
        state.connection
        |> Keyword.put(:timeout, min(timeout, 60_000))
        |> OPCUA.connect()
    end
  end

  defp subscribe(state) do
    request =
      Map.merge(state.parameters, %{
        node_id: state.node_id,
        receiver: self(),
        max_queue_length: @native_queue
      })

    case remaining(state.deadline) do
      0 ->
        {:error, Error.new(:deadline_exceeded), state.session}

      timeout ->
        case OPCUA.subscribe(%{state.session | timeout: min(timeout, 60_000)}, request) do
          {:ok, subscription} -> {:ok, subscription}
          {:error, error} -> {:error, error, state.session}
          :not_supported -> {:error, Error.new(:not_supported), state.session}
        end
    end
  end

  defp terminal(state, error, unsubscribe) do
    send(state.owner, {:wotex_transport_frame, {:error, %{error | effect: :none}}})
    send(state.owner, {:wotex_transport_status, status(error)})
    release(state, unsubscribe)
    {:stop, :normal, %{state | session: nil, subscription: nil}}
  end

  defp status(%Error{code: code}) when code in [:subscription_lost, :sequence_gap],
    do: :session_lost

  defp status(_), do: :transport_down

  # Cancels the owned subscription when requested and always closes the Session.
  defp release(state, unsubscribe) do
    deadline = now() + @release_ms

    cancelled =
      if unsubscribe and state.subscription,
        do: OPCUA.unsubscribe(budgeted(state.session, deadline), state.subscription),
        else: :ok

    closed = OPCUA.disconnect(budgeted(state.session, deadline))
    if match?({:error, _}, cancelled), do: cancelled, else: closed
  end

  defp watch(relay, owner, caller) do
    for pid <- [relay, owner, caller], do: Process.monitor(pid)

    receive do
      {:bound, ^relay} -> :ok
      {:DOWN, _, :process, ^relay, _} -> :ok
      {:DOWN, _, :process, _, _} -> Process.exit(relay, :kill)
    end
  end

  defp budgeted(session, deadline), do: %{session | timeout: max(remaining(deadline), 1)}
  defp remaining(deadline), do: max(deadline - now(), 0)
  defp now, do: System.monotonic_time(:millisecond)
end
