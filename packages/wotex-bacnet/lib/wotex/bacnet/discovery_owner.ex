defmodule Wotex.BACnet.DiscoveryOwner do
  @moduledoc """
  Owns the listener and send worker for one explicit Who-Is window.

  Registration precedes transmission. The verified wrapper checks the caller,
  listener, and absolute deadline again immediately before sending. Direct
  I-Am messages from the selected client feed
  `Wotex.BACnet.DiscoveryWindow`; routed or unrelated messages do not become
  discovered devices through this path.

  Caller, session, or client loss terminates collection. Completion unregisters
  the listener, cancels timers, and stops the owned send worker within the
  cleanup budget. Overflow or failed cleanup is reported as failure rather than
  a successful partial device list. No continuous discovery process is started
  by loading the library.
  """

  use GenServer
  alias BACnet.Protocol.NPCI
  alias Wotex.BACnet.{DiscoveryWindow, Error, StackClient}

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)
    clock = Map.get(options, :clock, fn -> System.monotonic_time(:millisecond) end)
    schedule = Map.get(options, :schedule, &Process.send_after/3)
    cancel = Map.get(options, :cancel_timer, &Process.cancel_timer/1)
    token = options.token
    window = options.window

    pending =
      :gen_server.send_request(options.client, {:wotex_client, :register_discovery, window.expires})

    {:ok,
     Map.merge(options, %{
       clock: clock,
       schedule: schedule,
       cancel_timer: cancel,
       token: token,
       phase: :registering,
       cleanup_deadline: nil,
       pending: pending,
       worker: nil,
       caller_monitor: Process.monitor(elem(options.from, 0)),
       session_monitor: Process.monitor(options.session),
       client_monitor: Process.monitor(options.client),
       timer: schedule.(self(), {:window, token}, max(window.expires - clock.(), 0))
     })}
  end

  @impl GenServer
  def handle_info({:window, token}, %{token: token, phase: phase} = state)
      when phase != :closing do
    window = DiscoveryWindow.finish(state.window, state.clock.())

    outcome =
      if state.phase == :collecting,
        do: window.outcome || {:error, Error.new(:deadline_exceeded)},
        else: {:error, Error.new(:deadline_exceeded)}

    close(%{state | window: window}, outcome)
  end

  def handle_info({:cleanup, token}, %{token: token, phase: :closing} = state),
    do: complete(state, cleanup_failure(state.window.outcome))

  def handle_info({:session_closing, session, deadline}, %{session: session} = state),
    do: close(state, {:error, Error.new(:connection_closed)}, deadline)

  def handle_info({:DOWN, ref, :process, _, _}, state)
      when ref in [state.caller_monitor, state.session_monitor, state.client_monitor],
      do: close(state, {:error, Error.new(:connection_closed)})

  def handle_info({:DOWN, ref, :process, pid, _}, %{worker: {pid, ref}} = state),
    do: close(%{state | worker: nil}, {:error, Error.new(:connection_closed)})

  def handle_info({:wire_result, pid, token, result}, %{worker: {pid, _}, token: token} = state) do
    state = stop_worker(state)

    case result do
      :ok -> {:noreply, %{state | phase: :collecting}}
      {:error, %Error{} = error} -> close(state, {:error, error})
      _ -> close(state, {:error, Error.new(:transport_error)})
    end
  end

  def handle_info(
        {:bacnet_client, _, apdu, {source, _, %NPCI{source: nil}}, client},
        %{client: client, phase: phase} = state
      )
      when phase in [:sending, :collecting] do
    window = DiscoveryWindow.accept(state.window, source, apdu, state.clock.())
    state = %{state | window: window}

    cond do
      window.outcome != nil -> close(state, window.outcome)
      queue_length() >= 1000 -> close(state, {:error, Error.new(:slow_consumer)})
      true -> {:noreply, state}
    end
  end

  def handle_info(message, %{pending: pending} = state) when pending != nil do
    case :gen_server.check_response(message, pending) do
      {:reply, :ok} -> registered_or_closed(%{state | pending: nil})
      {:reply, _} -> failed_response(%{state | pending: nil})
      {:error, _} -> failed_response(%{state | pending: nil})
      :no_reply -> {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    stop_worker(state)
    if state.timer, do: state.cancel_timer.(state.timer)
    if state.pending, do: :gen_server.receive_response(state.pending, 0)

    if state.phase != :closed do
      request = :gen_server.send_request(state.client, {:wotex_client, :unregister_discovery})
      :gen_server.receive_response(request, 0)
    end

    :ok
  end

  defp registered_or_closed(%{phase: :closing} = state),
    do: complete(state, state.window.outcome)

  defp registered_or_closed(state) do
    case DiscoveryWindow.admission(state.window, state.clock.()) do
      {:ok, deadline} ->
        owner = self()
        window = state.window

        worker =
          :erlang.spawn_opt(
            fn ->
              result =
                StackClient.discovery_send(
                  state.client,
                  window.destination,
                  window.apdu,
                  deadline,
                  elem(state.from, 0),
                  owner
                )

              send(owner, {:wire_result, self(), state.token, result})
            end,
            [:link, :monitor]
          )

        {:noreply, %{state | phase: :sending, worker: worker}}

      {:error, _} = error ->
        close(state, error)
    end
  end

  defp failed_response(%{phase: :closing} = state),
    do: complete(state, cleanup_failure(state.window.outcome))

  defp failed_response(state), do: close(state, {:error, Error.new(:connection_closed)})

  defp close(state, outcome, deadline \\ nil)
  defp close(%{phase: :closing} = state, _, nil), do: {:noreply, state}

  defp close(%{phase: :closing} = state, outcome, deadline) do
    cleanup_deadline = min(state.cleanup_deadline, deadline)
    state.cancel_timer.(state.timer)

    timer =
      state.schedule.(self(), {:cleanup, state.token}, max(cleanup_deadline - state.clock.(), 0))

    {:noreply,
     %{
       state
       | cleanup_deadline: cleanup_deadline,
         timer: timer,
         window: %{state.window | outcome: outcome}
     }}
  end

  defp close(state, outcome, deadline) do
    state = stop_worker(state)
    if state.timer, do: state.cancel_timer.(state.timer)
    if state.pending, do: :gen_server.receive_response(state.pending, 0)
    now = state.clock.()
    cleanup_deadline = min(deadline || now + 1000, now + 1000)
    pending = :gen_server.send_request(state.client, {:wotex_client, :unregister_discovery})
    timer = state.schedule.(self(), {:cleanup, state.token}, max(cleanup_deadline - now, 0))
    window = %{state.window | devices: %{}, outcome: outcome}

    {:noreply,
     %{
       state
       | phase: :closing,
         pending: pending,
         timer: timer,
         window: window,
         cleanup_deadline: cleanup_deadline
     }}
  end

  defp complete(state, outcome) do
    outcome =
      if match?({:ok, _}, outcome) and state.clock.() >= state.window.deadline,
        do: {:error, Error.new(:deadline_exceeded)},
        else: outcome

    :telemetry.execute([:wotex, :bacnet, :discovery, :stop], %{ignored: state.window.ignored}, %{
      result: if(match?({:ok, _}, outcome), do: :ok, else: :error)
    })

    if state.timer, do: state.cancel_timer.(state.timer)
    send(state.session, {:discovery_result, self(), state.token, outcome})
    {:stop, :normal, %{state | phase: :closed, timer: nil, pending: nil}}
  end

  defp cleanup_failure({:error, _} = error), do: error
  defp cleanup_failure(_), do: {:error, Error.new(:cleanup_failed)}

  defp stop_worker(%{worker: nil} = state), do: state

  defp stop_worker(%{worker: {pid, ref}} = state) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    Process.demonitor(ref, [:flush])
    %{state | worker: nil}
  end

  defp queue_length do
    {:message_queue_len, length} = Process.info(self(), :message_queue_len)
    length
  end
end
