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
  Observe delivery and public connection dispatch remain separate obligations.
  """

  use GenServer

  alias Wotex.CoAP.{Error, NativeBackend, Security}
  alias Wotex.CoAP.Native.{Admission, Body, Command, Report, Wire}

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

  @doc "Runs one admitted native request against an already opened generation."
  @spec request(pid(), map(), pos_integer()) :: {:ok, Wotex.CoAP.Message.t()} | {:error, Error.t()}
  def request(pid, parameters, timeout)
      when is_map(parameters) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = now() + timeout

    case identity(pid) do
      {:owned, generation, admission} ->
        with :ok <- valid_request(parameters, generation, timeout),
             {:ok, lease} <- admit(admission, pid, generation, deadline) do
          await_request(pid, admission, generation, parameters, deadline, lease)
        end

      :closed ->
        failure(:connection_closed)

      :invalid ->
        failure(:invalid_session)
    end
  end

  def request(_, _, timeout) when not is_integer(timeout) or timeout not in 1..60_000,
    do: failure(:invalid_timeout)

  def request(_, _, _), do: failure(:invalid_request)

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

      active_operation == :request ->
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

    state =
      Enum.reduce(Map.keys(state.calls), state, fn lease, acc ->
        finish_call(acc, lease, failure(:connection_closed))
      end)

    deadline = state.cleanup_deadline || now() + @cleanup_timeout
    close_port(state.port, state.os_pid, deadline)
    :ok
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
        if Port.info(port), do: Port.close(port)
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
    with true <- map_size(active.bodies) == 0,
         {:ok, event} <- Report.body_event(frame, active.id),
         {:ok, body} <- Body.push(active.body, event),
         {:ok, active} <- complete_request_body(active, body, event) do
      state = %{state | active: active}

      if rest == <<>>,
        do: {:noreply, state},
        else: handle_request_bytes(state, rest)
    else
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

  defp admit(admission, pid, generation, deadline) do
    case Admission.acquire(admission, pid, generation, deadline) do
      {:ok, lease} -> {:ok, lease}
      {:error, :busy} -> failure(:busy)
      {:error, :invalid_handle} -> failure(:invalid_session)
      {:error, :transport_closed} -> failure(:connection_closed)
    end
  end

  defp await_request(pid, admission, generation, parameters, deadline, lease) do
    remaining = deadline - now()

    if remaining > 0 do
      GenServer.call(
        pid,
        {:bounded, generation, parameters, deadline, lease},
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
      not is_map(parameters) -> :invalid_request
      true -> nil
    end
  end

  defp put_call(state, parameters, deadline, lease, caller, from) do
    monitor = Process.monitor(caller)
    timer = Process.send_after(self(), {:expire_call, lease}, max(deadline - now(), 0))

    call = %{
      parameters: parameters,
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
        if Port.info(port), do: Port.close(port)
        await_port(port, deadline)

      :timeout ->
        signal(os_pid, "-KILL")
        if Port.info(port), do: Port.close(port)
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
end
