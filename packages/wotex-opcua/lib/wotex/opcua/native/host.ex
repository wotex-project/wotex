defmodule Wotex.OPCUA.Native.Host do
  @moduledoc """
  Owns a verified native bootstrap process and its independent custody guardian.

  `start_link/1` accepts the explicit executable identities described by
  `Wotex.OPCUA.Native.HostOptions`. Its caller owns this temporary child. A native
  Session must start the host itself, so a short-lived establishment worker does
  not become the native process owner. Source hashing runs in one linked worker;
  hashing, spawn and readiness share the deadline captured at API entry.

  The successful return includes the decoded process readiness and the BEAM
  monotonic receive sample. This bootstrap does not send credentials or
  protocol requests at startup. Its internal `request/4` path can correlate
  explicit secure open, Value read, typed Write, Method Call, bounded Browse
  pages and close responses with credit replenishment. A Browse continuation is
  mapped to an owner-bound reference; only one is live per native Session.
  Other native service operations remain unimplemented.
  Unsolicited output ends the
  generation and sends one
  `{:wotex_opcua_native, pid, {:error, error}}` to its owner.

  Fallible initialization is unlinked; successful readiness requires a one-use
  claim from the original owner before its original deadline. That claim links
  the child to its owner. Owner death, an expired claim, failed initialization
  and OTP termination close the owned Port.
  The independently executing guardian then closes and reaps its SDK child under
  the separate 500 ms custody budget. Closing a Port alone is not an observed
  guardian exit status or evidence of remote Session deletion. The child
  specification is temporary: no automatic reconnect or replay occurs.
  """

  use GenServer

  alias Wotex.OPCUA.Browse.Continuation
  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.{Executable, Frame, HostOptions, Ready}

  @typedoc "Process readiness and its separately captured BEAM monotonic receive time."
  @type sample :: %{ready: Ready.t(), received_at_ms: integer()}

  @doc "Starts a caller-owned bootstrap and returns its verified readiness before service admission."
  @spec start_link(term()) :: {:ok, pid(), sample()} | {:error, Error.t()}
  def start_link(options) do
    entered = System.monotonic_time(:millisecond)

    with {:ok, settings} <- HostOptions.new(options) do
      token = make_ref()
      deadline = entered + settings.timeout

      generation = owner_generation()

      case GenServer.start(__MODULE__, {settings, self(), token, deadline, generation},
             timeout: settings.timeout + 500
           ) do
        {:ok, pid} ->
          claim(pid, token, deadline)

        {:error, {:shutdown, %Error{} = error}} ->
          {:error, error}

        {:error, _} ->
          {:error, Error.new(:native_startup_failed)}
      end
    end
  catch
    :exit, _ -> {:error, Error.new(:native_startup_failed)}
  end

  @doc "Sends one bounded owner request to the native generation."
  @spec request(pid(), String.t(), map(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(host, operation, parameters, timeout)
      when is_pid(host) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    GenServer.call(
      host,
      {__MODULE__, :request, operation, parameters, timeout, deadline},
      timeout + 100
    )
  catch
    :exit, _ -> {:error, Error.new(:native_process_terminated)}
  end

  def request(_, _, _, _), do: {:error, Error.new(:invalid_native_frame, :request)}

  @doc "Starts one bounded Browse page and binds any native token to this owner."
  @spec browse_page(pid(), map(), map(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def browse_page(host, parameters, limits, timeout)
      when is_pid(host) and is_map(parameters) and is_map(limits) and
             is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    GenServer.call(
      host,
      {__MODULE__, :browse_page, parameters, limits, timeout, deadline},
      timeout + 100
    )
  catch
    :exit, _ -> {:error, Error.new(:native_process_terminated)}
  end

  def browse_page(_, _, _, _), do: {:error, Error.new(:invalid_native_handle)}

  @doc "Consumes one owner-bound handle for the next native Browse page."
  @spec browse_next(pid(), Continuation.t(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def browse_next(host, handle, timeout), do: continue(host, handle, timeout, :next)

  @doc "Releases one owner-bound native server continuation."
  @spec browse_release(pid(), Continuation.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def browse_release(host, handle, timeout) do
    case continue(host, handle, timeout, :release) do
      {:ok, nil} -> :ok
      error -> error
    end
  end

  defp continue(host, %Continuation{} = handle, timeout, operation)
       when is_pid(host) and is_integer(timeout) and timeout in 1..60_000 do
    call_timeout = if operation == :release, do: min(timeout, 1000) + 1100, else: timeout + 1100

    GenServer.call(host, {__MODULE__, :browse_continue, handle, timeout, operation}, call_timeout)
  catch
    :exit, _ -> {:error, Error.new(:native_process_terminated)}
  end

  defp continue(_, _, _, _), do: {:error, Error.new(:invalid_continuation)}

  @doc "Returns a temporary OTP child specification with a bounded local shutdown."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 1000,
      type: :worker
    }
  end

  @impl GenServer
  def init({settings, owner, token, deadline, generation}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)

    with :ok <- verify(settings, owner, monitor, deadline),
         :ok <- budget(deadline),
         :ok <- owner_alive(owner),
         {:ok, port} <- spawn_native(settings) do
      case await_ready(port, owner, monitor, deadline, <<>>) do
        {:ok, sample} ->
          {:ok,
           %{
             port: port,
             owner: owner,
             monitor: monitor,
             token: token,
             sample: sample,
             deadline: deadline,
             generation: generation,
             pending: nil,
             input: <<>>,
             next_id: 1,
             continuations: %{},
             credit_sequence: 0,
             claim_timer: :erlang.start_timer(remaining(deadline), self(), :claim_expired),
             claimed: false
           }}

        {:error, error} ->
          close_port(port)
          {:stop, {:shutdown, error}}
      end
    else
      {:error, error} -> {:stop, {:shutdown, error}}
    end
  end

  @impl GenServer
  def handle_call(
        {__MODULE__, :claim, token},
        {owner, _},
        %{token: token, owner: owner, claimed: false} = state
      ) do
    with :ok <- budget(state.deadline),
         :ok <- owner_alive(owner) do
      Process.link(owner)
      Process.cancel_timer(state.claim_timer)
      {:reply, {:ok, state.sample}, %{state | claimed: true}}
    else
      {:error, error} -> {:stop, :normal, {:error, error}, state}
    end
  end

  def handle_call(
        {__MODULE__, :request, operation, parameters, timeout, deadline},
        {owner, _} = from,
        %{owner: owner, claimed: true, pending: nil} = state
      ) do
    if operation in ["browse_next", "browse_release"] do
      {:reply, {:error, Error.new(:invalid_continuation)}, state}
    else
      start_request(state, from, operation, parameters, timeout, deadline, nil)
    end
  end

  def handle_call(
        {__MODULE__, :browse_page, parameters, limits, timeout, deadline},
        {owner, _} = from,
        %{owner: owner, claimed: true, pending: nil} = state
      ) do
    if map_size(state.continuations) == 0 and valid_browse_limits?(limits) do
      start_request(
        state,
        from,
        "browse",
        Map.put(parameters, "allow_continuation", true),
        timeout,
        deadline,
        %{kind: :browse_page, pages: 0, references: 0, bytes: 0, limits: limits}
      )
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call(
        {__MODULE__, :browse_continue, %Continuation{} = handle, timeout, operation},
        {owner, _} = from,
        %{owner: owner, claimed: true, pending: nil} = state
      ) do
    case Map.fetch(state.continuations, handle.reference) do
      {:ok, cursor}
      when handle.pid == self() and handle.generation == state.generation and
             operation in [:next, :release] ->
        now = System.monotonic_time(:millisecond)

        if operation == :next and now >= cursor.deadline do
          {:stop, :normal, {:error, Error.new(:deadline_exceeded)}, state}
        else
          budget =
            if operation == :release,
              do: min(timeout, 1000),
              else: min(timeout, cursor.deadline - now)

          deadline = if operation == :release, do: now + budget, else: cursor.deadline
          name = if operation == :release, do: "browse_release", else: "browse_next"

          start_request(
            state,
            from,
            name,
            %{"continuation" => cursor.token},
            budget,
            deadline,
            Map.merge(cursor, %{kind: operation, previous: handle.reference})
          )
        end

      _ ->
        {:reply, {:error, Error.new(:invalid_continuation)}, state}
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_native_handle)}, state}

  defp valid_browse_limits?(%{max_pages: pages, max_references: references})
       when pages in 1..64 and references in 1..4096,
       do: true

  defp valid_browse_limits?(_), do: false

  defp start_request(state, from, operation, parameters, timeout, deadline, cursor) do
    now = System.monotonic_time(:millisecond)

    id = Integer.to_string(state.next_id)

    with {:ok, admission} <-
           Frame.admission(state.sample.ready, state.sample.received_at_ms, deadline, now, timeout),
         {:ok, frame} <-
           Frame.request(
             state.generation,
             id,
             operation,
             parameters,
             admission.timeout_ms,
             admission.deadline_ms
           ),
         {:ok, credit} <- initial_credit(state),
         :ok <- send_optional(state.port, credit),
         :ok <- send_frame(state.port, frame) do
      timer = Process.send_after(self(), :request_expired, max(min(deadline - now, timeout), 0))

      {:noreply,
       %{
         state
         | pending: %{
             from: from,
             timer: timer,
             id: id,
             operation: operation,
             cursor: cursor,
             deadline: deadline,
             requested_timeout: parameters["session_timeout_ms"]
           },
           next_id: state.next_id + 1,
           credit_sequence: max(state.credit_sequence, 1)
       }}
    else
      {:error, %Error{} = error} ->
        if cursor && cursor.kind in [:next, :release],
          do: {:stop, :normal, {:error, error}, state},
          else: {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, owner, _}, %{monitor: monitor, owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(
        {:timeout, timer, :claim_expired},
        %{claim_timer: timer, claimed: false} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    failed(state, Error.new(:native_process_terminated, nil, %{exit_status: status}))
  end

  def handle_info({port, {:data, bytes}}, %{port: port, pending: %{from: _} = pending} = state)
      when byte_size(state.input) + byte_size(bytes) <= 131_072 do
    input = state.input <> bytes

    if :binary.match(input, "\n") == :nomatch do
      {:noreply, %{state | input: input}}
    else
      handle_native_frame(state, pending, input)
    end
  end

  def handle_info({port, {:data, _}}, %{port: port} = state),
    do: failed(state, Error.new(:invalid_native_frame))

  def handle_info(:request_expired, %{pending: %{from: _}} = state),
    do: failed(state, Error.new(:deadline_exceeded, :request))

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: failed(state, Error.new(:native_process_terminated))

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    close_port(state.port)
    :ok
  end

  defp verify(settings, owner, owner_monitor, deadline) do
    host = self()
    token = make_ref()

    {worker, monitor} =
      :erlang.spawn_opt(
        fn ->
          result =
            with {:ok, _} <-
                   Executable.verify(settings.guardian, settings.guardian_digest, deadline),
                 {:ok, _} <-
                   Executable.verify(settings.executable, settings.executable_digest, deadline),
                 do: :ok

          send(host, {token, result})
        end,
        [:link, :monitor]
      )

    try do
      receive do
        {^token, result} -> result
        {:DOWN, ^owner_monitor, :process, ^owner, _} -> {:error, Error.new(:native_owner_lost)}
        {:EXIT, ^owner, _} -> {:error, Error.new(:native_owner_lost)}
        {:DOWN, ^monitor, :process, ^worker, _} -> {:error, Error.new(:invalid_native_executable)}
      after
        remaining(deadline) -> {:error, Error.new(:deadline_exceeded, :executable)}
      end
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      Process.unlink(worker)
      Process.demonitor(monitor, [:flush])
    end
  end

  defp spawn_native(settings) do
    environment =
      System.get_env()
      |> Map.new(fn {key, _} -> {String.to_charlist(key), false} end)
      |> Map.put(~c"LC_ALL", ~c"C")
      |> Map.to_list()

    port =
      Port.open({:spawn_executable, settings.guardian}, [
        :binary,
        :exit_status,
        args: ["500", "131072", "65536", Path.dirname(settings.executable), settings.executable],
        env: environment
      ])

    {:ok, port}
  rescue
    _ in [ArgumentError, ErlangError] -> {:error, Error.new(:native_startup_failed)}
  end

  defp await_ready(port, owner, monitor, deadline, buffered) do
    receive do
      {^port, {:data, bytes}} when byte_size(buffered) + byte_size(bytes) <= 4096 ->
        received = System.monotonic_time(:millisecond)
        frame = buffered <> bytes

        if :binary.match(frame, "\n") == :nomatch do
          await_ready(port, owner, monitor, deadline, frame)
        else
          with :ok <- budget(deadline),
               {:ok, ready} <- Ready.decode(frame) do
            {:ok, %{ready: ready, received_at_ms: received}}
          end
        end

      {^port, {:data, _}} ->
        {:error, Error.new(:invalid_native_ready, :ready)}

      {^port, {:exit_status, status}} ->
        {:error, Error.new(:native_process_terminated, nil, %{exit_status: status})}

      {:EXIT, ^port, _} ->
        {:error, Error.new(:native_process_terminated)}

      {:DOWN, ^monitor, :process, ^owner, _} ->
        {:error, Error.new(:native_owner_lost)}

      {:EXIT, ^owner, _} ->
        {:error, Error.new(:native_owner_lost)}
    after
      remaining(deadline) -> {:error, Error.new(:deadline_exceeded, :ready)}
    end
  end

  defp failed(state, error) do
    case state.pending do
      nil -> send(state.owner, {:wotex_opcua_native, self(), {:error, error}})
      pending -> GenServer.reply(pending.from, {:error, pending_effect(error, pending)})
    end

    {:stop, :normal, state}
  end

  defp pending_effect(error, %{operation: operation}) when operation in ["write", "call"],
    do: %{error | effect: :unknown}

  defp pending_effect(error, _), do: error

  defp send_frame(port, frame) do
    if Port.command(port, frame), do: :ok, else: {:error, Error.new(:native_process_terminated)}
  rescue
    ArgumentError -> {:error, Error.new(:native_process_terminated)}
  end

  defp initial_credit(%{credit_sequence: 0, generation: generation}),
    do: Frame.credit(generation, 1, 16, 262_144)

  defp initial_credit(_), do: {:ok, nil}

  defp send_optional(_, nil), do: :ok
  defp send_optional(port, frame), do: send_frame(port, frame)

  defp handle_native_frame(state, pending, input) do
    case Frame.terminal(input, state.generation) do
      {:ok, error} ->
        Process.cancel_timer(pending.timer)
        GenServer.reply(pending.from, {:error, error})
        {:stop, :normal, %{state | pending: nil}}

      {:error, _} ->
        handle_native_response(state, pending, input)
    end
  end

  defp handle_native_response(state, pending, input) do
    case Frame.response(
           input,
           state.generation,
           pending.id,
           pending.operation,
           pending.requested_timeout
         ) do
      {:ok, %{"continuation" => continuation} = result} when is_binary(continuation) ->
        if pending.cursor,
          do: deliver_native_result(state, pending, input, result),
          else: failed(state, Error.new(:response_limit))

      {:ok, result} ->
        deliver_native_result(state, pending, input, result)

      {:native_error, error} ->
        Process.cancel_timer(pending.timer)
        GenServer.reply(pending.from, {:error, error})
        {:stop, :normal, %{state | pending: nil}}

      {:error, error} ->
        failed(state, error)
    end
  end

  defp deliver_native_result(state, pending, input, result) do
    Process.cancel_timer(pending.timer)

    cond do
      pending.operation == "close" ->
        GenServer.reply(pending.from, {:ok, result})
        {:stop, :normal, %{state | pending: nil}}

      pending.cursor ->
        deliver_browse_result(state, pending, input, result)

      true ->
        reply_with_credit(state, pending, input, {:ok, result}, state.continuations)
    end
  end

  defp deliver_browse_result(state, pending, input, nil) when pending.cursor.kind == :release do
    continuations = Map.delete(state.continuations, pending.cursor.previous)
    reply_with_credit(state, pending, input, {:ok, nil}, continuations)
  end

  defp deliver_browse_result(
         state,
         pending,
         input,
         %{"references" => references, "continuation" => token} = result
       )
       when pending.cursor.kind in [:browse_page, :next] do
    old = pending.cursor
    pages = old.pages + 1
    count = old.references + length(references)
    bytes = old.bytes + byte_size(input)

    if pages > old.limits.max_pages or count > old.limits.max_references or bytes > 1_048_576 or
         (is_binary(token) and pages == old.limits.max_pages) do
      failed(state, Error.new(:response_limit))
    else
      continuations = Map.delete(state.continuations, Map.get(old, :previous))

      if is_binary(token) do
        reference = make_ref()
        handle = %Continuation{pid: self(), reference: reference, generation: state.generation}

        cursor = %{
          token: token,
          deadline: pending.deadline,
          pages: pages,
          references: count,
          bytes: bytes,
          limits: old.limits
        }

        reply_with_credit(
          state,
          pending,
          input,
          {:ok, %{result | "continuation" => handle}},
          Map.put(continuations, reference, cursor)
        )
      else
        reply_with_credit(state, pending, input, {:ok, result}, continuations)
      end
    end
  end

  defp deliver_browse_result(state, _, _, _),
    do: failed(state, Error.new(:invalid_native_frame))

  defp reply_with_credit(state, pending, input, reply, continuations) do
    with {:ok, credit} <-
           Frame.credit(state.generation, state.credit_sequence + 1, 1, byte_size(input)),
         :ok <- send_frame(state.port, credit) do
      GenServer.reply(pending.from, reply)

      {:noreply,
       %{
         state
         | pending: nil,
           input: <<>>,
           continuations: continuations,
           credit_sequence: state.credit_sequence + 1
       }}
    else
      {:error, error} -> failed(state, error)
    end
  end

  defp owner_generation do
    case :binary.decode_unsigned(:crypto.strong_rand_bytes(8)) do
      0 -> owner_generation()
      generation -> generation
    end
  end

  defp claim(pid, token, deadline) do
    result =
      try do
        GenServer.call(pid, {__MODULE__, :claim, token}, remaining(deadline) + 100)
      catch
        :exit, _ -> {:error, Error.new(:native_startup_failed)}
      end

    case result do
      {:ok, sample} ->
        {:ok, pid, sample}

      {:error, _} = error ->
        stop_unclaimed(pid)
        error
    end
  end

  defp stop_unclaimed(pid) do
    GenServer.stop(pid, :normal, 500)
  catch
    :exit, _ -> :ok
  end

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp owner_alive(owner) do
    if Process.alive?(owner), do: :ok, else: {:error, Error.new(:native_owner_lost)}
  end

  defp budget(deadline) do
    if remaining(deadline) > 0,
      do: :ok,
      else: {:error, Error.new(:deadline_exceeded, :ready)}
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
