defmodule Wotex.CoAP.Native.Connection do
  @moduledoc """
  Owns the verified native executable during OSCORE session startup and closure.

  `start/1` validates the exact native selection and OSCORE connection values
  before creating a process. The owner launches that executable directly with
  `--custody ABS_DIRECTORY`, accepts only the pinned ready identity, sends one
  bounded `open` command and requires its exact response identity. The process
  retains neither the credential nor its encoded command after startup.

  The process monitors both its configured owner and the caller that created
  it. It owns one generation-bound admission table and consumes its separate
  close-control capability, so a full ordinary reservation set cannot prevent
  cleanup. Admitted request commands run in FIFO order with queue time charged
  to the original deadline. Caller death or an active deadline closes the
  generation, while queued expiry prevents native submission. Native writes
  use `Port.command/3` with `:nosuspend`. Malformed, oversized, truncated,
  duplicate or otherwise unsolicited frames close the generation. Local cleanup
  signals the exact Port process and remains within the WCO-C03 1,000 ms budget.
  An explicit outbound payload is uploaded through correlated begin/chunk/end
  commands under the call deadline before request submission. Unary responses
  may carry an inline payload or one correlated, bounded body event stream.
  The root API selects this owner for explicit OSCORE unary sessions and applies
  discovery's smaller response-body limit before streamed-body allocation.
  Dedicated native observations open report credit, validate inline or streamed
  reports before delivery, serialize cumulative acknowledgments and cancel the
  exact subscription without retaining credentials. Non-secret process markers
  bind Runtime relays to the exact route and subscription generation.
  """

  use GenServer

  alias Wotex.CoAP.{Error, NativeBackend, Security, Subscription}
  alias Wotex.CoAP.Native.{Admission, Body, Command, Report, ReportLedger, Wire}

  @keys [:host, :port, :timeout, :owner, :security, :native_backend]
  @maximum_frame_bytes 131_071
  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @ready_timeout 5_000
  @close_timeout 350
  @cleanup_timeout 1_000
  @native_cleanup_timeout 550
  @maximum_body_bytes 1_048_576
  @maximum_body_chunk_bytes 32_768
  @mutating_methods [:post, :put, :delete]

  @typedoc "Validated startup values for one native generation."
  @type config :: %{
          host: String.t(),
          port: 1..65_535,
          timeout: 1..60_000,
          owner: pid(),
          security: Security.t(),
          native_backend: NativeBackend.t()
        }

  @doc "Starts one explicitly owned native generation and completes its ready/open handshake."
  @spec start(keyword()) :: {:ok, pid()} | {:error, Error.t()}
  def start(options) do
    creator = self()

    with {:ok, config} <- config(options) do
      case GenServer.start(__MODULE__, {creator, config},
             timeout: config.timeout + @cleanup_timeout
           ) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, {:shutdown, %Error{} = error}} ->
          {:error, error}

        {:error, _} ->
          failure(:native_unavailable)
      end
    end
  catch
    :exit, _ -> failure(:native_unavailable)
  end

  @doc "Closes an owned native generation idempotently within the local cleanup budget."
  @spec close(pid()) :: :ok | {:error, Error.t()}
  def close(pid) do
    case identity(pid) do
      {:owned, generation, admission} -> stop(pid, generation, admission)
      :closed -> :ok
      :invalid -> failure(:invalid_session)
    end
  end

  @doc false
  @spec abort(pid()) :: :ok | {:error, Error.t()}
  def abort(pid) do
    case identity(pid) do
      {:owned, _, _} ->
        monitor = Process.monitor(pid)
        Process.unlink(pid)
        if match?({:owned, _, _}, identity(pid)), do: Process.exit(pid, :kill)

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

  @doc "Runs one admitted native request against an already opened generation."
  @spec request(pid(), map(), pos_integer()) :: {:ok, Wotex.CoAP.Message.t()} | {:error, Error.t()}
  def request(pid, parameters, timeout), do: request(pid, parameters, timeout, [])

  @doc false
  @spec request(pid(), map(), pos_integer(), keyword()) ::
          {:ok, Wotex.CoAP.Message.t()} | {:error, Error.t()}
  def request(pid, parameters, timeout, options)
      when is_map(parameters) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = now() + timeout

    case identity(pid) do
      {:owned, generation, admission} ->
        with {:ok, maximum_body_bytes} <- request_options(options),
             :ok <- valid_request(parameters, generation, timeout),
             {:ok, lease} <- admit(admission, pid, generation, deadline) do
          await_request(
            pid,
            admission,
            generation,
            parameters,
            maximum_body_bytes,
            deadline,
            lease
          )
        end

      :closed ->
        failure(:connection_closed)

      :invalid ->
        failure(:invalid_session)
    end
  end

  def request(_, _, timeout, _) when not is_integer(timeout) or timeout not in 1..60_000,
    do: failure(:invalid_timeout)

  def request(_, _, _, _), do: failure(:invalid_request)

  @doc "Establishes one native observation and returns after its first complete report."
  @spec observe(pid(), binary(), pid(), keyword(), pos_integer()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def observe(pid, path, receiver, options, timeout)
      when is_integer(timeout) and timeout in 1..60_000 do
    deadline = now() + timeout

    with {:ok, config} <- observation_options(path, receiver, options) do
      case identity(pid) do
        {:owned, generation, _} ->
          safe_observe(pid, generation, config, deadline, timeout)

        :closed ->
          failure(:connection_closed)

        :invalid ->
          failure(:invalid_session)
      end
    end
  end

  def observe(_, _, _, _, timeout) when not is_integer(timeout) or timeout not in 1..60_000,
    do: failure(:invalid_timeout)

  @doc "Cancels the exact established native observation and closes its generation."
  @spec unobserve(pid(), Subscription.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def unobserve(pid, handle, timeout) when is_integer(timeout) and timeout in 1..60_000 do
    with :ok <- Subscription.validate(handle, pid) do
      case identity(pid) do
        {:owned, generation, _} ->
          safe_unobserve(pid, generation, handle, now() + timeout, timeout)

        :closed ->
          :ok

        :invalid ->
          failure(:invalid_session)
      end
    end
  end

  def unobserve(_, _, timeout) when not is_integer(timeout) or timeout not in 1..60_000,
    do: failure(:invalid_timeout)

  @doc "Validates native startup options and executable identity without starting a Port."
  @spec config(term()) :: {:ok, config()} | {:error, Error.t()}
  def config(options) do
    with {:ok, values} <- options(options, %{}),
         :ok <- host(Map.get(values, :host)),
         :ok <- port(Map.get(values, :port, 5683)),
         :ok <- timeout(Map.get(values, :timeout, 5_000)),
         :ok <- owner(Map.get(values, :owner, self())),
         :ok <- oscore(Map.get(values, :security)),
         {:ok, backend} <- NativeBackend.verify(Map.get(values, :native_backend)) do
      {:ok,
       %{
         host: values.host,
         port: Map.get(values, :port, 5683),
         timeout: Map.get(values, :timeout, 5_000),
         owner: Map.get(values, :owner, self()),
         security: values.security,
         native_backend: backend
       }}
    end
  end

  @impl GenServer
  def init({creator, config}) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(config.owner)
    creator_monitor = if creator == config.owner, do: nil, else: Process.monitor(creator)
    started_at = now()
    deadline = started_at + config.timeout
    generation = :erlang.unique_integer([:positive, :monotonic])

    if generation <= @maximum_counter do
      {:ok, command} = Command.new(generation)

      case open_port(config) do
        {:ok, port, os_pid} ->
          case handshake(
                 port,
                 owner_monitor,
                 creator_monitor,
                 command,
                 config,
                 generation,
                 started_at,
                 deadline
               ) do
            {:ok, command} ->
              admission = Admission.new(generation)
              Process.put(:wotex_coap_owner, {__MODULE__, generation, admission})

              Process.put(
                :wotex_coap_route,
                Map.take(Map.put(config, :creator, creator), [:owner, :creator, :host, :port])
              )

              {:ok,
               %{
                 port: port,
                 os_pid: os_pid,
                 generation: generation,
                 admission: admission,
                 admission_timer: schedule_admission_reap(),
                 command: command,
                 owner_monitor: owner_monitor,
                 creator_monitor: creator_monitor,
                 active: nil,
                 next_body_id: 1,
                 calls: %{},
                 call_order: :queue.new(),
                 caller_monitors: %{},
                 drain_scheduled: false,
                 timeout: config.timeout,
                 observation: nil,
                 buffer: <<>>,
                 cleanup_deadline: nil
               }}

            {:error, %Error{} = error} ->
              startup_failure({port, os_pid}, {:error, error})
          end

        {:error, %Error{} = error} ->
          startup_failure(nil, {:error, error})
      end
    else
      startup_failure(nil, failure(:sequence_exhausted))
    end
  rescue
    _ -> {:stop, {:shutdown, Error.new(:native_unavailable)}}
  end

  @impl GenServer
  def handle_call({:bounded, generation, parameters, deadline, lease}, from, state),
    do: {:noreply, enqueue_call(state, generation, parameters, deadline, lease, from)}

  def handle_call({:observe, generation, config, deadline}, from, state),
    do: begin_observation(state, generation, config, deadline, from)

  def handle_call({:unobserve, generation, handle, deadline}, from, state),
    do: begin_cancellation(state, generation, handle, deadline, from)

  def handle_call(
        {:close_control, generation, deadline, token},
        {caller, _} = from,
        %{active: nil} = state
      )
      when is_integer(generation) and is_integer(deadline) and is_reference(token) do
    remaining = deadline - now()

    cond do
      generation != state.generation or
          not Admission.close_owned?(state.admission, token, caller, deadline) ->
        {:reply, failure(:invalid_session), state}

      remaining <= 0 ->
        stop_with(failure(:timeout), from, %{state | cleanup_deadline: deadline})

      true ->
        timeout = min(@close_timeout, remaining)

        case Command.encode(state.command, :close, %{}, timeout) do
          {:ok, id, line, command} ->
            if write(state.port, line) do
              timer = Process.send_after(self(), {:native_timeout, state.generation, id}, timeout)

              {:noreply,
               %{
                 state
                 | command: command,
                   active: %{from: from, id: id, operation: :close, timer: timer},
                   cleanup_deadline: deadline
               }}
            else
              stop_with(failure(:native_unavailable), from, %{
                state
                | cleanup_deadline: deadline
              })
            end

          :exhausted ->
            stop_with(failure(:sequence_exhausted), from, %{
              state
              | cleanup_deadline: deadline
            })

          :error ->
            stop_with(failure(:native_protocol_error), from, %{
              state
              | cleanup_deadline: deadline
            })
        end
    end
  end

  def handle_call(
        {:close_control, generation, deadline, token},
        {caller, _},
        %{active: %{operation: active_operation}} = state
      )
      when is_integer(generation) and is_integer(deadline) and is_reference(token) do
    cond do
      generation != state.generation or
          not Admission.close_owned?(state.admission, token, caller, deadline) ->
        {:reply, failure(:invalid_session), state}

      active_operation in [:request, :observe, :credit, :cancel] ->
        state = fail_active(state, failure(:connection_closed))
        {:stop, :normal, :ok, %{state | cleanup_deadline: deadline}}

      true ->
        {:reply, failure(:busy), state}
    end
  end

  def handle_call({:close_control, _, _, _}, _, state),
    do: {:reply, failure(:invalid_session), state}

  def handle_call(_, _, state), do: {:reply, failure(:invalid_session), state}

  @impl GenServer
  def handle_info(
        {port, {:data, bytes}},
        %{port: port, active: %{operation: :request}} = state
      )
      when is_binary(bytes),
      do: handle_request_bytes(state, bytes)

  def handle_info(
        {port, {:data, bytes}},
        %{port: port, active: %{operation: operation}} = state
      )
      when operation in [:observe, :credit, :cancel] and is_binary(bytes),
      do: handle_observation_bytes(state, bytes)

  def handle_info(
        {port, {:data, bytes}},
        %{port: port, active: nil, observation: %{}} = state
      )
      when is_binary(bytes),
      do: handle_observation_bytes(state, bytes)

  def handle_info({port, {:data, bytes}}, %{port: port, active: active} = state)
      when is_binary(bytes) and not is_nil(active) do
    case receive_chunk(state.buffer, bytes) do
      {:line, line, <<>>} ->
        handle_active_line(line, %{state | buffer: <<>>})

      {:more, buffer} ->
        {:noreply, %{state | buffer: buffer}}

      _ ->
        stop_with(failure(:native_protocol_error), state)
    end
  end

  def handle_info({port, {:data, _}}, %{port: port} = state),
    do: stop_with(failure(:native_protocol_error), state)

  # A worker ends its own generation after a terminal exchange failure. A clean
  # exit with no partial frame therefore completes a racing close and reports a
  # closed connection to an active request; other exits remain protocol errors.
  def handle_info(
        {port, {:exit_status, 0}},
        %{port: port, buffer: <<>>, active: %{operation: :close} = active} = state
      ) do
    Process.cancel_timer(active.timer)
    GenServer.reply(active.from, :ok)

    {:stop, :normal,
     %{state | active: nil, cleanup_deadline: state.cleanup_deadline || now() + @cleanup_timeout}}
  end

  def handle_info(
        {port, {:exit_status, 0}},
        %{port: port, buffer: <<>>, active: %{operation: :request}} = state
      ),
      do: stop_with(failure(:connection_closed), state)

  def handle_info({port, {:exit_status, _}}, %{port: port, active: %{}} = state),
    do: stop_with(failure(:native_protocol_error), state)

  def handle_info({port, {:exit_status, _}}, %{port: port, buffer: <<>>} = state),
    do: stop_with(failure(:native_unavailable), state)

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: stop_with(failure(:native_unavailable), state)

  def handle_info({:DOWN, monitor, :process, _, _}, %{owner_monitor: monitor} = state),
    do: stop_with(failure(:connection_closed), state)

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{creator_monitor: monitor} = state
      )
      when is_reference(monitor),
      do: stop_with(failure(:connection_closed), state)

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{observation: %{receiver_monitor: monitor}} = state
      ),
      do: stop_observation(state, Error.new(:connection_closed), false)

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{observation: %{caller_monitor: monitor}} = state
      )
      when is_reference(monitor),
      do: stop_observation(state, Error.new(:connection_closed), false)

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Map.fetch(state.caller_monitors, monitor) do
      {:ok, lease} ->
        case state.active do
          %{operation: :request, lease: ^lease} ->
            state = finish_call(state, lease, failure(:connection_closed))
            {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}

          _ ->
            {:noreply, continue_after_call(state, lease, failure(:connection_closed))}
        end

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:native_timeout, generation, id},
        %{generation: generation, active: %{id: id}} = state
      ),
      do: stop_with(failure(:timeout), state)

  def handle_info(
        {:observation_deadline, reference},
        %{observation: %{deadline_reference: reference}} = state
      ),
      do: stop_observation(state, Error.new(:timeout))

  def handle_info(:drain_calls, %{active: nil} = state), do: drain_calls(state)
  def handle_info(:drain_calls, state), do: {:noreply, %{state | drain_scheduled: false}}

  def handle_info({:expire_call, lease}, state) do
    case state.active do
      %{operation: :request, lease: ^lease} ->
        state = finish_call(state, lease, failure(:timeout))
        {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}

      _ ->
        {:noreply, continue_after_call(state, lease, failure(:timeout))}
    end
  end

  def handle_info({:reap_admission, token}, state) do
    case reap_admission(state, token) do
      {:ok, state} -> {:noreply, state}
      {:error, code, state} -> stop_with(failure(code), state)
    end
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
  def terminate(_, state) when is_map(state) do
    if timer = Map.get(state, :admission_timer), do: Process.cancel_timer(elem(timer, 0))

    state = fail_active(state, failure(:connection_closed))
    state = finish_observation(state, Error.new(:connection_closed), true)

    state =
      Enum.reduce(Map.keys(state.calls), state, fn lease, acc ->
        finish_call(acc, lease, failure(:connection_closed))
      end)

    deadline = state.cleanup_deadline || now() + @cleanup_timeout
    close_port(state.port, state.os_pid, deadline)
    :ok
  end

  defp begin_observation(state, generation, config, deadline, from) do
    remaining = deadline - now()

    cond do
      generation != state.generation ->
        {:reply, failure(:invalid_session), state}

      not is_nil(state.observation) ->
        {:reply, failure(:observation_active), state}

      not is_nil(state.active) or map_size(state.calls) > 0 ->
        {:reply, failure(:busy), state}

      remaining <= 0 ->
        {:reply, failure(:timeout), state}

      true ->
        dispatch_observe(state, config, deadline, from)
    end
  end

  defp dispatch_observe(state, config, deadline, {caller, _} = from) do
    remaining = deadline - now()

    case Command.encode(state.command, :observe, config.parameters, remaining) do
      {:ok, id, line, command} ->
        if write(state.port, line) do
          {:ok, handle} = Subscription.new(self(), make_ref(), make_ref())
          timer = Process.send_after(self(), {:native_timeout, state.generation, id}, remaining)

          observation = %{
            phase: :opening,
            from: from,
            cancel_from: nil,
            caller_monitor: Process.monitor(caller),
            receiver: config.receiver,
            receiver_monitor: Process.monitor(config.receiver),
            max_queue_length: config.max_queue_length,
            handle: handle,
            subscription_id: nil,
            wire_generation: nil,
            ledger: nil,
            body: Body.new(),
            bodies: %{},
            deadline: deadline,
            deadline_timer: nil,
            deadline_reference: nil
          }

          {:noreply,
           %{
             state
             | command: command,
               observation: observation,
               active: %{operation: :observe, id: id, timer: timer}
           }}
        else
          {:stop, :normal, failure(:native_unavailable),
           %{
             state
             | cleanup_deadline: now() + @cleanup_timeout
           }}
        end

      :exhausted ->
        {:stop, :normal, failure(:sequence_exhausted),
         %{
           state
           | cleanup_deadline: now() + @cleanup_timeout
         }}

      :error ->
        {:reply, failure(:invalid_observation_options), state}
    end
  end

  defp begin_cancellation(state, generation, handle, deadline, from) do
    observation = state.observation

    cond do
      generation != state.generation ->
        {:reply, failure(:invalid_session), state}

      is_nil(observation) or observation.handle != handle ->
        {:reply, failure(:invalid_subscription), state}

      match?(%{operation: :cancel}, state.active) ->
        join_cancellation(state, deadline, from)

      match?(%{operation: :credit}, state.active) and observation.phase == :active and
          deadline > now() ->
        credit = state.active
        Process.cancel_timer(credit.timer)

        dispatch_cancel(
          %{state | active: nil},
          deadline,
          [from],
          Map.take(credit, [:id, :ack_seq])
        )

      not is_nil(state.active) ->
        {:reply, failure(:busy), state}

      observation.phase != :active ->
        {:reply, failure(:observation_active), state}

      deadline <= now() ->
        {:reply, failure(:timeout), state}

      true ->
        dispatch_cancel(state, deadline, [from])
    end
  end

  defp join_cancellation(%{observation: observation} = state, deadline, from) do
    callers = observation.cancel_from || []

    if deadline > now() and length(callers) < 64,
      do: {:noreply, %{state | observation: %{observation | cancel_from: [from | callers]}}},
      else: {:reply, failure(:busy), state}
  end

  defp dispatch_cancel(state, deadline, callers, ignored_credit \\ nil) do
    observation = %{state.observation | phase: :canceling, cancel_from: callers}
    state = %{state | observation: observation}

    parameters = %{
      subscription_id: observation.subscription_id,
      generation: observation.wire_generation
    }

    remaining = deadline - now()

    case Command.encode(state.command, :cancel, parameters, remaining) do
      {:ok, id, line, command} ->
        if write(state.port, line) do
          timer = Process.send_after(self(), {:native_timeout, state.generation, id}, remaining)

          active = %{
            operation: :cancel,
            id: id,
            timer: timer,
            ignored_credit: ignored_credit
          }

          {:noreply, %{state | command: command, observation: observation, active: active}}
        else
          stop_observation(state, Error.new(:native_unavailable))
        end

      :exhausted ->
        stop_observation(state, Error.new(:sequence_exhausted))

      :error ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp open_parameters(config, generation) do
    %{
      host: config.host,
      port: config.port,
      generation: generation,
      security: config.security
    }
  end

  defp handshake(
         port,
         owner_monitor,
         creator_monitor,
         command,
         config,
         generation,
         started_at,
         deadline
       ) do
    with :ok <-
           await_ready(
             port,
             owner_monitor,
             creator_monitor,
             min(deadline, started_at + @ready_timeout)
           ),
         remaining when remaining > 0 <- deadline - now(),
         {:ok, id, line, command} <-
           Command.encode(command, :open, open_parameters(config, generation), remaining),
         true <- write(port, line),
         {:ok, nil} <- await_response(port, owner_monitor, creator_monitor, :open, id, deadline) do
      {:ok, command}
    else
      :error -> failure(:native_protocol_error)
      :exhausted -> failure(:sequence_exhausted)
      false -> failure(:native_unavailable)
      remaining when is_integer(remaining) -> failure(:timeout)
      {:error, %Error{} = error} -> {:error, error}
      _ -> failure(:native_unavailable)
    end
  end

  defp open_port(config) do
    executable = config.native_backend.executable
    directory = config.security.context_store

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [
          :binary,
          :exit_status,
          :use_stdio,
          {:args, [~c"--custody", String.to_charlist(directory)]}
        ]
      )

    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) and os_pid > 0 ->
        {:ok, port, os_pid}

      _ ->
        close_if_open(port)
        failure(:native_unavailable)
    end
  rescue
    _ -> failure(:native_unavailable)
  end

  defp await_ready(port, owner_monitor, creator_monitor, deadline) do
    with {:ok, line} <- await_line(port, owner_monitor, creator_monitor, deadline),
         {:ok, frame} <- Wire.frame(line),
         {:ok, _} <- Wire.ready(frame),
         do: :ok
  end

  defp await_response(port, owner_monitor, creator_monitor, operation, id, deadline) do
    with {:ok, line} <- await_line(port, owner_monitor, creator_monitor, deadline),
         {:ok, frame} <- Wire.frame(line),
         do: Wire.response(operation, frame, id)
  end

  defp await_line(port, owner_monitor, creator_monitor, deadline, buffer \\ <<>>) do
    remaining = deadline - now()

    if remaining <= 0 do
      failure(:timeout)
    else
      result =
        receive do
          {^port, {:data, bytes}} when is_binary(bytes) ->
            case receive_chunk(buffer, bytes) do
              {:line, line, <<>>} -> {:ok, line}
              {:line, _, _} -> failure(:native_protocol_error)
              {:more, next} -> await_line(port, owner_monitor, creator_monitor, deadline, next)
              :error -> failure(:native_protocol_error)
            end

          {^port, {:exit_status, _}} ->
            failure(:native_protocol_error)

          {:DOWN, ^owner_monitor, :process, _, _} ->
            failure(:connection_closed)

          {:DOWN, ^creator_monitor, :process, _, _} when is_reference(creator_monitor) ->
            failure(:connection_closed)
        after
          remaining -> failure(:timeout)
        end

      if now() <= deadline, do: result, else: failure(:timeout)
    end
  end

  defp receive_chunk(buffer, bytes) do
    case :binary.match(bytes, "\n") do
      {size, 1} when byte_size(buffer) + size <= @maximum_frame_bytes ->
        line = buffer <> binary_part(bytes, 0, size)
        rest_size = byte_size(bytes) - size - 1
        rest = binary_part(bytes, size + 1, rest_size)

        if byte_size(line) > 0 and :binary.match(line, "\r") == :nomatch,
          do: {:line, line, rest},
          else: :error

      :nomatch when byte_size(buffer) + byte_size(bytes) <= @maximum_frame_bytes ->
        {:more, buffer <> bytes}

      _ ->
        :error
    end
  end

  defp write(port, line) do
    Port.command(port, line, [:nosuspend])
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp handle_active_line(line, %{active: %{operation: :close} = active} = state) do
    result =
      with {:ok, frame} <- Wire.frame(line),
           do: Wire.response(:close, frame, active.id)

    Process.cancel_timer(active.timer)
    GenServer.reply(active.from, close_result(result))
    {:stop, :normal, %{state | active: nil}}
  end

  defp handle_observation_bytes(state, bytes) do
    case receive_chunk(state.buffer, bytes) do
      {:line, line, rest} ->
        case handle_observation_line(line, %{state | buffer: <<>>}) do
          {:noreply, state} when rest != <<>> -> handle_observation_bytes(state, rest)
          result -> result
        end

      {:more, buffer} ->
        {:noreply, %{state | buffer: buffer}}

      :error ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp handle_observation_line(line, state) do
    case Wire.frame(line) do
      {:ok, frame} ->
        if observation_event?(frame),
          do: handle_report_frame(frame, byte_size(line) + 1, state),
          else: handle_observation_response(frame, state)

      {:error, %Error{}} ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp handle_observation_response(frame, %{active: %{operation: :observe} = active} = state) do
    result = Wire.response(:observe, frame, active.id)
    Process.cancel_timer(active.timer)

    case result do
      {:ok, %{subscription_id: subscription_id, generation: generation}} ->
        {:ok, ledger} = ReportLedger.new(subscription_id, generation)

        observation = %{
          state.observation
          | phase: :opening_credit,
            subscription_id: subscription_id,
            wire_generation: generation,
            ledger: ledger
        }

        state = %{state | active: nil, observation: observation}
        dispatch_next_credit(state, :initial, observation.deadline)

      {:error, %Error{} = error} ->
        stop_observation(%{state | active: nil}, error)
    end
  end

  defp handle_observation_response(frame, %{active: %{operation: :credit} = active} = state) do
    result = Wire.response(:credit, frame, active.id)
    Process.cancel_timer(active.timer)

    with {:ok, nil} <- result,
         {:ok, ledger} <- ReportLedger.credit_accepted(state.observation.ledger, active.ack_seq) do
      observation = %{state.observation | ledger: ledger}
      state = %{state | active: nil, observation: observation}

      if active.phase == :initial,
        do: begin_report_delivery(state),
        else: dispatch_next_credit(state, :reports, now() + state.timeout)
    else
      {:error, %Error{} = error} -> stop_observation(%{state | active: nil}, error)
      _ -> stop_observation(%{state | active: nil}, Error.new(:native_protocol_error))
    end
  end

  defp handle_observation_response(frame, %{active: %{operation: :cancel} = active} = state) do
    ignored_credit = active.ignored_credit

    if ignored_credit && Map.get(frame, "id") == ignored_credit.id do
      active = %{active | ignored_credit: nil}
      state = %{state | active: active}

      case Wire.response(:credit, frame, ignored_credit.id) do
        {:ok, nil} ->
          case ReportLedger.credit_accepted(
                 state.observation.ledger,
                 ignored_credit.ack_seq
               ) do
            {:ok, ledger} ->
              {:noreply, %{state | observation: %{state.observation | ledger: ledger}}}

            :error ->
              stop_observation(state, Error.new(:native_protocol_error))
          end

        {:error, %Error{code: :native_protocol_error} = error} ->
          stop_observation(state, error)

        {:error, %Error{}} ->
          {:noreply, state}
      end
    else
      result = Wire.response(:cancel, frame, active.id)
      Process.cancel_timer(active.timer)

      case result do
        {:ok, nil} -> complete_cancellation(%{state | active: nil})
        {:error, %Error{} = error} -> stop_observation(%{state | active: nil}, error)
      end
    end
  end

  defp handle_observation_response(_, state),
    do: stop_observation(state, Error.new(:native_protocol_error))

  defp handle_report_frame(_, _, %{observation: %{phase: phase}} = state)
       when phase in [:opening, :opening_credit],
       do: stop_observation(state, Error.new(:native_protocol_error))

  defp handle_report_frame(frame, encoded_bytes, %{observation: %{phase: :canceling}} = state) do
    cond do
      body_event?(frame) ->
        case account_report_body(state.observation, frame, encoded_bytes) do
          {:ok, observation} -> {:noreply, %{state | observation: observation}}
          :error -> stop_observation(state, Error.new(:native_protocol_error))
        end

      Map.get(frame, "event") == "report" ->
        case consume_complete_report(state.observation, frame, encoded_bytes) do
          {:ok, _, observation} -> {:noreply, %{state | observation: observation}}
          :error -> stop_observation(state, Error.new(:native_protocol_error))
        end

      Map.get(frame, "event") == "error" ->
        handle_terminal_report(frame, state)

      true ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp handle_report_frame(frame, encoded_bytes, state) do
    cond do
      body_event?(frame) -> handle_report_body(frame, encoded_bytes, state)
      Map.get(frame, "event") == "report" -> handle_complete_report(frame, encoded_bytes, state)
      Map.get(frame, "event") == "error" -> handle_terminal_report(frame, state)
    end
  end

  defp handle_report_body(frame, encoded_bytes, state) do
    case account_report_body(state.observation, frame, encoded_bytes) do
      {:ok, observation} ->
        dispatch_next_credit(%{state | observation: observation}, :reports, now() + state.timeout)

      :error ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp account_report_body(observation, frame, encoded_bytes) do
    with true <- map_size(observation.bodies) == 0,
         {:ok, sequence, event} <-
           Report.body_event(frame, observation.subscription_id, observation.wire_generation),
         {:ok, ledger} <-
           ReportLedger.account_frame(
             observation.ledger,
             observation.subscription_id,
             observation.wire_generation,
             sequence,
             encoded_bytes
           ),
         {:ok, body} <- Body.push(observation.body, event),
         {:ok, body, bodies} <- complete_report_body(body, observation.bodies, event),
         do: {:ok, %{observation | ledger: ledger, body: body, bodies: bodies}},
         else: (_ -> :error)
  end

  defp complete_report_body(body, bodies, %{"event" => "body_end", "body_id" => id}) do
    with {:ok, bytes, body} <- Body.take(body, id),
         do: {:ok, body, Map.put(bodies, id, bytes)}
  end

  defp complete_report_body(body, bodies, _), do: {:ok, body, bodies}

  defp handle_complete_report(frame, encoded_bytes, state) do
    observation = state.observation

    with :ok <- receiver_capacity(observation),
         {:ok, report, observation} <-
           consume_complete_report(observation, frame, encoded_bytes) do
      send(
        observation.receiver,
        {:wotex_coap, observation.handle.reference, {:ok, report.message, report.metadata}}
      )

      observation = establish_observation(observation)

      dispatch_next_credit(%{state | observation: observation}, :reports, now() + state.timeout)
    else
      {:error, %Error{code: :receiver_overflow}} ->
        stop_observation(state, Error.new(:receiver_overflow))

      {:error, %Error{} = error} ->
        stop_observation(state, error)

      _ ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp consume_complete_report(observation, frame, encoded_bytes) do
    token = make_ref()

    with :ok <- report_body_reference(frame, observation.bodies),
         {:ok, report} <-
           Report.decode(
             frame,
             observation.subscription_id,
             observation.wire_generation,
             observation.bodies
           ),
         {:ok, ledger} <-
           ReportLedger.retain_report(
             observation.ledger,
             observation.subscription_id,
             observation.wire_generation,
             report.report_seq,
             encoded_bytes,
             token
           ),
         {:ok, ledger} <-
           ReportLedger.consume_report(
             ledger,
             observation.subscription_id,
             observation.wire_generation,
             report.report_seq,
             token
           ) do
      {:ok, report, %{observation | ledger: ledger, body: Body.new(), bodies: %{}}}
    else
      _ -> :error
    end
  end

  defp handle_terminal_report(frame, state) do
    case Report.terminal(
           frame,
           state.observation.subscription_id,
           state.observation.wire_generation
         ) do
      {:error, %Error{code: :native_protocol_error}} ->
        stop_observation(state, Error.new(:native_protocol_error))

      {:error, %Error{} = error} ->
        stop_observation(state, error)
    end
  end

  defp report_body_reference(
         %{"value" => %{"body_id" => id}},
         bodies
       )
       when map_size(bodies) == 1 do
    if Map.has_key?(bodies, id), do: :ok, else: failure(:native_protocol_error)
  end

  defp report_body_reference(%{"value" => value}, bodies)
       when is_map(value) and map_size(bodies) == 0 do
    if Map.has_key?(value, "body_id"), do: failure(:native_protocol_error), else: :ok
  end

  defp report_body_reference(_, _), do: failure(:native_protocol_error)

  defp observation_event?(%{"event" => event})
       when event in ["body_begin", "body_chunk", "body_end", "report", "error"],
       do: true

  defp observation_event?(_), do: false

  defp dispatch_next_credit(state, phase, deadline) do
    case ReportLedger.next_credit(state.observation.ledger) do
      {:ok, nil, ledger} ->
        {:noreply, %{state | observation: %{state.observation | ledger: ledger}}}

      {:ok, parameters, ledger} ->
        with remaining when remaining > 0 <- deadline - now(),
             {:ok, id, line, command} <-
               Command.encode(state.command, :credit, parameters, remaining),
             true <- write(state.port, line) do
          timer = Process.send_after(self(), {:native_timeout, state.generation, id}, remaining)

          {:noreply,
           %{
             state
             | command: command,
               observation: %{state.observation | ledger: ledger},
               active: %{
                 operation: :credit,
                 phase: phase,
                 id: id,
                 ack_seq: parameters.ack_seq,
                 timer: timer
               }
           }}
        else
          remaining when is_integer(remaining) ->
            stop_observation(state, Error.new(:timeout))

          false ->
            stop_observation(state, Error.new(:native_unavailable))

          :exhausted ->
            stop_observation(state, Error.new(:sequence_exhausted))

          :error ->
            stop_observation(state, Error.new(:native_protocol_error))
        end

      :error ->
        stop_observation(state, Error.new(:native_protocol_error))
    end
  end

  defp begin_report_delivery(state) do
    remaining = state.observation.deadline - now()

    if remaining > 0 do
      reference = make_ref()
      timer = Process.send_after(self(), {:observation_deadline, reference}, remaining)

      observation = %{
        state.observation
        | phase: :registering,
          deadline_timer: timer,
          deadline_reference: reference
      }

      {:noreply, %{state | observation: observation}}
    else
      stop_observation(state, Error.new(:timeout))
    end
  end

  defp establish_observation(%{phase: :registering} = observation) do
    if observation.deadline_timer, do: Process.cancel_timer(observation.deadline_timer)
    Process.put(:wotex_coap_subscription, {__MODULE__, observation.handle.generation})
    GenServer.reply(observation.from, {:ok, observation.handle})
    Process.demonitor(observation.caller_monitor, [:flush])

    %{
      observation
      | phase: :active,
        from: nil,
        caller_monitor: nil,
        deadline_timer: nil,
        deadline_reference: nil
    }
  end

  defp establish_observation(observation), do: observation

  defp receiver_capacity(observation) do
    case Process.info(observation.receiver, :message_queue_len) do
      {:message_queue_len, count} when count < observation.max_queue_length -> :ok
      nil -> failure(:connection_closed)
      _ -> failure(:receiver_overflow)
    end
  end

  defp complete_cancellation(state) do
    Enum.each(state.observation.cancel_from || [], &GenServer.reply(&1, :ok))
    state = clear_observation(state)
    {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
  end

  defp stop_observation(state, %Error{} = error, notify \\ true) do
    state = finish_observation(state, error, notify)
    {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
  end

  defp finish_observation(%{observation: nil} = state, _, _), do: state

  defp finish_observation(%{observation: observation} = state, %Error{} = error, notify) do
    if observation.from, do: GenServer.reply(observation.from, {:error, error})

    if observation.cancel_from,
      do: Enum.each(observation.cancel_from, &GenServer.reply(&1, {:error, error}))

    if notify and is_nil(observation.from) and Process.alive?(observation.receiver) do
      send(
        observation.receiver,
        {:wotex_coap, observation.handle.reference, {:error, error}}
      )
    end

    clear_observation(state)
  end

  defp clear_observation(%{observation: observation} = state) do
    Process.delete(:wotex_coap_subscription)
    if observation.deadline_timer, do: Process.cancel_timer(observation.deadline_timer)
    if observation.caller_monitor, do: Process.demonitor(observation.caller_monitor, [:flush])
    if observation.receiver_monitor, do: Process.demonitor(observation.receiver_monitor, [:flush])

    case state.active do
      %{timer: timer} when is_reference(timer) -> Process.cancel_timer(timer)
      _ -> :ok
    end

    %{state | observation: nil, active: nil, buffer: <<>>}
  end

  defp handle_request_bytes(state, bytes) do
    case receive_chunk(state.buffer, bytes) do
      {:line, line, rest} ->
        handle_request_line(line, rest, %{state | buffer: <<>>})

      {:more, buffer} ->
        {:noreply, %{state | buffer: buffer}}

      :error ->
        stop_with(failure(:native_protocol_error), state)
    end
  end

  defp handle_request_line(line, rest, %{active: active} = state) do
    if now() >= Map.fetch!(state.calls, active.lease).deadline do
      state = finish_call(state, active.lease, failure(:timeout))
      {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
    else
      case Wire.frame(line) do
        {:ok, frame} ->
          handle_request_frame(frame, rest, state)

        {:error, %Error{}} = result ->
          stop_request_protocol(state, result)
      end
    end
  end

  defp handle_request_frame(frame, rest, %{active: %{phase: :response}} = state) do
    if body_event?(frame),
      do: handle_request_body(frame, rest, state),
      else: handle_request_response(frame, rest, state)
  end

  defp handle_request_frame(frame, rest, %{active: %{phase: phase}} = state)
       when phase in [:body_begin, :body_chunk, :body_end],
       do: handle_upload_response(frame, rest, state)

  defp handle_request_frame(_, _, state),
    do: stop_request_protocol(state, failure(:native_protocol_error))

  defp handle_request_body(frame, rest, %{active: active} = state) do
    maximum_body_bytes = Map.fetch!(state.calls, active.lease).maximum_body_bytes

    with true <- map_size(active.bodies) == 0,
         {:ok, event} <- Report.body_event(frame, active.id),
         :ok <- body_limit(event, maximum_body_bytes),
         {:ok, body} <- Body.push(active.body, event),
         {:ok, active} <- complete_request_body(active, body, event) do
      state = %{state | active: active}

      if rest == <<>>,
        do: {:noreply, state},
        else: handle_request_bytes(state, rest)
    else
      {:error, %Error{code: :body_limit}} = result -> stop_request_protocol(state, result)
      _ -> stop_request_protocol(state, failure(:native_protocol_error))
    end
  end

  defp complete_request_body(active, body, %{"event" => "body_end", "body_id" => id}) do
    with {:ok, bytes, body} <- Body.take(body, id) do
      {:ok, %{active | body: body, bodies: %{id => bytes}}}
    end
  end

  defp complete_request_body(active, body, _), do: {:ok, %{active | body: body}}

  defp handle_request_response(frame, <<>>, %{active: %{lease: lease} = active} = state) do
    result =
      with :ok <- response_body_reference(frame, active.bodies),
           do: Wire.response(:request, frame, active.id, active.bodies)

    case result do
      {:ok, _} = result ->
        {:noreply, continue_after_call(state, lease, result)}

      {:error, %Error{code: :native_protocol_error}} = result ->
        stop_request_protocol(state, result)

      {:error, %Error{}} = result ->
        {:noreply, continue_after_call(state, lease, result)}
    end
  end

  defp handle_request_response(_, _, state),
    do: stop_request_protocol(state, failure(:native_protocol_error))

  defp handle_upload_response(frame, <<>>, %{active: active} = state) do
    case Wire.response(active.phase, frame, active.id) do
      {:ok, nil} -> continue_upload(state)
      {:error, %Error{}} = result -> stop_request_protocol(state, result)
    end
  end

  defp handle_upload_response(_, _, state),
    do: stop_request_protocol(state, failure(:native_protocol_error))

  defp continue_upload(%{active: %{phase: :body_begin, payload: <<>>} = active} = state),
    do: dispatch_body_end(state, active)

  defp continue_upload(%{active: %{phase: :body_begin} = active} = state),
    do: dispatch_body_chunk(state, active)

  defp continue_upload(%{active: %{phase: :body_chunk} = active} = state) do
    if active.offset == byte_size(active.payload),
      do: dispatch_body_end(state, active),
      else: dispatch_body_chunk(state, active)
  end

  defp continue_upload(%{active: %{phase: :body_end} = active} = state),
    do: dispatch_uploaded_request(state, active)

  defp response_body_reference(%{"ok" => true, "result" => result}, bodies)
       when map_size(bodies) == 1 and is_map(result) do
    [{id, _}] = Map.to_list(bodies)
    if Map.get(result, "body_id") == id, do: :ok, else: failure(:native_protocol_error)
  end

  defp response_body_reference(%{"ok" => false}, bodies) when map_size(bodies) == 0, do: :ok
  defp response_body_reference(%{"ok" => true}, bodies) when map_size(bodies) == 0, do: :ok
  defp response_body_reference(_, _), do: failure(:native_protocol_error)

  defp stop_request_protocol(%{active: %{lease: lease}} = state, result) do
    state = finish_call(state, lease, result)
    {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
  end

  defp body_event?(%{"event" => event}) when event in ["body_begin", "body_chunk", "body_end"],
    do: true

  defp body_event?(_), do: false

  defp close_result({:ok, nil}), do: :ok
  defp close_result({:error, %Error{}} = result), do: result

  defp valid_request(parameters, generation, timeout) do
    with {:ok, request} <- request_parameters(parameters, "body"),
         {:ok, command} <- Command.new(generation),
         {:ok, _, _, _} <- Command.encode(command, :request, request, timeout),
         do: :ok,
         else: (_ -> failure(:invalid_request))
  end

  defp request_parameters(parameters, body_id) do
    allowed = [:method, :path, :confirmable, :accept, :content_format, :payload]

    with true <- Map.keys(parameters) -- allowed == [],
         :ok <- valid_payload(parameters) do
      request = Map.delete(parameters, :payload)

      if Map.has_key?(parameters, :payload),
        do: {:ok, Map.put(request, :body_id, body_id)},
        else: {:ok, request}
    else
      _ -> :error
    end
  end

  defp valid_payload(parameters) do
    case Map.fetch(parameters, :payload) do
      :error -> :ok
      {:ok, payload} when is_binary(payload) and byte_size(payload) <= @maximum_body_bytes -> :ok
      _ -> :error
    end
  end

  defp observation_options(path, receiver, options) do
    with {:ok, values} <- observation_values(options, %{}),
         true <- is_pid(receiver) and node(receiver) == node() and Process.alive?(receiver),
         {:ok, _} <- Wotex.CoAP.message(%{method: :get, path: path}),
         true <- is_boolean(Map.get(values, :renew, true)),
         true <- is_boolean(Map.get(values, :confirmable, true)),
         true <- Map.get(values, :observation_kind, :property) in [:property, :event],
         true <-
           is_integer(Map.get(values, :max_queue_length, 1000)) and
             Map.get(values, :max_queue_length, 1000) in 1..10_000,
         true <-
           is_nil(Map.get(values, :accept)) or
             (is_integer(Map.get(values, :accept)) and Map.get(values, :accept) in 0..65_535) do
      parameters = %{
        path: path,
        confirmable: Map.get(values, :confirmable, true),
        observation_kind: Map.get(values, :observation_kind, :property),
        renew: Map.get(values, :renew, true)
      }

      parameters =
        if is_nil(Map.get(values, :accept)),
          do: parameters,
          else: Map.put(parameters, :accept, values.accept)

      {:ok,
       %{
         parameters: parameters,
         receiver: receiver,
         max_queue_length: Map.get(values, :max_queue_length, 1000)
       }}
    else
      _ -> failure(:invalid_observation_options)
    end
  end

  defp observation_values([], values), do: {:ok, values}

  defp observation_values([{key, value} | rest], values)
       when key in [:renew, :max_queue_length, :confirmable, :accept, :observation_kind] and
              not is_map_key(values, key),
       do: observation_values(rest, Map.put(values, key, value))

  defp observation_values(_, _), do: failure(:invalid_observation_options)

  defp safe_observe(pid, generation, config, deadline, timeout) do
    GenServer.call(pid, {:observe, generation, config, deadline}, timeout + 100)
  catch
    :exit, {:timeout, _} -> failure(:timeout)
    :exit, _ -> failure(:connection_closed)
  end

  defp safe_unobserve(pid, generation, handle, deadline, timeout) do
    case GenServer.call(pid, {:unobserve, generation, handle, deadline}, timeout + 100) do
      :ok -> await_stop(pid, deadline, :ok)
      result -> result
    end
  catch
    :exit, {:timeout, _} -> failure(:timeout)
    :exit, _ -> if(Process.alive?(pid), do: failure(:connection_closed), else: :ok)
  end

  defp admit(admission, pid, generation, deadline) do
    case Admission.acquire(admission, pid, generation, deadline) do
      {:ok, lease} -> {:ok, lease}
      {:error, :busy} -> failure(:busy)
      {:error, :invalid_handle} -> failure(:invalid_session)
      {:error, :transport_closed} -> failure(:connection_closed)
    end
  end

  defp await_request(
         pid,
         admission,
         generation,
         parameters,
         maximum_body_bytes,
         deadline,
         lease
       ) do
    remaining = deadline - now()

    if remaining > 0 do
      GenServer.call(
        pid,
        {:bounded, generation, {parameters, maximum_body_bytes}, deadline, lease},
        remaining + 100
      )
    else
      Admission.release(admission, lease)
      failure(:timeout)
    end
  catch
    :exit, {:timeout, _} -> request_call_failure(:timeout, parameters, lease)
    :exit, _ -> request_call_failure(:connection_closed, parameters, lease)
  end

  defp request_call_failure(code, parameters, lease) do
    error = Error.new(code)

    if mutating?(parameters) and Admission.cancel_unsubmitted(lease) == :submitted,
      do: {:error, Error.with_effect(error, :unknown)},
      else: {:error, error}
  end

  defp enqueue_call(
         state,
         generation,
         parameters,
         deadline,
         {slot, token} = lease,
         {caller, _} = from
       )
       when is_integer(deadline) and slot in 1..64 and is_reference(token) do
    case admission_error(state, generation, parameters, deadline, lease, caller) do
      nil -> put_call(state, parameters, deadline, lease, caller, from)
      code -> reject_call(state, lease, from, code)
    end
  end

  defp enqueue_call(state, _, _, _, _, from) do
    GenServer.reply(from, failure(:invalid_session))
    state
  end

  defp reject_call(state, lease, from, code) do
    Admission.release(state.admission, lease)
    GenServer.reply(from, failure(code))
    state
  end

  defp admission_error(state, generation, parameters, deadline, lease, caller) do
    cond do
      generation != state.generation ->
        :invalid_session

      not Admission.owned?(state.admission, lease, caller, deadline) ->
        if(deadline <= now(), do: :timeout, else: :invalid_session)

      Map.has_key?(state.calls, lease) ->
        :invalid_session

      true ->
        call_state_error(state, parameters, deadline, caller)
    end
  end

  defp call_state_error(state, parameters, deadline, caller) do
    cond do
      Admission.closing?(state.admission) -> :connection_closed
      not Process.alive?(caller) or deadline <= now() -> :timeout
      not is_nil(state.observation) -> :observation_active
      bounded_call(parameters) == :error -> :invalid_request
      true -> nil
    end
  end

  defp put_call(state, parameters, deadline, lease, caller, from) do
    {:ok, parameters, maximum_body_bytes} = bounded_call(parameters)
    monitor = Process.monitor(caller)
    timer = Process.send_after(self(), {:expire_call, lease}, max(deadline - now(), 0))

    call = %{
      parameters: parameters,
      maximum_body_bytes: maximum_body_bytes,
      deadline: deadline,
      from: from,
      monitor: monitor,
      timer: timer
    }

    %{
      state
      | calls: Map.put(state.calls, lease, call),
        call_order: :queue.in(lease, state.call_order),
        caller_monitors: Map.put(state.caller_monitors, monitor, lease)
    }
    |> schedule_drain()
  end

  defp schedule_drain(%{active: nil, drain_scheduled: false} = state) do
    if :queue.is_empty(state.call_order) do
      state
    else
      send(self(), :drain_calls)
      %{state | drain_scheduled: true}
    end
  end

  defp schedule_drain(state), do: state

  defp drain_calls(state) do
    case :queue.out(state.call_order) do
      {:empty, _} ->
        {:noreply, %{state | drain_scheduled: false}}

      {{:value, lease}, order} ->
        call = Map.fetch!(state.calls, lease)
        state = %{state | call_order: order, drain_scheduled: false}

        cond do
          Admission.closing?(state.admission) ->
            {:noreply, continue_after_call(state, lease, failure(:connection_closed))}

          not Process.alive?(elem(call.from, 0)) ->
            {:noreply, continue_after_call(state, lease, failure(:connection_closed))}

          call.deadline <= now() ->
            {:noreply, continue_after_call(state, lease, failure(:timeout))}

          true ->
            dispatch_request(state, lease, call)
        end
    end
  end

  defp dispatch_request(state, lease, call) do
    case Map.fetch(call.parameters, :payload) do
      :error -> dispatch_request_command(state, lease, call.parameters, false)
      {:ok, payload} -> dispatch_body_begin(state, lease, call.parameters, payload)
    end
  end

  defp dispatch_request_command(state, lease, parameters, uploaded?) do
    remaining = Map.fetch!(state.calls, lease).deadline - now()

    if remaining > 0 do
      case Command.encode(state.command, :request, parameters, remaining) do
        {:ok, id, line, command} ->
          submit_request(state, lease, id, line, command, uploaded?)

        :exhausted ->
          stop_dispatched_call(state, lease, failure(:sequence_exhausted))

        :error ->
          stop_dispatched_call(state, lease, failure(:invalid_request))
      end
    else
      stop_dispatched_call(state, lease, failure(:timeout))
    end
  end

  defp dispatch_body_begin(state, lease, parameters, payload) do
    case allocate_body(state) do
      {:ok, body_id, state} ->
        {:ok, request} = request_parameters(parameters, body_id)

        active = %{
          operation: :request,
          phase: :body_begin,
          id: nil,
          lease: lease,
          body_id: body_id,
          payload: payload,
          offset: 0,
          parameters: request
        }

        upload_parameters = %{
          body_id: body_id,
          length: byte_size(payload),
          sha256: payload_hash(payload)
        }

        dispatch_upload_command(state, active, :body_begin, upload_parameters)

      :exhausted ->
        stop_dispatched_call(state, lease, failure(:sequence_exhausted))
    end
  end

  defp dispatch_body_chunk(state, active) do
    remaining = byte_size(active.payload) - active.offset
    size = min(remaining, @maximum_body_chunk_bytes)
    chunk = binary_part(active.payload, active.offset, size)

    parameters = %{body_id: active.body_id, offset: active.offset, data: chunk}
    active = %{active | offset: active.offset + size}
    dispatch_upload_command(state, active, :body_chunk, parameters)
  end

  defp dispatch_body_end(state, active) do
    parameters = %{body_id: active.body_id}
    dispatch_upload_command(state, active, :body_end, parameters)
  end

  defp dispatch_upload_command(state, active, operation, parameters) do
    remaining = Map.fetch!(state.calls, active.lease).deadline - now()

    if remaining > 0 do
      case Command.encode(state.command, operation, parameters, remaining) do
        {:ok, id, line, command} -> submit_upload(state, active, operation, id, line, command)
        :exhausted -> stop_dispatched_call(state, active.lease, failure(:sequence_exhausted))
        :error -> stop_dispatched_call(state, active.lease, failure(:native_protocol_error))
      end
    else
      stop_dispatched_call(state, active.lease, failure(:timeout))
    end
  end

  defp submit_upload(state, active, operation, id, line, command) do
    if write(state.port, line) do
      {:noreply, %{state | active: %{active | phase: operation, id: id}, command: command}}
    else
      stop_dispatched_call(state, active.lease, failure(:native_unavailable))
    end
  end

  defp dispatch_uploaded_request(state, active) do
    state = %{state | active: nil}
    dispatch_request_command(state, active.lease, active.parameters, true)
  end

  defp submit_request(state, lease, id, line, command, uploaded?) do
    case Admission.mark_submission(lease) do
      :ok ->
        if write(state.port, line) do
          {:noreply,
           %{
             state
             | active: %{
                 operation: :request,
                 phase: :response,
                 id: id,
                 lease: lease,
                 body: Body.new(),
                 bodies: %{}
               },
               command: command
           }}
        else
          Admission.clear_submission(lease)
          state = finish_call(state, lease, failure(:native_unavailable))
          {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
        end

      :cancelled ->
        if uploaded?,
          do: stop_dispatched_call(state, lease, failure(:timeout)),
          else: {:noreply, continue_after_call(state, lease, failure(:timeout))}
    end
  end

  defp stop_dispatched_call(state, lease, result) do
    state = finish_call(state, lease, result)
    {:stop, :normal, %{state | cleanup_deadline: now() + @cleanup_timeout}}
  end

  defp allocate_body(%{next_body_id: next} = state)
       when is_integer(next) and next in 1..@maximum_counter do
    body_id = "body-" <> Integer.to_string(next)
    next = if next == @maximum_counter, do: :exhausted, else: next + 1
    {:ok, body_id, %{state | next_body_id: next}}
  end

  defp allocate_body(%{next_body_id: :exhausted}), do: :exhausted

  defp payload_hash(payload) do
    digest = :crypto.hash(:sha256, payload)
    Base.encode16(digest, case: :lower)
  end

  defp finish_call(state, lease, result) do
    case Map.pop(state.calls, lease) do
      {nil, _} ->
        state

      {call, calls} ->
        Process.cancel_timer(call.timer)
        Process.demonitor(call.monitor, [:flush])
        Admission.release(state.admission, lease)
        GenServer.reply(call.from, call_result(result, call.parameters, lease))

        %{
          state
          | calls: calls,
            call_order: :queue.filter(&(&1 != lease), state.call_order),
            caller_monitors: Map.delete(state.caller_monitors, call.monitor),
            active:
              if(match?(%{operation: :request, lease: ^lease}, state.active),
                do: nil,
                else: state.active
              )
        }
    end
  end

  defp continue_after_call(state, lease, result) do
    state
    |> finish_call(lease, result)
    |> schedule_drain()
  end

  defp call_result({:error, %Error{} = error}, parameters, lease) do
    if mutating?(parameters) and Admission.cancel_unsubmitted(lease) == :submitted,
      do: {:error, Error.with_effect(error, :unknown)},
      else: {:error, error}
  end

  defp call_result(result, _, _), do: result

  defp mutating?(%{method: method}), do: method in @mutating_methods
  defp mutating?(_), do: false

  defp request_options(options), do: request_options(options, @maximum_body_bytes)

  defp request_options([], maximum), do: {:ok, maximum}

  defp request_options([{:max_body_size, value}], @maximum_body_bytes)
       when is_integer(value) and value in @maximum_body_chunk_bytes..@maximum_body_bytes,
       do: {:ok, value}

  defp request_options(_, _), do: failure(:invalid_request)

  defp bounded_call({parameters, maximum_body_bytes})
       when is_map(parameters) and is_integer(maximum_body_bytes) and
              maximum_body_bytes in @maximum_body_chunk_bytes..@maximum_body_bytes,
       do: {:ok, parameters, maximum_body_bytes}

  defp bounded_call(parameters) when is_map(parameters),
    do: {:ok, parameters, @maximum_body_bytes}

  defp bounded_call(_), do: :error

  defp body_limit(%{"event" => "body_begin", "length" => length}, maximum)
       when is_integer(length) and length > maximum,
       do: failure(:body_limit)

  defp body_limit(_, _), do: :ok

  defp schedule_admission_reap do
    token = make_ref()
    {Process.send_after(self(), {:reap_admission, token}, 50), token}
  end

  defp reap_admission(%{admission_timer: {_, token}} = state, token) do
    now = now()

    for {lease, caller, deadline} <- Admission.reservations(state.admission),
        not Map.has_key?(state.calls, lease),
        deadline <= now or not Process.alive?(caller) do
      receive do
        {:"$gen_call", from, {:bounded, generation, _, ^deadline, ^lease}}
        when generation == state.generation ->
          GenServer.reply(from, failure(:timeout))
      after
        0 -> :ok
      end

      Admission.release(state.admission, lease)
    end

    case Admission.close_failure(state.admission, now()) do
      nil -> {:ok, %{state | admission_timer: schedule_admission_reap()}}
      :owner_closed -> {:error, :connection_closed, state}
      code -> {:error, code, state}
    end
  end

  defp reap_admission(state, _), do: {:ok, state}

  defp stop_with({:error, %Error{}} = result, _, state) do
    {:stop, :normal, result, %{state | cleanup_deadline: now() + @cleanup_timeout}}
  end

  defp stop_with({:error, %Error{}} = result, state) do
    state = %{state | cleanup_deadline: state.cleanup_deadline || now() + @cleanup_timeout}
    {:stop, :normal, fail_active(state, result)}
  end

  defp fail_active(%{active: %{operation: :close} = active} = state, result) do
    Process.cancel_timer(active.timer)
    GenServer.reply(active.from, result)
    %{state | active: nil}
  end

  defp fail_active(%{active: %{operation: :request, lease: lease}} = state, result),
    do: finish_call(state, lease, result)

  defp fail_active(
         %{active: %{operation: operation}, observation: observation} = state,
         {:error, %Error{} = error}
       )
       when operation in [:observe, :credit, :cancel] and not is_nil(observation),
       do: finish_observation(state, error, true)

  defp fail_active(state, _), do: state

  defp startup_failure(port, {:error, %Error{} = error}) do
    if is_tuple(port), do: close_port(elem(port, 0), elem(port, 1), now() + @cleanup_timeout)
    {:stop, {:shutdown, error}}
  end

  defp close_port(port, os_pid, deadline) when is_port(port) and is_integer(os_pid) do
    signal(os_pid, "-TERM")
    native_deadline = min(deadline, now() + @native_cleanup_timeout)

    case await_port(port, native_deadline) do
      :closed ->
        close_if_open(port)
        await_port(port, deadline)

      :timeout ->
        signal(os_pid, "-KILL")
        close_if_open(port)
        await_port(port, deadline)
    end
  rescue
    _ -> :ok
  end

  defp await_port(port, deadline) do
    if Port.info(port) && now() < deadline do
      receive do
        {^port, {:exit_status, _}} -> :closed
      after
        5 -> await_port(port, deadline)
      end
    else
      if Port.info(port), do: :timeout, else: :closed
    end
  end

  defp signal(os_pid, signal) do
    System.cmd("/bin/kill", [signal, Integer.to_string(os_pid)],
      stderr_to_stdout: true,
      env: cleared_environment()
    )

    :ok
  rescue
    _ -> :ok
  end

  defp cleared_environment,
    do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)

  defp identity(pid) when is_pid(pid) and node(pid) == node() and pid != self() do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_owner}) do
      :undefined ->
        :closed

      {{:dictionary, :wotex_coap_owner}, {__MODULE__, generation, admission}}
      when is_integer(generation) and generation in 1..@maximum_counter ->
        {:owned, generation, admission}

      _ ->
        :invalid
    end
  end

  defp identity(_), do: :invalid

  defp stop(pid, generation, admission) do
    deadline = now() + @cleanup_timeout

    case Admission.begin_close(admission, pid, generation, deadline) do
      {:first, token} ->
        stop_first(pid, generation, deadline, token)

      :waiting ->
        await_stop(pid, deadline, :ok)

      {:error, :transport_closed} ->
        :ok

      {:error, :invalid_handle} ->
        failure(:invalid_session)
    end
  end

  defp stop_first(pid, generation, deadline, token) do
    result =
      try do
        GenServer.call(
          pid,
          {:close_control, generation, deadline, token},
          max(deadline - now() - 100, 1)
        )
      catch
        :exit, _ -> if(Process.alive?(pid), do: failure(:cleanup_timeout), else: :ok)
      end

    await_stop(pid, deadline, result)
  end

  defp await_stop(pid, deadline, result) do
    monitor = Process.monitor(pid)
    remaining = max(deadline - now(), 0)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> result
    after
      remaining ->
        Process.demonitor(monitor, [:flush])
        Process.exit(pid, :kill)
        failure(:cleanup_timeout)
    end
  end

  defp options([], values), do: {:ok, values}

  defp options([{key, value} | rest], values)
       when key in @keys and not is_map_key(values, key),
       do: options(rest, Map.put(values, key, value))

  defp options(_, _), do: failure(:invalid_options)

  defp host(value) when is_binary(value) and byte_size(value) in 1..45 do
    if String.valid?(value) and :binary.match(value, <<0>>) == :nomatch do
      case :inet.parse_address(String.to_charlist(value)) do
        {:ok, _} -> :ok
        _ -> failure(:invalid_host)
      end
    else
      failure(:invalid_host)
    end
  end

  defp host(_), do: failure(:invalid_host)

  defp port(value) when is_integer(value) and value in 1..65_535, do: :ok
  defp port(_), do: failure(:invalid_port)

  defp timeout(value) when is_integer(value) and value in 1..60_000, do: :ok
  defp timeout(_), do: failure(:invalid_timeout)

  defp owner(value) when is_pid(value) and node(value) == node() do
    if Process.alive?(value), do: :ok, else: failure(:invalid_owner)
  end

  defp owner(_), do: failure(:invalid_owner)

  defp oscore(%Security{mode: :oscore} = security), do: Security.validate(security)
  defp oscore(_), do: failure(:unsupported_security)

  defp now, do: System.monotonic_time(:millisecond)
  defp failure(code), do: {:error, Error.new(code)}

  # The child can exit between a liveness check and the close, so closing an
  # already closed Port counts as closed.
  defp close_if_open(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end
end
