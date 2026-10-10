defmodule Wotex.Matter.Bridge.Connection do
  @moduledoc """
  Owns one native bridge Port and its bounded consumer execution lifetime.

  Start explicitly with `start_link/1` or the temporary child specification.
  Required options are the explicit `:owner` pid, `:executable`, its lowercase `:executable_sha256`,
  explicit `:arguments`, a nonblocking BEAM-millisecond `:clock`, a qualified
  lower elapsed-time `:minimum_rate`, required `:policy`, exact `:routes` and
  a startup handshake `:timeout` from 1 to 5000 milliseconds. Policy and routes have the
  contract of `Wotex.Matter.Bridge.Consumer`. No executable is discovered,
  downloaded or built, and inherited environment variables are cleared.

  The caller owns the selected immutable executable and its bootstrap
  arguments, including native credentials, store, endpoints and networking.
  Digest admission checks the caller-selected file; it does not protect an
  artifact that another actor changes after validation. The selected native
  host must implement `Wotex.Matter.Bridge.Control`, enforce authenticated SDK
  admission before emitting requests and close/drain SDK custody on input loss.
  Ready/model receipts and captured principal values do not supply those checks.

  One random generation binds open/ready, clock probes, requests, results, observations and
  close/closed. A successful start requires the exact pinned ready receipt and
  one correlated clock sample. The caller must qualify the supplied clocks,
  rate and sampling bounds described by `Wotex.Matter.Bridge.ClockProjection`;
  this process neither derives that qualification nor substitutes a default.

  At most sixteen requests include queued frames and running consumer work.
  Native IDs increase strictly, with gaps permitted. One pending probe services
  the ordered queue without extending any original native deadline. Expired
  or refused submissions yield unknown outcome without executing or retrying
  a handler. Completed results are collected once and written without suspending
  this owner; a busy or failed native pipe closes the generation.

  The configured owner alone may call `status/1`, `observe/3` or `close/1`.
  Owner, native Port or consumer loss closes execution and reaps the native
  process. One `{:wotex_matter_bridge_closed, connection, generation, error}`
  message reports channel loss to the configured owner, with no external exception or
  payload text. An admitted mutation makes subsequent loss conservatively
  unknown. Explicit close stops consumer work, requires the exact closed receipt
  and zero native exit within a separate one-second cleanup grace, then joins
  Port release. Separate approved observations retain at most sixty-four slots
  until a matching applied/refused receipt or generation closure. Delivery is
  explicit and independent of handler results. A consumer result mapper must
  obtain its required receipt before returning completed. This process supplies
  no production SDK host binary, authenticated-peer evidence or host-clock qualification.
  """

  use GenServer

  alias Wotex.Matter.Bridge.{
    ClockProbe,
    ClockProjection,
    ConnectionConfiguration,
    Consumer,
    Control,
    Observation,
    Wire
  }

  alias Wotex.Matter.Bridge.PortProcess
  alias Wotex.Matter.Error

  @uint64 0xFFFFFFFFFFFFFFFF
  @limit 16
  @cleanup 1000
  @observation_limit 64

  @doc "Starts one explicitly selected native process and its private execution owner."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(options) do
    with {:ok, configuration} <- ConnectionConfiguration.build(options),
         true <- Process.alive?(configuration.owner),
         :ok <- PortProcess.verify(configuration) do
      case GenServer.start_link(__MODULE__, {self(), configuration}) do
        {:ok, connection} ->
          case GenServer.call(connection, :bootstrap, :infinity) do
            :ok -> {:ok, connection}
            {:error, _} = error -> error
          end

        _ ->
          {:error, Error.new(:connection_failed)}
      end
    else
      false -> {:error, Error.new(:owner_closed)}
      {:error, error} -> {:error, error}
    end
  catch
    :exit, _ -> {:error, Error.new(:connection_failed)}
  end

  @doc "Uses temporary supervision so a lost native generation cannot restart implicitly."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  @doc "Returns only generation and bounded execution counts to the configured owner."
  @spec status(term()) :: {:ok, map()} | {:error, Error.t()}
  def status(connection), do: call(connection, :status)

  @doc "Stops owned work and joins native close, exit and Port release without retry."
  @spec close(term()) :: :ok | {:error, Error.t()}
  def close(connection), do: call(connection, :close)

  @doc """
  Delivers explicit approved state and waits for its correlated native receipt.

  Only the configured owner may call this function. All observation fields
  follow `Wotex.Matter.Bridge.Observation`. `deadline` is an absolute
  millisecond value on the configured BEAM clock, strictly in the future and
  at most 500 milliseconds away. At most sixty-four observations retain credit
  until their matching receipt or generation closure. IDs are independent of
  requests and probes and are never reused within the generation.

  `:applied` means endpoint validation and approved-state application;
  `:refused` preserves prior state. Neither outcome completes a request or
  establishes a physical effect. Missing, late, malformed or replayed receipts
  close the generation. Explicit close cancels pending callers once.
  """
  @spec observe(term(), Observation.t(), integer()) ::
          {:ok, :applied | :refused} | {:error, Error.t()}
  def observe(connection, observation, deadline),
    do: call(connection, {:observe, observation, deadline})

  @impl GenServer
  def init({starter, configuration}) do
    Process.flag(:trap_exit, true)
    generation = :crypto.strong_rand_bytes(16)

    {:ok,
     %{
       starter: starter,
       configuration: configuration,
       owner: configuration.owner,
       owner_monitor: Process.monitor(configuration.owner),
       generation: generation,
       mutation: false,
       error: nil
     }}
  end

  defp launch(%{configuration: configuration} = startup) do
    generation = startup.generation

    options = [
      generation: generation,
      receiver: self(),
      clock: configuration.clock,
      policy: configuration.policy,
      routes: configuration.routes
    ]

    case Consumer.start_link(options) do
      {:ok, consumer} ->
        case PortProcess.open(configuration) do
          {:ok, port} ->
            state =
              initial(
                startup.owner,
                startup.owner_monitor,
                consumer,
                port,
                generation,
                configuration
              )

            deadline = System.monotonic_time(:millisecond) + configuration.timeout

            start_bootstrap(state, deadline)

          {:error, error} ->
            Consumer.close(consumer)
            {:error, error, startup}
        end

      {:error, error} ->
        {:error, error, startup}
    end
  end

  defp start_bootstrap(state, deadline) do
    bootstrap(state, deadline)
  rescue
    _ -> failed_bootstrap(state)
  catch
    _, _ -> failed_bootstrap(state)
  end

  defp failed_bootstrap(state) do
    {:error, Error.new(:connection_failed), state}
  end

  defp initial(owner, owner_monitor, consumer, port, generation, configuration) do
    %{
      owner: owner,
      owner_monitor: owner_monitor,
      consumer: consumer,
      consumer_monitor: Process.monitor(consumer),
      port: port,
      port_monitor: :erlang.monitor(:port, port),
      generation: generation,
      clock: configuration.clock,
      minimum_rate: configuration.minimum_rate,
      last_ms: nil,
      last_id: 0,
      last_probe_id: 0,
      last_observation_id: 0,
      observations: %{},
      projection: nil,
      probe: nil,
      pending: %{},
      queue: :queue.new(),
      mutation: false,
      error: nil
    }
  end

  @impl GenServer
  def handle_continue(:drain, state), do: transition(drain(state))

  @impl GenServer
  def handle_call(:bootstrap, {starter, _}, %{starter: starter} = state) do
    case launch(state) do
      {:ok, ready} -> {:reply, :ok, ready, {:continue, :drain}}
      {:error, error, failed} -> {:stop, :normal, {:error, error}, failed}
    end
  end

  def handle_call(:status, {owner, _}, %{owner: owner} = state) do
    {:reply,
     {:ok,
      %{
        generation: state.generation,
        pending: map_size(state.pending),
        probing: state.probe != nil,
        observations: map_size(state.observations)
      }}, state}
  end

  def handle_call({:observe, observation, deadline}, {owner, _} = from, %{owner: owner} = state) do
    cond do
      map_size(state.observations) >= @observation_limit ->
        {:reply, {:error, Error.new(:busy)}, state}

      state.last_observation_id == @uint64 ->
        {:stop, :normal, {:error, failure(state, :response_limit)},
         %{state | error: failure(state, :response_limit)}}

      true ->
        admit_observation(observation, deadline, from, state)
    end
  end

  def handle_call(:close, {owner, _}, %{owner: owner} = state) do
    state = cancel_observers(state, failure(state, :owner_closed))
    Consumer.close(state.consumer)
    if state.probe, do: Process.cancel_timer(state.probe.timer)
    {:ok, frame} = Control.encode(:close, state.generation)

    reply =
      if PortProcess.send_frame(state.port, frame),
        do: await_close(state, System.monotonic_time(:millisecond) + @cleanup, false),
        else: {:error, failure(state, :transport_closed)}

    joined = PortProcess.close(state.port)
    reply = if reply == :ok, do: joined, else: reply

    reply =
      case reply do
        {:error, error} ->
          {:error, Error.with_effect(error, if(state.mutation, do: :unknown, else: :none))}

        result ->
          result
      end

    {:stop, :normal, reply, state}
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_request)}, state}

  @impl GenServer
  def handle_info({port, {:data, {:eol, body}}}, %{port: port} = state),
    do: transition(receive_frame(body <> "\n", state))

  def handle_info({port, {:data, _}}, %{port: port} = state),
    do: stop(state, :response_limit)

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: stop(state, :invalid_transport_return, %{exit_status: status})

  def handle_info({:DOWN, monitor, :port, _, _}, %{port_monitor: monitor} = state),
    do: stop(state, :transport_closed)

  def handle_info({:DOWN, monitor, :process, _, _}, %{owner_monitor: monitor} = state),
    do: stop(state, :owner_closed)

  def handle_info({:DOWN, monitor, :process, _, _}, %{consumer_monitor: monitor} = state),
    do: stop(state, :owner_closed)

  def handle_info({:EXIT, consumer, _}, %{consumer: consumer} = state),
    do: stop(state, :owner_closed)

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: stop(state, :transport_closed)

  def handle_info({:probe_expired, token}, %{probe: %{token: token}} = state),
    do: stop(state, :timeout)

  def handle_info(
        {:wotex_matter_bridge_ready, consumer, generation, id},
        %{consumer: consumer, generation: generation} = state
      ) do
    with %{phase: :running} <- Map.get(state.pending, id),
         {:ok, frame} <- Consumer.take_result(consumer, id),
         true <- PortProcess.send_frame(state.port, frame) do
      transition(drain(%{state | pending: Map.delete(state.pending, id)}))
    else
      _ -> stop(state, :transport_closed)
    end
  end

  def handle_info({:observation_expired, id, token}, state) do
    case Map.get(state.observations, id) do
      %{token: ^token} -> stop(state, :timeout)
      _ -> {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    cleanup(state)

    if Map.get(state, :error),
      do: send(state.owner, {:wotex_matter_bridge_closed, self(), state.generation, state.error})

    :ok
  end

  @impl GenServer
  def format_status(status) do
    status
    |> Map.put(:state, :redacted)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp bootstrap(state, deadline) do
    {:ok, frame} = Control.encode(:open, state.generation)

    with true <- System.monotonic_time(:millisecond) < deadline,
         true <- PortProcess.send_frame(state.port, frame),
         :ok <- await_ready(state, deadline),
         {:ok, probing} <- probe(state, max(1, deadline - System.monotonic_time(:millisecond))) do
      await_probe(probing, deadline)
    else
      {:error, error, failed} -> {:error, error, failed}
      {:error, error} -> {:error, error, state}
      _ -> {:error, Error.new(:connection_failed), state}
    end
  end

  defp await_ready(state, deadline) do
    port = state.port
    owner = state.owner_monitor
    consumer = state.consumer_monitor
    native = state.port_monitor
    consumer_pid = state.consumer

    receive do
      {^port, {:data, {:eol, body}}} ->
        within(deadline, fn -> Control.decode(body <> "\n", :ready, state.generation) end)

      {^port, {:exit_status, status}} ->
        {:error, Error.new(:invalid_transport_return, nil, %{exit_status: status})}

      {^port, _} ->
        {:error, Error.new(:invalid_ready)}

      {:DOWN, ^owner, :process, _, _} ->
        {:error, Error.new(:owner_closed)}

      {:DOWN, ^consumer, :process, _, _} ->
        {:error, Error.new(:owner_closed)}

      {:DOWN, ^native, :port, _, _} ->
        {:error, Error.new(:transport_closed)}

      {:EXIT, ^consumer_pid, _} ->
        {:error, Error.new(:owner_closed)}
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> {:error, Error.new(:timeout)}
    end
  end

  defp await_probe(state, deadline) do
    port = state.port
    owner = state.owner_monitor
    consumer = state.consumer_monitor
    native = state.port_monitor
    consumer_pid = state.consumer

    receive do
      {^port, {:data, {:eol, body}}} ->
        case startup_ingest(body <> "\n", state, deadline) do
          {:ok, %{probe: nil} = next} -> {:ok, next}
          {:ok, next} -> await_probe(next, deadline)
          {:error, error, failed} -> {:error, error, failed}
        end

      {^port, {:exit_status, status}} ->
        {:error, Error.new(:invalid_transport_return, nil, %{exit_status: status}), state}

      {^port, _} ->
        {:error, Error.new(:invalid_frame), state}

      {:DOWN, ^owner, :process, _, _} ->
        {:error, Error.new(:owner_closed), state}

      {:DOWN, ^consumer, :process, _, _} ->
        {:error, Error.new(:owner_closed), state}

      {:DOWN, ^native, :port, _, _} ->
        {:error, Error.new(:transport_closed), state}

      {:EXIT, ^consumer_pid, _} ->
        {:error, Error.new(:owner_closed), state}
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        {:error, Error.new(:timeout), state}
    end
  end

  defp startup_ingest(frame, state, deadline) do
    case within(deadline, fn -> ingest(frame, state) end) do
      {:error, error} -> {:error, error, state}
      result -> result
    end
  end

  defp within(deadline, callback) do
    if System.monotonic_time(:millisecond) < deadline do
      result = callback.()

      if System.monotonic_time(:millisecond) < deadline,
        do: result,
        else: {:error, Error.new(:timeout)}
    else
      {:error, Error.new(:timeout)}
    end
  end

  defp receive_frame(frame, state) do
    with {:ok, next} <- ingest(frame, state), do: drain(next)
  end

  defp ingest(frame, state) do
    case Wire.decode_request(frame, state.generation) do
      {:ok, request} ->
        enqueue(frame, request, state)

      _ ->
        case observation_id(frame) do
          {:ok, id} -> observation_reply(frame, id, state)
          :error -> sample_reply(frame, state)
        end
    end
  end

  defp enqueue(frame, request, state) do
    if request.id > state.last_id and map_size(state.pending) < @limit do
      entry = %{
        frame: frame,
        deadline: request.deadline_native_ms,
        phase: :queued,
        refreshed: false
      }

      {:ok,
       %{
         state
         | last_id: request.id,
           pending: Map.put(state.pending, request.id, entry),
           queue: :queue.in(request.id, state.queue),
           mutation: state.mutation or request.operation in [:write, :invoke]
       }}
    else
      {:error, Error.new(:invalid_frame), state}
    end
  end

  defp sample_reply(frame, %{probe: %{} = probe} = state) do
    with true <- System.monotonic_time(:millisecond) < probe.deadline,
         {:ok, native} <- ClockProbe.decode(frame, state.generation, probe.id),
         true <- state.projection == nil or native >= state.projection.native_ms,
         {:ok, now} <- sample(state),
         {:ok, projection} <-
           ClockProjection.new(state.generation, probe.before, now, native, state.minimum_rate),
         true <- System.monotonic_time(:millisecond) < probe.deadline do
      Process.cancel_timer(probe.timer)
      {:ok, %{state | probe: nil, projection: projection, last_ms: now}}
    else
      _ -> {:error, Error.new(:invalid_frame), state}
    end
  end

  defp sample_reply(_, state), do: {:error, Error.new(:invalid_frame), state}

  defp drain(%{probe: %{}} = state), do: {:ok, state}

  defp drain(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {:ok, state}

      {{:value, id}, queue} ->
        entry = Map.fetch!(state.pending, id)

        case sample(state) do
          {:ok, now} ->
            next = %{state | last_ms: now}

            case projected_deadline(next, entry.deadline, now) do
              {:ok, _} -> dispatch(id, entry, queue, next)
              {:error, %Error{code: :probe_required}} -> refresh(id, entry, next)
              {:error, %Error{code: :deadline_exceeded}} -> reject(id, queue, next)
              _ -> {:error, Error.new(:invalid_transport_context), next}
            end

          {:error, error} ->
            {:error, error, state}
        end
    end
  end

  defp projected_deadline(state, deadline, now),
    do: ClockProjection.deadline(state.projection, state.generation, deadline, now)

  defp refresh(_, %{refreshed: true}, state),
    do: {:error, Error.new(:invalid_transport_context), state}

  defp refresh(id, entry, state) do
    pending = Map.put(state.pending, id, %{entry | refreshed: true})
    probe(%{state | pending: pending}, 500)
  end

  defp dispatch(id, entry, queue, state) do
    case Consumer.submit(state.consumer, entry.frame, state.projection) do
      {:ok, ^id} ->
        pending = Map.put(state.pending, id, %{phase: :running})
        drain(%{state | pending: pending, queue: queue})

      {:error, %Error{code: code}} when code in [:busy, :deadline_exceeded] ->
        reject(id, queue, state)

      _ ->
        {:error, Error.new(:owner_closed), state}
    end
  end

  defp reject(id, queue, state) do
    {:ok, frame} = Wire.encode_result(state.generation, id, :unknown)

    if PortProcess.send_frame(state.port, frame),
      do: drain(%{state | pending: Map.delete(state.pending, id), queue: queue}),
      else: {:error, Error.new(:transport_closed), state}
  end

  defp probe(state, timeout) do
    with true <- state.last_probe_id < @uint64,
         {:ok, now} <- sample(state),
         id = state.last_probe_id + 1,
         {:ok, frame} <- ClockProbe.encode(state.generation, id),
         true <- PortProcess.send_frame(state.port, frame) do
      token = make_ref()
      timer = Process.send_after(self(), {:probe_expired, token}, timeout)

      deadline = System.monotonic_time(:millisecond) + timeout

      {:ok,
       %{
         state
         | last_probe_id: id,
           last_ms: now,
           probe: %{id: id, before: now, timer: timer, token: token, deadline: deadline}
       }}
    else
      _ -> {:error, Error.new(:invalid_transport_context), state}
    end
  end

  defp sample(state) do
    now = state.clock.()

    if is_integer(now) and now in -0x8000000000000000..0x7FFFFFFFFFFFFFFF and
         (state.last_ms == nil or now >= state.last_ms),
       do: {:ok, now},
       else: {:error, Error.new(:invalid_transport_context)}
  rescue
    _ -> {:error, Error.new(:invalid_transport_context)}
  catch
    _, _ -> {:error, Error.new(:invalid_transport_context)}
  end

  defp await_close(state, deadline, acknowledged, discarded \\ 0) do
    port = state.port
    owner = state.owner_monitor

    receive do
      {^port, {:data, {:eol, body}}} when not acknowledged ->
        case within(deadline, fn -> closing_frame(body <> "\n", state, discarded) end) do
          {:ack, next} -> await_close(next, deadline, true, discarded)
          {:discard, next, count} -> await_close(next, deadline, false, count)
          {:error, _} = error -> error
        end

      {^port, {:exit_status, 0}} when acknowledged ->
        within(deadline, fn -> PortProcess.join(port, state.port_monitor, deadline) end)

      {^port, {:exit_status, status}} ->
        {:error, failure(state, :invalid_transport_return, %{exit_status: status})}

      {^port, _} ->
        {:error, failure(state, :invalid_frame)}

      {:DOWN, ^owner, :process, _, _} ->
        {:error, failure(state, :owner_closed)}
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> {:error, failure(state, :timeout)}
    end
  end

  defp closing_frame(frame, state, discarded) do
    if Control.decode(frame, :closed, state.generation) == :ok,
      do: {:ack, state},
      else: closing_request(frame, state, discarded)
  end

  defp closing_request(frame, state, discarded) do
    case Wire.decode_request(frame, state.generation) do
      {:ok, request} when request.id > state.last_id and discarded < @limit ->
        {:discard, %{state | last_id: request.id}, discarded + 1}

      {:ok, _} when discarded >= @limit ->
        {:error, failure(state, :response_limit)}

      _ ->
        closing_observation(frame, state, discarded)
    end
  end

  defp closing_probe(frame, %{probe: %{} = probe} = state, discarded) do
    case ClockProbe.decode(frame, state.generation, probe.id) do
      {:ok, _} -> {:discard, %{state | probe: nil}, discarded}
      _ -> {:error, failure(state, :invalid_frame)}
    end
  end

  defp closing_probe(_, state, _), do: {:error, failure(state, :invalid_frame)}

  defp admit_observation(observation, deadline, from, state) do
    id = state.last_observation_id + 1
    started = System.monotonic_time(:millisecond)

    with {:ok, frame} <- Observation.encode(state.generation, id, observation),
         true <- is_integer(deadline),
         {:ok, now} <- sample(state) do
      next = %{state | last_ms: now}
      real_deadline = started + deadline - now

      cond do
        deadline <= now or real_deadline <= System.monotonic_time(:millisecond) ->
          {:reply, {:error, Error.new(:deadline_exceeded)}, next}

        deadline > now + 500 ->
          {:reply, {:error, Error.new(:invalid_timeout)}, next}

        not PortProcess.send_frame(state.port, frame) ->
          {:stop, :normal, {:error, failure(next, :transport_closed)},
           %{next | error: failure(next, :transport_closed)}}

        true ->
          token = make_ref()
          remaining = max(0, real_deadline - System.monotonic_time(:millisecond))
          timer = Process.send_after(self(), {:observation_expired, id, token}, remaining)

          entry = %{
            from: from,
            deadline: deadline,
            real_deadline: real_deadline,
            token: token,
            timer: timer
          }

          {:noreply,
           %{next | last_observation_id: id, observations: Map.put(next.observations, id, entry)}}
      end
    else
      {:error, %Error{code: :invalid_transport_context} = error} ->
        error = Error.with_effect(error, if(state.mutation, do: :unknown, else: :none))
        {:stop, :normal, {:error, error}, %{state | error: error}}

      _ ->
        {:reply, {:error, Error.new(:invalid_frame)}, state}
    end
  end

  defp observation_id(frame) when is_binary(frame) and byte_size(frame) in 1..512 do
    with true <- :binary.last(frame) == 10,
         body = binary_part(frame, 0, byte_size(frame) - 1),
         {:ok, %{"type" => "observation-receipt", "id" => id}} <-
           Wotex.JSON.decode(body,
             max_bytes: 511,
             max_depth: 1,
             max_nodes: 16,
             max_collection_size: 6,
             max_string_bytes: 32
           ),
         true <- is_binary(id) and byte_size(id) in 1..20,
         {value, ""} <- Integer.parse(id),
         true <- value in 1..@uint64 and id == Integer.to_string(value) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp observation_id(_), do: :error

  defp observation_reply(frame, id, state) do
    with %{from: from} = entry when from != nil <- Map.get(state.observations, id),
         {:ok, outcome} <- Observation.decode_receipt(frame, state.generation, id),
         true <- System.monotonic_time(:millisecond) < entry.real_deadline,
         {:ok, now} <- sample(state),
         true <- now < entry.deadline,
         true <- System.monotonic_time(:millisecond) < entry.real_deadline do
      Process.cancel_timer(entry.timer)
      GenServer.reply(from, {:ok, outcome})
      {:ok, %{state | observations: Map.delete(state.observations, id), last_ms: now}}
    else
      {:error, %Error{code: :invalid_transport_context} = error} -> {:error, error, state}
      _ -> {:error, Error.new(:invalid_frame), state}
    end
  end

  defp cancel_observers(state, error) do
    observations =
      Map.new(state.observations, fn {id, entry} ->
        if entry.timer, do: Process.cancel_timer(entry.timer)
        if entry.from, do: GenServer.reply(entry.from, {:error, error})
        {id, %{entry | from: nil, timer: nil}}
      end)

    %{state | observations: observations}
  end

  defp closing_observation(frame, state, discarded) do
    case observation_id(frame) do
      {:ok, id} ->
        with %{from: nil} <- Map.get(state.observations, id),
             {:ok, _} <- Observation.decode_receipt(frame, state.generation, id) do
          {:discard, %{state | observations: Map.delete(state.observations, id)}, discarded}
        else
          _ -> {:error, failure(state, :invalid_frame)}
        end

      :error ->
        closing_probe(frame, state, discarded)
    end
  end

  defp cleanup(%{consumer: _, port: _} = state) do
    cancel_observers(state, Map.get(state, :error) || Error.new(:owner_closed))
    if state.probe, do: Process.cancel_timer(state.probe.timer)
    Consumer.close(state.consumer)
    PortProcess.close(state.port)
  end

  defp cleanup(_), do: :ok

  defp transition({:ok, state}), do: {:noreply, state}

  defp transition({:error, error, state}),
    do:
      {:stop, :normal,
       %{state | error: Error.with_effect(error, if(state.mutation, do: :unknown, else: :none))}}

  defp stop(state, code, details \\ %{}),
    do: {:stop, :normal, %{state | error: failure(state, code, details)}}

  defp failure(state, code, details \\ %{}) do
    Error.new(code, nil, details)
    |> Error.with_effect(if(state.mutation, do: :unknown, else: :none))
  end

  defp call(connection, message) when is_pid(connection) do
    GenServer.call(connection, message, @cleanup * 3 + 100)
  catch
    :exit, _ -> {:error, Error.new(:owner_closed)}
  end

  defp call(_, _), do: {:error, Error.new(:invalid_handle)}
end
