defmodule Wotex.BLE.CoreBluetooth.Connection do
  @moduledoc """
  Owns one bounded CoreBluetooth native generation.

  Handles bind a local process, private reference and consumer-supplied generation.
  At most 64 calls are admitted, including one active native procedure. Queued
  deadlines and caller loss remove unsent work; active loss retires the entire
  generation. Close joins native retirement and guardian exit within 1,500 ms.
  The consumer must keep admitted artifact paths immutable through execution.
  """
  use GenServer

  alias Wotex.BLE.{Address, Error}
  alias Wotex.BLE.BlueZ.{Artifacts, Frame}
  alias Wotex.BLE.CoreBluetooth.{Options, Response}

  @enforce_keys [:pid, :reference, :generation]
  @derive {Inspect, only: [:generation]}
  defstruct [:pid, :reference, :generation]
  @opaque t :: %__MODULE__{pid: pid(), reference: reference(), generation: pos_integer()}
  @ready %{
    "version" => 1,
    "event" => "ready",
    "backend" => "corebluetooth-native",
    "revision" => "1"
  }
  @writes [:write, :write_command]
  @fatal [
    :timeout,
    :clock_regressed,
    :disconnected,
    :stale_discovery,
    :not_authorized,
    :invalid_response,
    :transport_error,
    :cleanup_timeout,
    :peer_not_found
  ]

  @doc "Verifies and opens one native generation under the original startup deadline."
  @spec connect(term()) :: {:ok, t()} | {:error, Error.t()}
  def connect(input) do
    deadline_start = now()

    with {:ok, options} <- Options.new(input, self()),
         {:ok, pid} <- GenServer.start(__MODULE__, {options, deadline_start + options.timeout}) do
      call(pid, :open, options.timeout + 1600)
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:transport_unavailable)}
    end
  end

  @doc "Links one connection after bounded startup."
  @spec start_link(term()) :: {:ok, pid()} | {:error, Error.t()}
  def start_link(options) do
    with {:ok, handle} <- connect(options) do
      Process.link(handle.pid)
      {:ok, handle.pid}
    end
  end

  @doc "Retrieves an opaque handle from a local live owner."
  @spec session(term()) :: {:ok, t()} | {:error, Error.t()}
  def session(pid) when is_pid(pid) and node(pid) == node(), do: call(pid, :session, 1600)
  def session(_), do: {:error, Error.new(:invalid_handle)}

  @doc "Executes a validated read or explicitly selected write without retry."
  @spec request(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def request(handle, message, timeout), do: operation(handle, {:request, message}, timeout)

  @doc "Retrieves the bounded native discovery snapshot."
  @spec discover(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def discover(handle, timeout), do: operation(handle, :discover, timeout)

  @doc "Queries current native connection health."
  @spec health_check(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def health_check(handle, timeout), do: operation(handle, :health, timeout)

  @doc "Closes this generation and joins actual native retirement."
  @spec disconnect(term()) :: :ok | {:error, Error.t()}
  def disconnect(handle) do
    with :ok <- valid_handle(handle), do: call(handle.pid, {:close, handle}, 1600)
  end

  defp operation(handle, operation, timeout) do
    with :ok <- valid_handle(handle),
         true <- is_integer(timeout) and timeout in 1..60_000 do
      call(handle.pid, {:operation, handle, operation, now() + timeout}, timeout + 1600)
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_timeout)}
    end
  end

  defp valid_handle(%__MODULE__{pid: pid, reference: ref, generation: generation} = handle)
       when map_size(handle) == 4 and is_pid(pid) and node(pid) == node() and is_reference(ref) and
              is_integer(generation) and generation in 1..0xFFFF_FFFF_FFFF_FFFF,
       do: :ok

  defp valid_handle(_), do: {:error, Error.new(:invalid_handle)}

  defp call(pid, message, timeout) do
    GenServer.call(pid, message, timeout)
  catch
    :exit, {:timeout, _} -> {:error, call_error(message, :timeout)}
    :exit, _ -> {:error, call_error(message, :disconnected)}
  end

  defp call_error({:operation, _, {:request, %{type: :write}}, _}, code),
    do: Error.unknown_effect(Error.new(code))

  defp call_error(_, code), do: Error.new(code)

  @impl GenServer
  def init({options, deadline}) do
    Process.flag(:trap_exit, true)
    handle = %__MODULE__{pid: self(), reference: make_ref(), generation: options.generation}

    {:ok,
     %{
       handle: handle,
       options: options,
       deadline: deadline,
       phase: :new,
       owner: Process.monitor(options.owner),
       starter: nil,
       waiter: nil,
       startup_timer: nil,
       verifier: nil,
       port: nil,
       active: nil,
       queue: [],
       sequence: 0,
       routes: [],
       close_waiters: [],
       close_ack: nil,
       reason: nil,
       timers: []
     }}
  end

  @impl GenServer
  def handle_call(:open, from, %{phase: :new} = state) do
    parent = self()

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          send(
            parent,
            {:verified, self(), Artifacts.verify(state.options.artifacts, state.deadline)}
          )
        end,
        [:link, :monitor]
      )

    timer = Process.send_after(self(), :startup_timeout, max(state.deadline - now(), 0))

    {:noreply,
     %{
       state
       | phase: :verifying,
         waiter: from,
         starter: Process.monitor(elem(from, 0)),
         verifier: {pid, ref},
         startup_timer: timer
     }}
  end

  def handle_call(:session, _, %{phase: :ready} = state), do: {:reply, {:ok, state.handle}, state}
  def handle_call(:session, _, state), do: {:reply, {:error, Error.new(:disconnected)}, state}

  def handle_call({:operation, handle, operation, deadline}, from, %{phase: :ready} = state) do
    with true <- handle === state.handle,
         true <- deadline > now(),
         true <- length(state.queue) + if(state.active, do: 1, else: 0) < 64,
         {:ok, kind, parameters} <- parameters(operation, state) do
      token = make_ref()

      entry = %{
        token: token,
        id: nil,
        kind: kind,
        parameters: parameters,
        from: from,
        monitor: Process.monitor(elem(from, 0)),
        deadline: deadline,
        submitted: false,
        outcome: nil,
        timer: Process.send_after(self(), {:deadline, token}, max(deadline - now(), 0))
      }

      continue(dispatch(%{state | queue: Enum.concat(state.queue, [entry])}))
    else
      {:error, _} = error ->
        {:reply, error, state}

      false when handle !== state.handle ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      _ ->
        code = if deadline <= now(), do: :timeout, else: :busy
        {:reply, {:error, Error.new(code)}, state}
    end
  end

  def handle_call({:operation, handle, _, _}, _, state) do
    code = if handle === state.handle, do: :disconnected, else: :invalid_handle
    {:reply, {:error, Error.new(code)}, state}
  end

  def handle_call({:close, handle}, from, state) do
    cond do
      handle !== state.handle ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      length(state.close_waiters) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        continue(
          close(%{state | close_waiters: [from | state.close_waiters]}, Error.new(:disconnected))
        )
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_request)}, state}

  @impl GenServer
  def handle_info({:verified, pid, result}, %{verifier: {pid, ref}, phase: :verifying} = state) do
    Process.demonitor(ref, [:flush])
    Process.unlink(pid)
    state = %{state | verifier: nil}

    case result do
      {:ok, artifacts} ->
        if now() < state.deadline do
          case open_port(artifacts) do
            {:ok, port} -> {:noreply, %{state | port: port, phase: :ready_receipt}}
            _ -> continue(close(state, Error.new(:transport_unavailable)))
          end
        else
          continue(close(state, Error.new(:timeout)))
        end

      {:error, %Error{} = error} ->
        continue(close(state, error))

      _ ->
        continue(close(state, Error.new(:transport_unavailable)))
    end
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Frame.decode(line) do
      {:ok, frame} -> continue(frame(state, frame))
      _ -> continue(close(state, Error.new(:invalid_response)))
    end
  end

  def handle_info({port, {:data, _}}, %{port: port} = state),
    do: continue(close(state, Error.new(:response_limit)))

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    state = if state.phase == :closing, do: state, else: close(state, Error.new(:disconnected))
    finish(%{state | port: nil}, status == 0 and state.close_ack == true)
  end

  def handle_info(:startup_timeout, %{waiter: waiter} = state) when waiter != nil,
    do: continue(close(state, Error.new(:timeout)))

  def handle_info({:deadline, token}, %{active: %{token: token}} = state),
    do: continue(close(state, Error.new(:timeout)))

  def handle_info({:deadline, token}, state) do
    {expired, queue} = Enum.split_with(state.queue, &(&1.token == token))
    Enum.each(expired, &reply(&1, {:error, Error.new(:timeout)}))
    {:noreply, %{state | queue: queue}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    cond do
      ref in [state.owner, state.starter] ->
        continue(close(state, Error.new(:disconnected)))

      state.verifier && elem(state.verifier, 1) == ref ->
        state = %{state | verifier: nil}

        if state.phase == :closing,
          do: continue(state),
          else: continue(close(state, Error.new(:transport_unavailable)))

      state.active && state.active.monitor == ref ->
        continue(close(state, Error.new(:disconnected)))

      true ->
        {removed, queue} = Enum.split_with(state.queue, &(&1.monitor == ref))
        Enum.each(removed, &release/1)
        {:noreply, %{state | queue: queue}}
    end
  end

  def handle_info(:cleanup_term, %{phase: :closing} = state) do
    signal_port(state.port, "-TERM")
    {:noreply, state}
  end

  def handle_info(:cleanup_kill, %{phase: :closing} = state) do
    signal_port(state.port, "-KILL")
    {:noreply, state}
  end

  def handle_info(:cleanup_timeout, %{phase: :closing} = state), do: finish(state, false)

  def handle_info({:EXIT, pid, reason}, state) when is_pid(pid) and reason != :normal,
    do: continue(close(state, Error.new(:disconnected)))

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    stop_verifier(state.verifier)
    close_port(state.port)
    :ok
  end

  @impl GenServer
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted, log: []}

  defp parameters(:discover, _), do: {:ok, :discover, %{}}
  defp parameters(:health, _), do: {:ok, :health, %{}}

  defp parameters({:request, message}, state) do
    with :ok <- Address.validate_message(message),
         {:ok, address} <- Address.new(message),
         :ok <- selection(address, state.handle.generation),
         {:ok, route} <- route(address, state.routes),
         kind = kind(message),
         true <- supported?(route, kind) do
      parameters = %{"address" => %{"generation" => route.generation, "route" => route.route}}

      parameters =
        if kind in @writes,
          do:
            Map.put(parameters, "value", %{
              "type" => "bytes",
              "base64" => Base.encode64(message.value)
            }),
          else: parameters

      {:ok, kind, parameters}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:not_supported)}
    end
  end

  defp parameters(_, _), do: {:error, Error.new(:invalid_request)}
  defp kind(%{type: :write, write_mode: :without_response}), do: :write_command
  defp kind(%{type: kind}), do: kind
  defp supported?(route, :read), do: route.read
  defp supported?(route, :write), do: route.write
  defp supported?(route, :write_command), do: route.write_without_response

  defp selection(address, generation) do
    cond do
      address.handle != nil or address.object_path != nil -> {:error, Error.new(:not_supported)}
      address.generation not in [nil, generation] -> {:error, Error.new(:stale_discovery)}
      true -> :ok
    end
  end

  defp route(address, routes) do
    routes =
      Enum.filter(routes, fn route ->
        route.service == address.service and route.characteristic == address.characteristic and
          address.native_route in [nil, {:core_bluetooth, route.route}]
      end)

    case routes do
      [route] -> {:ok, route}
      [] -> {:error, Error.new(:address_mismatch)}
      _ -> {:error, Error.new(:ambiguous_characteristic)}
    end
  end

  defp frame(%{phase: :ready_receipt} = state, @ready) do
    parameters = %{
      "identifier" => state.options.peer.identifier,
      "generation" => state.handle.generation,
      "permission" => Atom.to_string(state.options.permission),
      "pairing" => "system"
    }

    startup_send(%{state | phase: :opening}, "open", :open, parameters)
  end

  defp frame(state, frame) do
    state =
      if state.waiter && state.phase != :closing && now() >= state.deadline,
        do: close(state, Error.new(:timeout)),
        else: state

    case Response.decode(frame, state.handle.generation) do
      {:submitted, id} ->
        submitted(state, id)

      {:lost, code} ->
        close(state, Error.new(code))

      {:reply, "close", result} when state.phase == :closing ->
        case Response.result(:close, elem(result, 1), state.handle.generation) do
          {:ok, :closed} when elem(result, 0) == :ok and is_nil(state.close_ack) ->
            %{state | close_ack: true}

          _ ->
            %{state | close_ack: false}
        end

      {:reply, id, result} ->
        native_reply(state, id, result)

      _ ->
        close(state, Error.new(:invalid_response))
    end
  end

  defp submitted(%{active: %{id: id, kind: kind, submitted: false} = active} = state, id)
       when kind in @writes, do: %{state | active: %{active | submitted: true}}

  defp submitted(state, _), do: close(state, Error.new(:invalid_response))

  defp native_reply(%{active: %{id: id} = active} = state, id, result) do
    validated = validated_result(active, result, state.handle.generation)

    if state.phase != :closing and now() >= active.deadline do
      error = Error.new(:timeout)

      outcome =
        case validated do
          {:error, %{effect: :none}} -> {:error, error}
          _ -> {:error, effect(error, active)}
        end

      close(%{state | active: %{active | outcome: outcome}}, error)
    else
      deliver_native(state, active, validated)
    end
  end

  defp native_reply(state, _, _), do: close(state, Error.new(:invalid_response))

  defp deliver_native(state, _, {:ok, value}), do: success(state, value)
  defp deliver_native(%{phase: :closing} = state, _, {:error, _}), do: state

  defp deliver_native(state, active, {:error, error} = outcome) do
    if error.code in @fatal or active.kind == :open or state.waiter do
      close(%{state | active: %{active | outcome: outcome}}, error)
    else
      reply(active, outcome)
      dispatch(%{state | active: nil})
    end
  end

  defp deliver_native(state, _, _), do: close(state, Error.new(:invalid_response))

  defp validated_result(active, {:ok, result}, generation) do
    if active.kind in @writes and not active.submitted,
      do: :invalid,
      else: Response.result(active.kind, result, generation)
  end

  defp validated_result(active, {:error, error, submitted, _}, _) do
    if submitted == active.submitted and (not submitted or active.kind in @writes),
      do: {:error, if(submitted, do: Error.unknown_effect(error), else: error)},
      else: :invalid
  end

  defp success(%{phase: :closing} = state, _), do: state

  defp success(%{phase: :opening} = state, :opened) do
    startup_send(%{state | sequence: 1}, "1", :discover, %{})
  end

  defp success(%{phase: :ready, active: %{kind: :discover}} = state, %{characteristics: routes})
       when routes != state.routes,
       do: close(state, Error.new(:stale_discovery))

  defp success(%{waiter: waiter} = state, %{characteristics: routes}) when waiter != nil do
    if now() >= state.deadline do
      close(state, Error.new(:timeout))
    else
      Process.cancel_timer(state.startup_timer)
      Process.demonitor(state.starter, [:flush])
      GenServer.reply(waiter, {:ok, state.handle})
      %{state | waiter: nil, starter: nil, phase: :ready, active: nil, routes: routes}
    end
  end

  defp success(state, value) do
    if now() >= state.active.deadline do
      close(state, Error.new(:timeout))
    else
      reply(state.active, {:ok, value})
      dispatch(%{state | active: nil})
    end
  end

  defp startup_send(state, id, kind, parameters) do
    active = %{
      id: id,
      kind: kind,
      deadline: state.deadline,
      submitted: false,
      outcome: nil,
      token: :startup,
      from: nil,
      monitor: nil,
      timer: nil
    }

    state = %{state | active: active}

    if send_frame(state.port, id, kind, parameters, state.deadline),
      do: state,
      else: close(state, Error.new(:timeout))
  end

  defp dispatch(%{active: nil, queue: [entry | rest], phase: :ready} = state) do
    state = %{state | queue: rest}

    cond do
      not Process.alive?(elem(entry.from, 0)) ->
        release(entry)
        dispatch(state)

      entry.deadline <= now() ->
        reply(entry, {:error, Error.new(:timeout)})
        dispatch(state)

      state.sequence == 0xFFFF_FFFF_FFFF_FFFF ->
        reply(entry, {:error, Error.new(:resource_limit)})
        close(state, Error.new(:resource_limit))

      true ->
        sequence = state.sequence + 1
        entry = %{entry | id: Integer.to_string(sequence)}
        state = %{state | sequence: sequence, active: entry}

        if send_frame(state.port, entry.id, entry.kind, entry.parameters, entry.deadline),
          do: state,
          else: close(state, Error.new(:transport_error))
    end
  end

  defp dispatch(state), do: state

  defp close(%{phase: :closing} = state, %{code: code})
       when code in [:invalid_response, :response_limit],
       do: %{state | close_ack: false}

  defp close(%{phase: :closing} = state, _), do: state

  defp close(state, reason) do
    stop_verifier(state.verifier)
    if state.startup_timer, do: Process.cancel_timer(state.startup_timer)
    Enum.each(state.queue, &reply(&1, {:error, Error.new(:disconnected)}))
    if state.port, do: send_frame(state.port, "close", :close, %{}, now() + 500)

    timers =
      for {message, timeout} <- [cleanup_term: 650, cleanup_kill: 1250, cleanup_timeout: 1500],
          do: Process.send_after(self(), message, timeout)

    %{state | phase: :closing, reason: reason, queue: [], timers: timers}
  end

  defp continue(%{phase: :closing, port: nil, verifier: nil} = state), do: finish(state, true)
  defp continue(state), do: {:noreply, state}

  defp finish(state, confirmed) do
    Enum.each(state.timers, &Process.cancel_timer/1)
    error = state.reason || Error.new(:disconnected)
    error = if confirmed, do: error, else: %{error | details: %{cleanup: :unconfirmed}}
    if state.waiter, do: GenServer.reply(state.waiter, {:error, error})

    if state.active && state.active.from do
      result = state.active.outcome || {:error, effect(error, state.active)}
      result = if confirmed, do: result, else: unconfirmed(result)
      reply(state.active, result)
    end

    result = if confirmed, do: :ok, else: {:error, Error.new(:cleanup_timeout)}
    Enum.each(state.close_waiters, &GenServer.reply(&1, result))
    {:stop, :normal, state}
  end

  defp unconfirmed({:error, error}), do: {:error, %{error | details: %{cleanup: :unconfirmed}}}
  defp effect(error, %{kind: kind}) when kind in @writes, do: Error.unknown_effect(error)
  defp effect(error, _), do: error

  defp reply(entry, result) do
    release(entry)
    if entry.from, do: GenServer.reply(entry.from, result)
  end

  defp release(entry) do
    if entry.timer, do: Process.cancel_timer(entry.timer)
    if entry.monitor, do: Process.demonitor(entry.monitor, [:flush])
  end

  defp open_port(%{executable: executable, guardian: guardian}) do
    {:ok,
     Port.open({:spawn_executable, guardian.path}, [
       :binary,
       :exit_status,
       {:line, 131_071},
       args: ["500", "131072", "65536", Path.dirname(executable.path), executable.path],
       env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
     ])}
  rescue
    _ -> :error
  end

  defp send_frame(port, id, operation, parameters, deadline) do
    remaining = deadline - now()

    remaining > 0 and
      Port.command(
        port,
        Jason.encode!(%{
          version: 1,
          id: id,
          operation: Atom.to_string(operation),
          parameters: parameters,
          timeout_ms: min(remaining, 60_000)
        }) <> "\n",
        [:nosuspend]
      )
  rescue
    _ -> false
  end

  defp stop_verifier(nil), do: :ok

  defp stop_verifier({pid, ref}) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    # Keep the monitor until DOWN joins retirement, or the cleanup budget expires.
    ref
  end

  defp close_port(nil), do: :ok

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp signal_port(nil, _), do: :ok

  defp signal_port(port, signal) do
    case Port.info(port, :os_pid) do
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

  defp now, do: System.monotonic_time(:millisecond)
end
