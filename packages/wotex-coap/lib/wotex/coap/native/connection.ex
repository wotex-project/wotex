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
  cleanup. Native writes use `Port.command/3` with `:nosuspend`. Malformed,
  oversized, truncated, duplicate or otherwise unsolicited frames close the
  generation. Local cleanup signals the exact Port process and remains within
  the WCO-C03 1,000 ms budget. This module implements startup and close control
  only; unary exchange, body transfer, Observe delivery and public connection
  dispatch remain separate obligations.
  """

  use GenServer

  alias Wotex.CoAP.{Error, NativeBackend, Security}
  alias Wotex.CoAP.Native.{Admission, Command, Wire}

  @keys [:host, :port, :timeout, :owner, :security, :native_backend]
  @maximum_frame_bytes 131_071
  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @ready_timeout 5_000
  @close_timeout 350
  @cleanup_timeout 1_000
  @native_cleanup_timeout 550

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
  def handle_call(
        {:close_control, generation, deadline, token},
        {caller, _} = from,
        %{active: nil} = state
      ) do
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
        state
      ) do
    if generation == state.generation and
         Admission.close_owned?(state.admission, token, caller, deadline),
       do: {:reply, failure(:busy), state},
       else: {:reply, failure(:invalid_session), state}
  end

  def handle_call(_, _, state), do: {:reply, failure(:invalid_session), state}

  @impl GenServer
  def handle_info({port, {:data, bytes}}, %{port: port, active: active} = state)
      when is_binary(bytes) and not is_nil(active) do
    case receive_chunk(state.buffer, bytes) do
      {:line, line, <<>>} ->
        result =
          with {:ok, frame} <- Wire.frame(line),
               do: Wire.response(active.operation, frame, active.id)

        case result do
          {:ok, nil} ->
            Process.cancel_timer(active.timer)
            GenServer.reply(active.from, :ok)
            {:stop, :normal, %{state | active: nil, buffer: <<>>}}

          {:error, %Error{} = error} ->
            Process.cancel_timer(active.timer)
            GenServer.reply(active.from, {:error, error})
            {:stop, :normal, %{state | active: nil, buffer: <<>>}}
        end

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

  def handle_info(
        {:native_timeout, generation, id},
        %{generation: generation, active: %{id: id}} = state
      ),
      do: stop_with(failure(:timeout), state)

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

    if state.active do
      Process.cancel_timer(state.active.timer)
      GenServer.reply(state.active.from, failure(:connection_closed))
    end

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

  defp schedule_admission_reap do
    token = make_ref()
    {Process.send_after(self(), {:reap_admission, token}, 50), token}
  end

  defp reap_admission(%{admission_timer: {_, token}} = state, token) do
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

    if state.active do
      Process.cancel_timer(state.active.timer)
      GenServer.reply(state.active.from, result)
    end

    {:stop, :normal, %{state | active: nil}}
  end

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
