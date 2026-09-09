defmodule Wotex.CoAP.Observation do
  @moduledoc """
  Coordinates one dedicated connection's Observe registration and report lifecycle.

  The connection owns datagrams, identifiers, retransmission and duplicate ACKs.
  This explicit coordinator owns receiver monitoring, report assembly and expiry;
  a caller-owned session is dedicated until cancellation or terminal cleanup.
  """

  use GenServer
  alias Wotex.CoAP
  alias Wotex.CoAP.{Block, Blockwise, Codec, Connection, Error, Execution, Observe}
  alias Wotex.CoAP.Observation.Report

  @doc "Validates a native Observe request without opening or registering anything."
  @spec options(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def options(path, receiver, options) do
    with {:ok, values} <- option_values(options, %{}),
         {:ok, request} <- CoAP.message(%{method: :get, path: path}),
         true <- is_pid(receiver) and node(receiver) == node(),
         renew = Map.get(values, :renew, true),
         queue = Map.get(values, :max_queue_length, 1000),
         true <- is_boolean(renew) and is_integer(queue) and queue in 1..10_000 do
      {:ok, %{request: request, receiver: receiver, renew: renew, max_queue_length: queue}}
    else
      _ -> failure(:invalid_observation_options)
    end
  end

  @doc false
  @spec start(map()) :: GenServer.on_start()
  def start(config), do: GenServer.start(__MODULE__, config)

  @impl GenServer
  def init(config) do
    Process.flag(:trap_exit, true)
    :ok = Execution.install(config.execution)
    Process.put(:wotex_coap_observation, {__MODULE__, config.handle.generation})
    send(self(), :register)

    {:ok,
     %{
       config: config,
       phase: :registering,
       report: nil,
       pending: nil,
       task: nil,
       task_ref: nil,
       timer: nil,
       timer_ref: nil,
       expiry: nil,
       refresh_at: nil,
       phase_deadline: config.deadline,
       from: config.from,
       cancel_from: nil,
       terminal: false,
       connection_monitor: Process.monitor(config.handle.pid),
       receiver_monitor: Process.monitor(config.receiver),
       caller_monitor: Process.monitor(elem(config.from, 0))
     }}
  end

  @impl GenServer
  def handle_call(
        {:cancel, handle, _},
        from,
        %{config: %{handle: handle}, phase: :canceling} = state
      ) do
    if length(state.cancel_from) < 64,
      do: {:noreply, %{state | cancel_from: [from | state.cancel_from]}},
      else: {:reply, failure(:busy), state}
  end

  def handle_call({:cancel, handle, deadline}, from, %{config: %{handle: handle}} = state) do
    Connection.observation_abort(state.config.handle.pid, state.config.capability)
    state = stop_task(state)
    state = cancel_timer(%{state | phase: :canceling, pending: nil, cancel_from: [from]})
    request = put_observe(state.config.request, 1)
    {:noreply, task(state, fn -> exchange(state, request, :cancel, deadline) end)}
  end

  def handle_call({:cancel, _, _}, _, state),
    do: {:reply, failure(:invalid_subscription), state}

  @impl GenServer
  def handle_info(:register, state) do
    request = put_observe(state.config.request, 0)
    {:noreply, task(state, fn -> exchange(state, request, :register, state.config.deadline) end)}
  end

  def handle_info(
        {:report, generation, message, received_at},
        %{config: %{handle: %{generation: generation}}} = state
      ) do
    if state.phase == :canceling,
      do: {:noreply, state},
      else: incoming(state, message, received_at)
  end

  def handle_info(
        {:transport_failed, generation, error},
        %{config: %{handle: %{generation: generation}}} = state
      ),
      do: terminal(state, error)

  def handle_info({:result, reference, result}, %{task_ref: reference} = state) do
    state = %{state | task: nil, task_ref: nil}
    completed(state, result)
  end

  def handle_info({:expiry, reference}, %{timer_ref: reference} = state) do
    cond do
      now() < state.refresh_at -> {:noreply, arm(state)}
      state.config.renew -> renew(state)
      true -> terminal(state, Error.new(:observation_stale))
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    cond do
      monitor == state.connection_monitor -> terminal(state, Error.new(:connection_closed))
      monitor == state.receiver_monitor -> {:stop, :normal, state}
      monitor == state.caller_monitor and not is_nil(state.from) -> {:stop, :normal, state}
      true -> {:noreply, state}
    end
  end

  def handle_info({:EXIT, worker, reason}, %{task: worker} = state) when reason != :normal,
    do: terminal(state, Error.new(:observation_failed))

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
    stop_task(state)
    cancel_timer(state)
    if state.from, do: GenServer.reply(state.from, failure(:connection_closed))

    if state.cancel_from,
      do: Enum.each(state.cancel_from, &GenServer.reply(&1, failure(:connection_closed)))

    Connection.close(state.config.handle.pid)
  end

  defp option_values([], values), do: {:ok, values}

  defp option_values([{key, value} | rest], values)
       when key in [:renew, :max_queue_length] and not is_map_key(values, key),
       do: option_values(rest, Map.put(values, key, value))

  defp option_values(_, _), do: failure(:invalid_observation_options)

  defp exchange(state, request, operation, deadline) do
    if deadline > now(),
      do:
        Connection.observation_exchange(
          state.config.handle.pid,
          state.config.capability,
          request,
          operation,
          max(1, deadline - now())
        ),
      else: failure(:timeout)
  end

  defp task(state, function) do
    owner = self()
    reference = make_ref()
    execution = Execution.context()

    worker =
      spawn_link(fn ->
        :ok = Execution.install(execution)
        send(owner, {:result, reference, function.()})
      end)

    %{state | task: worker, task_ref: reference}
  end

  defp completed(%{phase: :canceling} = state, {:ok, message}) do
    if Codec.option(message, 6) == [] do
      Enum.each(state.cancel_from, &GenServer.reply(&1, :ok))
      {:stop, :normal, %{state | cancel_from: nil}}
    else
      terminal(state, Error.new(:invalid_cancellation_response))
    end
  end

  defp completed(state, {:error, %Error{} = error}), do: terminal(state, error)

  defp completed(%{phase: phase} = state, {:ok, message, received_at})
       when phase in [:registering, :renewing] do
    with {:ok, report} <- Report.new(message, received_at),
         true <-
           is_nil(state.report) or
             report.metadata.content_format == state.report.metadata.content_format do
      assemble(%{state | report: report, phase: :assembling}, report)
    else
      false -> terminal(state, Error.new(:representation_changed))
      {:error, error} -> terminal(state, error)
    end
  end

  defp completed(%{phase: :assembling} = state, {:ok, message}) do
    case Report.complete(state.report, message) do
      {:ok, report} -> deliver(%{state | report: report})
      {:error, error} -> terminal(state, error)
    end
  end

  defp incoming(state, message, received_at) do
    case Report.new(message, received_at) do
      {:ok, candidate} -> candidate(state, candidate)
      {:error, error} -> terminal(state, error)
    end
  end

  defp candidate(%{report: nil, config: %{kind: :event}} = state, _),
    do: terminal(state, Error.new(:overlapping_event_report))

  defp candidate(%{report: nil, pending: nil} = state, report),
    do: {:noreply, %{state | pending: report}}

  defp candidate(%{report: nil} = state, report) do
    previous = state.pending

    if Observe.fresh?(
         previous.metadata.observe,
         report.metadata.observe,
         max(0, report.received_at - previous.received_at)
       ), do: {:noreply, %{state | pending: report}}, else: {:noreply, state}
  end

  defp candidate(state, candidate) do
    previous = state.pending || state.report

    cond do
      candidate.metadata.content_format != state.report.metadata.content_format ->
        terminal(state, Error.new(:representation_changed))

      not Observe.fresh?(
        previous.metadata.observe,
        candidate.metadata.observe,
        max(0, candidate.received_at - previous.received_at)
      ) ->
        {:noreply, state}

      state.phase in [:assembling, :renewing] and state.config.kind == :event ->
        terminal(state, Error.new(:overlapping_event_report))

      state.phase in [:assembling, :renewing] ->
        {:noreply, %{state | pending: candidate}}

      true ->
        assemble(
          cancel_timer(%{
            state
            | report: candidate,
              phase: :assembling,
              phase_deadline: now() + state.config.timeout
          }),
          candidate
        )
    end
  end

  defp assemble(state, report) do
    watch_phase(state)

    cond do
      state.phase_deadline <= now() ->
        terminal(state, Error.new(:timeout))

      complete_first?(report.first) ->
        complete_first(state, report.first)

      true ->
        {:noreply,
         task(state, fn ->
           Connection.observation_exchange(
             state.config.handle.pid,
             state.config.capability,
             state.config.request,
             {:continue, report.first},
             budget(state)
           )
         end)}
    end
  end

  defp complete_first?(message) do
    case Codec.option(message, 23) do
      [] -> true
      [value] -> match?({:ok, %{more: false}}, Block.decode(value))
    end
  end

  defp complete_first(state, first) do
    request = %{state.config.request | token: <<>>}

    {result, _} =
      Blockwise.continue(request, first, [], nil, fn _, value ->
        {failure(:invalid_observation_response), value}
      end)

    completed(state, result)
  end

  defp budget(state), do: max(1, state.phase_deadline - now())

  defp deliver(state) do
    if now() >= state.phase_deadline,
      do: terminal(state, Error.new(:timeout)),
      else: deliver_current(state)
  end

  defp deliver_current(state) do
    case Process.info(state.config.receiver, :message_queue_len) do
      {:message_queue_len, count} when count < state.config.max_queue_length ->
        send(
          state.config.receiver,
          {:wotex_coap, state.config.handle.reference,
           {:ok, state.report.message, state.report.metadata}}
        )

        state = established(state)
        pending(state)

      nil ->
        {:stop, :normal, state}

      _ ->
        terminal(state, Error.new(:receiver_overflow))
    end
  end

  defp established(state) do
    :ok =
      GenServer.call(state.config.handle.pid, {:observation_established, state.config.capability})

    if state.from do
      GenServer.reply(state.from, {:ok, state.config.handle})
      Process.demonitor(state.caller_monitor, [:flush])
    end

    %{state | from: nil, caller_monitor: nil}
  end

  defp pending(%{pending: nil} = state) do
    expiry = state.report.received_at + state.report.metadata.max_age * 1000

    refresh_at =
      if state.config.renew, do: max(expiry, state.report.received_at + 1000), else: expiry

    {:noreply, arm(%{state | phase: :active, expiry: expiry, refresh_at: refresh_at})}
  end

  defp pending(state) do
    report = state.pending
    previous = state.report
    state = %{state | phase: :active, pending: nil}

    if Observe.fresh?(
         previous.metadata.observe,
         report.metadata.observe,
         max(0, report.received_at - previous.received_at)
       ), do: candidate(state, report), else: pending(state)
  end

  defp renew(state) do
    state = cancel_timer(%{state | phase: :renewing, phase_deadline: now() + state.config.timeout})
    watch_phase(state)
    request = put_observe(state.config.request, 0)

    {:noreply, task(state, fn -> exchange(state, request, :renew, state.phase_deadline) end)}
  end

  defp watch_phase(state) do
    :ok =
      GenServer.call(
        state.config.handle.pid,
        {:observation_phase, state.config.capability, state.phase_deadline}
      )
  end

  defp arm(state) do
    state = cancel_timer(state)
    reference = make_ref()

    timer =
      Execution.schedule({:expiry, reference}, min(60_000, max(0, state.refresh_at - now())))

    %{state | timer: timer, timer_ref: reference}
  end

  defp cancel_timer(state) do
    if state.timer, do: Execution.cancel(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end

  defp stop_task(state) do
    if state.task, do: Process.exit(state.task, :kill)
    %{state | task: nil, task_ref: nil}
  end

  defp terminal(state, error) do
    Connection.observation_terminal(state.config.handle.pid, state.config.capability, error)
    if state.from, do: GenServer.reply(state.from, {:error, error})
    if state.cancel_from, do: Enum.each(state.cancel_from, &GenServer.reply(&1, {:error, error}))
    {:stop, :normal, %{state | from: nil, cancel_from: nil, terminal: true}}
  end

  defp put_observe(request, value),
    do: %{request | options: [{6, Codec.uint(value)} | request.options]}

  defp now, do: Execution.now_ms()
  defp failure(code), do: {:error, Error.new(code)}
end
