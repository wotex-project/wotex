defmodule Wotex.BLE.BlueZ.Connection do
  @moduledoc """
  Owns one explicitly started persistent BlueZ bridge and its D-Bus sender.

  `connect/1` waits for the packaged bridge to resolve the selected peer before
  returning an opaque handle. The supplied absolute `:executable` is a Python
  interpreter with the pinned dbus-next dependency installed. `:bus_address`
  selects local IPC explicitly, and `:owner` defaults to the calling process.
  `start_link/1` supports consumer supervision; `session/1` retrieves its session.

  Discovery, pairing and GATT requests share a bounded serial queue. Owner
  death, a deadline or malformed bridge output closes the generation. Cleanup
  is bounded to one second and never reconnects or powers an adapter. Loading
  the module starts nothing. Stream procedures graduate separately.
  """

  use GenServer
  alias Wotex.BLE.BlueZ.{Frame, Options, Pairing, Response, Stream, SubscriptionOwner}
  alias Wotex.BLE.{Error, Procedure, Session}

  @derive {Inspect, only: [:pid, :generation]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct [:pid, :reference, :generation]
  @opaque t :: %__MODULE__{pid: pid(), reference: reference(), generation: pos_integer()}

  @doc "Opens the explicit peer, with no link to the caller during fallible startup."
  @spec connect(term()) :: {:ok, t()} | {:error, Error.t()}
  def connect(options) do
    with {:ok, options} <- Options.new(options),
         {:ok, pid} <-
           GenServer.start(__MODULE__, Map.put(options, :deadline, now() + options.timeout)) do
      call(pid, :open)
    end
  end

  @doc "Links a successfully initialized connection for consumer supervision."
  @spec start_link(term()) :: {:ok, pid()} | {:error, Error.t()}
  def start_link(options) do
    with {:ok, handle} <- connect(options) do
      Process.link(handle.pid)
      {:ok, handle.pid}
    end
  end

  @doc "Retrieves the session from an explicitly supervised connection process."
  @spec session(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  def session(pid) when is_pid(pid), do: call(pid, :session)
  def session(_), do: {:error, Error.new(:invalid_handle)}

  @doc "Returns a bounded page of the selected peer's verified GATT characteristics."
  @spec discover(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def discover(%__MODULE__{pid: pid, reference: reference, generation: 1}, options, timeout)
      when is_pid(pid) and is_reference(reference) and is_integer(timeout) and
             timeout in 1..60_000 do
    with {:ok, parameters} <- Options.discovery(options) do
      call(pid, {reference, "discover", parameters, now() + timeout})
    end
  end

  def discover(_, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Executes a validated read or acknowledged write on this persistent sender."
  @spec request(term(), term(), term()) :: {:ok, binary() | :written} | {:error, Error.t()}
  def request(%__MODULE__{pid: pid, reference: reference, generation: 1}, message, timeout)
      when is_pid(pid) and is_reference(reference) and is_integer(timeout) and
             timeout >= 1 and timeout <= 60_000 do
    with {:ok, operation, parameters} <- Procedure.parameters(message) do
      call(pid, {reference, operation, parameters, now() + timeout})
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Pairs only through an explicitly supplied consumer Agent policy."
  @spec pair(term(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def pair(%__MODULE__{pid: pid, reference: reference, generation: 1}, request, timeout)
      when is_pid(pid) and is_reference(reference) do
    with {:ok, policy} <- Pairing.options(request, timeout) do
      call(pid, {reference, :pair, policy, now() + policy.timeout})
    end
  end

  def pair(_, _, _), do: {:error, Error.new(:invalid_handle)}

  @doc "Queries the bound peer's current Connected and ServicesResolved state."
  @spec health_check(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def health_check(handle, timeout) do
    if handle?(handle) and is_integer(timeout) and timeout in 1..60_000,
      do: call(handle.pid, {handle.reference, "health", %{}, now() + timeout}),
      else: {:error, Error.new(:invalid_handle)}
  end

  @doc "Starts a receiver-owned stream through this persistent sender."
  @spec subscribe(term(), term(), term()) :: {:ok, Wotex.BLE.Subscription.t()} | {:error, Error.t()}
  def subscribe(handle, request, timeout) do
    with true <- handle?(handle),
         {:ok, config} <- Stream.options(request, timeout, self()) do
      call(handle.pid, {handle.reference, :subscribe, config, now() + config.timeout})
    else
      false -> {:error, Error.new(:invalid_handle)}
      error -> error
    end
  end

  @doc "Cancels a same-session subscription and waits for its native release."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(handle, subscription) do
    if handle?(handle) and Stream.handle?(subscription) and
         handle.reference == subscription.session_reference,
       do: SubscriptionOwner.cancel(subscription),
       else: {:error, Error.new(:invalid_subscription)}
  end

  defp handle?(%__MODULE__{pid: pid, reference: ref, generation: 1} = handle),
    do: map_size(handle) == 4 and is_pid(pid) and is_reference(ref)

  defp handle?(_), do: false

  @doc "Closes the generation and waits for bounded native cleanup; repeated close is safe."
  @spec disconnect(term()) :: :ok | {:error, Error.t()}
  def disconnect(%__MODULE__{pid: pid, reference: reference, generation: 1})
      when is_pid(pid) and is_reference(reference) do
    case call(pid, {reference, :close}) do
      {:error, %Error{code: :disconnected}} -> :ok
      result -> result
    end
  end

  def disconnect(_), do: {:error, Error.new(:invalid_handle)}

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       options: options,
       owner_ref: Process.monitor(options.owner),
       handle: %__MODULE__{pid: self(), reference: make_ref(), generation: 1},
       status: :new,
       port: nil,
       waiter: nil,
       start_ref: nil,
       startup_timer: nil,
       pending: %{},
       wires: %{},
       subscriptions: %{},
       cleanup_grace: 1000,
       active: nil,
       queue: :queue.new(),
       counter: 0,
       buffer: <<>>,
       discovery_generation: 1,
       policy: nil,
       policy_control: nil,
       close_from: [],
       close_result: {:error, Error.new(:disconnected)},
       close_id: nil
     }}
  end

  @impl GenServer
  def handle_call(:open, from, %{status: :new} = state) do
    case open_port(state.options.executable) do
      {:ok, port} ->
        timer = Process.send_after(self(), :startup_timeout, max(state.options.deadline - now(), 0))

        {:noreply,
         %{
           state
           | port: port,
             waiter: from,
             start_ref: Process.monitor(elem(from, 0)),
             startup_timer: timer,
             status: :starting
         }}

      :error ->
        {:stop, :normal, {:error, Error.new(:transport_unavailable)}, state}
    end
  end

  def handle_call(:session, _from, %{status: :ready} = state) do
    {:reply,
     {:ok, %Session{client: Wotex.BLE.BlueZ, handle: state.handle, timeout: state.options.timeout}},
     state}
  end

  def handle_call({reference, :close}, from, %{handle: %{reference: reference}} = state) do
    {:noreply, close(state, :disconnected, from)}
  end

  def handle_call(
        {reference, operation, parameters, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      )
      when operation in ["discover", "read", "write", "health"] and is_map(parameters) and
             is_integer(deadline) do
    cond do
      deadline <= now() -> {:reply, {:error, Error.new(:timeout)}, state}
      map_size(state.pending) >= 64 -> {:reply, {:error, Error.new(:busy)}, state}
      true -> {:noreply, admit(state, from, parameters, deadline, operation)}
    end
  end

  def handle_call(
        {reference, :pair, policy, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      )
      when is_map(policy) and is_integer(deadline) do
    cond do
      deadline <= now() ->
        {:reply, {:error, Error.new(:timeout)}, state}

      map_size(state.pending) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        {:noreply,
         admit(state, from, %{"capability" => policy.capability}, deadline, "pair", policy)}
    end
  end

  def handle_call(
        {reference, :subscribe, config, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      ) do
    cond do
      deadline <= now() ->
        {:reply, {:error, Error.new(:timeout)}, state}

      map_size(state.pending) >= 64 or subscription_count(state) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        token = make_ref()

        case SubscriptionOwner.start(state.handle, config, from, token, deadline) do
          {:ok, pid} ->
            {:noreply, admit(state, {pid, token}, config.parameters, deadline, "subscribe")}

          _ ->
            {:reply, {:error, Error.new(:transport_error)}, state}
        end
    end
  end

  def handle_call(_, _from, state), do: {:reply, {:error, Error.new(:invalid_handle)}, state}

  @impl GenServer
  def handle_cast(
        {reference, :unsubscribe, pid, from},
        %{handle: %{reference: reference}, status: :ready} = state
      ),
      do: {:noreply, cancel_subscription(state, pid, from)}

  def handle_cast({_, operation, _, from}, state) when operation == :unsubscribe do
    GenServer.reply(from, {:error, Error.new(:disconnected)})
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({port, {:data, {:eol, data}}}, %{port: port, buffer: buffer} = state) do
    decoded =
      if byte_size(buffer) + byte_size(data) < 131_072,
        do: Frame.decode(buffer <> data),
        else: :limit

    case decoded do
      :limit -> {:noreply, close(state, :response_limit)}
      {:ok, frame} -> frame(frame, %{state | buffer: <<>>})
      :error -> {:noreply, close(state, :invalid_response)}
    end
  end

  def handle_info({port, {:data, {:noeol, data}}}, %{port: port} = state) do
    if byte_size(state.buffer) + byte_size(data) < 131_072,
      do: {:noreply, %{state | buffer: state.buffer <> data}},
      else: {:noreply, close(state, :response_limit)}
  end

  def handle_info({port, {:exit_status, _}}, %{port: port} = state) do
    state = if state.status == :closing, do: state, else: close(state, :disconnected)
    finish(state)
  end

  def handle_info(:startup_timeout, %{status: status} = state) when status in [:starting, :opening],
    do: {:noreply, close(state, :timeout)}

  def handle_info({:deadline, id}, state) do
    cond do
      Map.has_key?(state.pending, id) and state.pending[id].operation == "unsubscribe" ->
        {:noreply, close(%{state | cleanup_grace: 350}, :cleanup_timeout)}

      state.active == id ->
        {:noreply, close(state, expiry_code(state.pending[id].operation))}

      Map.has_key?(state.pending, id) ->
        {:noreply, complete(state, id, {:error, Error.new(:timeout)})}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:agent_decision, token, result}, %{policy: %{token: token}} = state),
    do: {:noreply, answer_policy(state, result)}

  def handle_info({:agent_timeout, token}, %{policy: %{token: token}} = state),
    do: {:noreply, answer_policy(state, {:ok, %{"action" => "reject"}})}

  def handle_info({:DOWN, monitor, :process, _, _}, %{policy: %{monitor: monitor}} = state),
    do: {:noreply, answer_policy(state, {:ok, %{"action" => "reject"}})}

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    if ref in [state.owner_ref, state.start_ref],
      do: {:noreply, close(state, :disconnected)},
      else: {:noreply, caller_down(state, ref)}
  end

  def handle_info(:terminate_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-TERM")
    Process.send_after(self(), :kill_bridge, 100)
    {:noreply, %{state | close_result: {:error, Error.new(:cleanup_timeout)}}}
  end

  def handle_info(:kill_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-KILL")
    finish(state)
  end

  def handle_info({:EXIT, pid, _}, %{options: %{owner: pid}} = state),
    do: {:noreply, close(state, :disconnected)}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{status: state.status, pending: map_size(state.pending)}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  @impl GenServer
  def terminate(_, state) do
    drop_policy(state)
    if state.port && Port.info(state.port), do: Port.close(state.port)
    :ok
  end

  defp call(pid, request) do
    GenServer.call(pid, request, :infinity)
  catch
    :exit, _ -> {:error, Error.new(:disconnected)}
  end

  defp open_port(executable) do
    script = Path.join(to_string(:code.priv_dir(:wotex_ble)), "bluez/bridge.py")

    {:ok,
     Port.open({:spawn_executable, executable}, [
       :binary,
       :exit_status,
       {:line, 131_071},
       args: ["-s", "-E", "-B", script],
       env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
     ])}
  rescue
    _ -> :error
  end

  defp frame(
         %{"version" => 1, "event" => "ready", "backend" => "dbus-next", "revision" => "0.2.3"} =
           frame,
         %{status: :starting} = state
       )
       when map_size(frame) == 4 do
    remaining = state.options.deadline - now()

    if remaining > 0 do
      request(state.port, "open", "open", state.options.parameters, remaining)
      {:noreply, %{state | status: :opening}}
    else
      {:noreply, close(state, :timeout)}
    end
  end

  defp frame(%{"id" => "open"} = frame, %{status: :opening} = state) do
    case timed_parse(frame, "open", state.options.deadline) do
      :expired ->
        {:noreply, close(state, :timeout)}

      {:ok, %{"generation" => generation}} ->
        Process.cancel_timer(state.startup_timer)
        Process.demonitor(state.start_ref, [:flush])
        GenServer.reply(state.waiter, {:ok, state.handle})

        {:noreply,
         %{state | status: :ready, waiter: nil, start_ref: nil, discovery_generation: generation}}

      {:error, error} ->
        {:noreply, close(state, error.code)}

      :invalid ->
        {:noreply, close(state, :invalid_response)}
    end
  end

  defp frame(%{"id" => id} = frame, %{status: :ready, policy_control: id} = state)
       when is_binary(id) do
    case Response.parse(frame, "agent_reply") do
      {:ok, nil} -> {:noreply, %{state | policy_control: nil}}
      _ -> {:noreply, close(state, :pairing_rejected)}
    end
  end

  defp frame(%{"subscription_id" => id} = frame, %{status: :ready} = state) do
    subscription = state.subscriptions[id]
    binding = if subscription, do: subscription.binding, else: nil

    case Stream.report(frame, binding) do
      :invalid ->
        {:noreply, close(state, :invalid_response)}

      event ->
        if subscription, do: send(subscription.pid, {:ble_stream, id, event})
        {:noreply, state}
    end
  end

  defp frame(%{"id" => wire} = frame, %{status: :ready} = state) when is_binary(wire) do
    case Map.fetch(state.wires, wire) do
      {:ok, id} when id == state.active ->
        active_frame(frame, id, state)

      {:ok, id} ->
        if state.pending[id].operation == "unsubscribe",
          do: accept_unsubscribe(state, id, frame),
          else: {:noreply, close(state, :invalid_response)}

      :error ->
        {:noreply, close(state, :invalid_response)}
    end
  end

  defp frame(%{"id" => id} = frame, %{status: :closing, close_id: id} = state)
       when is_binary(id) do
    case Response.parse(frame, "close") do
      {:ok, nil} -> {:noreply, %{state | close_result: :ok}}
      {:error, _} = error -> {:noreply, %{state | close_result: error}}
      _ -> {:noreply, %{state | close_result: {:error, Error.new(:invalid_response)}}}
    end
  end

  defp frame(_, %{status: :closing} = state), do: {:noreply, state}
  defp frame(_, state), do: {:noreply, close(state, :invalid_response)}

  defp active_frame(
         %{"version" => 1, "id" => _, "event" => "write_submitted"} = frame,
         id,
         %{status: :ready, active: id} = state
       )
       when map_size(frame) == 3 and is_reference(id) do
    case state.pending[id] do
      %{operation: "write", submitted: false, deadline: deadline} when is_integer(deadline) ->
        if now() < deadline do
          {:noreply, put_in(state.pending[id].submitted, true)}
        else
          {:noreply, close(state, :timeout)}
        end

      _ ->
        {:noreply, close(state, :invalid_response)}
    end
  end

  defp active_frame(
         %{"version" => 1, "id" => _, "event" => "agent_challenge", "challenge" => challenge} =
           frame,
         id,
         %{status: :ready, active: id, policy: nil, policy_control: nil} = state
       )
       when map_size(frame) == 4 and is_reference(id) do
    pending = state.pending[id]

    with "pair" <- pending.operation,
         {:ok, challenge} <-
           Pairing.challenge(challenge, state.options.parameters["peer"], pending.deadline, now()) do
      {:noreply, start_policy(state, id, pending.policy, challenge)}
    else
      _ -> {:noreply, close(state, :invalid_response)}
    end
  end

  defp active_frame(frame, id, state) do
    pending = state.pending[id]

    case timed_parse(frame, pending.operation, pending.deadline) do
      :expired ->
        {:noreply, close(state, expiry_code(pending.operation))}

      :invalid ->
        {:noreply, close(state, :invalid_response)}

      {:error, %Error{code: code} = error}
      when code in [
             :timeout,
             :disconnected,
             :owner_changed,
             :peer_changed,
             :invalid_response,
             :transport_error
           ] ->
        error = mark_unknown_write_effect(error, pending)
        {:noreply, close(complete(state, id, {:error, error}), code)}

      {:ok, %{subscription_id: _} = binding} ->
        accept_subscription(state, id, binding)

      {:ok, %{paired: true}} ->
        accept_pair(state, id)

      {:ok, %{connected: true, services_resolved: true} = health} ->
        {:noreply, advance(complete(state, id, {:ok, health}))}

      {:ok, page} when is_map(page) ->
        accept_page(state, id, page)

      {:ok, :written} ->
        accept_write(state, id)

      {:ok, value} when is_binary(value) ->
        {:noreply, advance(complete(state, id, {:ok, value}))}

      {:error, error} ->
        error = mark_unknown_submitted_effect(error, pending)
        {:noreply, advance(complete(state, id, {:error, error}))}
    end
  end

  defp mark_unknown_write_effect(error, %{operation: "write"}), do: Error.unknown_effect(error)
  defp mark_unknown_write_effect(error, _), do: error

  defp mark_unknown_submitted_effect(error, %{submitted: true}), do: Error.unknown_effect(error)
  defp mark_unknown_submitted_effect(error, _), do: error

  defp accept_unsubscribe(state, id, frame) do
    case timed_parse(frame, "unsubscribe", state.pending[id].deadline) do
      {:ok, nil} ->
        native_id = state.pending[id].parameters["subscription_id"]
        {:noreply, complete(retire_subscription(state, native_id), id, :ok)}

      {:error, error} ->
        {:noreply, close(complete(state, id, {:error, error}), error.code)}

      _ ->
        {:noreply, close(%{state | cleanup_grace: 350}, :cleanup_timeout)}
    end
  end

  defp accept_subscription(state, id, binding) do
    pending = state.pending[id]

    if Stream.matches?(binding, pending.wire_id, pending.parameters) do
      pid = elem(pending.from, 0)
      record = %{pid: pid, monitor: Process.monitor(pid), binding: binding, closing: false}
      state = %{state | subscriptions: Map.put(state.subscriptions, pending.wire_id, record)}
      {:noreply, advance(complete(state, id, {:ok, binding}))}
    else
      {:noreply, close(state, :invalid_response)}
    end
  end

  defp subscription_count(state),
    do:
      map_size(state.subscriptions) +
        Enum.count(state.pending, fn {_, item} -> item.operation == "subscribe" end)

  defp cancel_subscription(state, pid, from) do
    case Enum.find(state.subscriptions, fn {_, item} -> item.pid == pid end) do
      {id, %{closing: false}} ->
        if map_size(state.pending) < 64 do
          state = put_in(state.subscriptions[id].closing, true)
          admit(state, from, %{"subscription_id" => id}, now() + 600, "unsubscribe")
        else
          close(state, :busy)
        end

      {_, _} ->
        state

      nil ->
        cancel_starting(state, pid, from)
    end
  end

  defp cancel_starting(state, pid, from) do
    case Enum.find(state.pending, fn {_, item} ->
           item.operation == "subscribe" and elem(item.from, 0) == pid
         end) do
      {id, _} when id == state.active ->
        close(state, :disconnected)

      {id, _} ->
        state = complete(state, id, {:error, Error.new(:disconnected)})
        GenServer.reply(from, :ok)
        advance(state)

      nil ->
        GenServer.reply(from, :ok)
        state
    end
  end

  defp retire_subscription(state, id) do
    case Map.pop(state.subscriptions, id) do
      {nil, _} ->
        state

      {item, remaining} ->
        Process.demonitor(item.monitor, [:flush])
        %{state | subscriptions: remaining}
    end
  end

  defp accept_pair(state, id) do
    if is_nil(state.policy) and is_nil(state.policy_control),
      do: {:noreply, advance(complete(state, id, {:ok, %{paired: true}}))},
      else: {:noreply, close(state, :invalid_response)}
  end

  defp accept_write(state, id) do
    if state.pending[id].submitted,
      do: {:noreply, advance(complete(state, id, {:ok, :written}))},
      else: {:noreply, close(state, :invalid_response)}
  end

  defp timed_parse(frame, operation, deadline) do
    if now() < deadline,
      do: Response.parse(frame, operation),
      else: :expired
  end

  defp accept_page(state, id, page) do
    current = state.discovery_generation
    continuation? = not is_nil(state.pending[id].parameters["cursor"])

    if page.generation < current or (continuation? and page.generation != current) do
      {:noreply, close(state, :invalid_response)}
    else
      updated = complete(%{state | discovery_generation: page.generation}, id, {:ok, page})
      {:noreply, advance(updated)}
    end
  end

  defp admit(state, from, parameters, deadline, operation, policy \\ nil) do
    id = make_ref()

    pending = %{
      from: from,
      operation: operation,
      policy: policy,
      submitted: false,
      wire_id: nil,
      parameters: parameters,
      deadline: deadline,
      monitor: Process.monitor(elem(from, 0)),
      timer: Process.send_after(self(), {:deadline, id}, max(deadline - now(), 0))
    }

    state = %{state | pending: Map.put(state.pending, id, pending)}

    if operation == "unsubscribe" do
      issue(state, id, pending)
    else
      advance(%{state | queue: :queue.in(id, state.queue)})
    end
  end

  defp advance(%{active: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, id}, queue} ->
        state = %{state | queue: queue}

        case Map.fetch(state.pending, id) do
          :error -> advance(state)
          {:ok, pending} -> dispatch(state, id, pending)
        end

      {:empty, _} ->
        state
    end
  end

  defp advance(state), do: state

  defp dispatch(state, id, pending) do
    remaining = pending.deadline - now()

    if remaining <= 0 do
      updated = complete(state, id, {:error, Error.new(:timeout)})
      advance(updated)
    else
      state = issue(state, id, pending)
      if state.status == :ready, do: %{state | active: id}, else: state
    end
  end

  defp issue(%{counter: counter} = state, _, _) when counter == 0xFFFF_FFFF_FFFF_FFFF,
    do: close(state, :request_id_exhausted)

  defp issue(state, id, pending) do
    wire = Integer.to_string(state.counter + 1)

    request(
      state.port,
      wire,
      pending.operation,
      pending.parameters,
      max(pending.deadline - now(), 1)
    )

    %{
      state
      | counter: state.counter + 1,
        wires: Map.put(state.wires, wire, id),
        pending: Map.put(state.pending, id, %{pending | wire_id: wire})
    }
  end

  defp complete(state, id, result) do
    state = if state.active == id, do: drop_policy(state), else: state
    {pending, remaining} = Map.pop(state.pending, id)
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    GenServer.reply(pending.from, result)

    %{
      state
      | pending: remaining,
        wires: Map.delete(state.wires, pending.wire_id),
        queue: :queue.filter(&(&1 != id), state.queue),
        active: if(state.active == id, do: nil, else: state.active)
    }
  end

  defp caller_down(state, monitor) do
    case Enum.find(state.pending, fn {_, pending} -> pending.monitor == monitor end) do
      {_id, %{operation: "unsubscribe"}} ->
        close(%{state | cleanup_grace: 350}, :disconnected)

      {id, _} when id == state.active ->
        close(state, :disconnected)

      {id, _} ->
        complete(state, id, {:error, Error.new(:disconnected)})

      nil ->
        case Enum.find(state.subscriptions, fn {_, item} -> item.monitor == monitor end) do
          {_, item} -> cancel_subscription(state, item.pid, {self(), make_ref()})
          nil -> state
        end
    end
  end

  defp close(state, code, from \\ nil)

  defp close(%{status: :closing} = state, _, nil), do: state

  defp close(%{status: :closing, close_from: waiters} = state, _, from) do
    if length(waiters) < 64 do
      %{state | close_from: [from | waiters]}
    else
      GenServer.reply(from, {:error, Error.new(:busy)})
      state
    end
  end

  defp close(state, code, from) do
    Enum.each(state.subscriptions, fn {id, item} ->
      send(item.pid, {:ble_stream, id, {:error, Error.new(code)}})
    end)

    state = drop_policy(state)
    if state.waiter, do: GenServer.reply(state.waiter, {:error, Error.new(code)})

    state =
      Enum.reduce(Map.keys(state.pending), state, fn id, acc ->
        error = Error.new(code)

        error =
          if acc.active == id and acc.pending[id].operation == "write",
            do: Error.unknown_effect(error),
            else: error

        complete(acc, id, {:error, error})
      end)

    request(state.port, "close", "close", %{}, max(state.cleanup_grace - 200, 1))
    Process.send_after(self(), :terminate_bridge, max(state.cleanup_grace - 150, 0))

    %{
      state
      | status: :closing,
        waiter: nil,
        pending: %{},
        queue: :queue.new(),
        active: nil,
        close_id: "close",
        close_from: if(from, do: [from], else: [])
    }
  end

  defp finish(state) do
    Enum.each(state.close_from, &GenServer.reply(&1, state.close_result))
    {:stop, :normal, %{state | close_from: []}}
  end

  defp request(port, id, operation, parameters, timeout) do
    Port.command(
      port,
      Jason.encode!(%{
        version: 1,
        id: id,
        operation: operation,
        parameters: parameters,
        timeout_ms: min(timeout, 60_000)
      }) <> "\n"
    )
  rescue
    _ -> false
  end

  defp signal_port(port, signal) do
    case port && Port.info(port, :os_pid) do
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

  defp start_policy(state, id, policy, challenge) do
    owner = self()
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        result = Pairing.invoke(policy, challenge)
        send(owner, {:agent_decision, token, result})
      end)

    timer =
      Process.send_after(self(), {:agent_timeout, token}, max(challenge.deadline_ms - now(), 0))

    %{
      state
      | policy: %{
          id: id,
          pid: pid,
          monitor: monitor,
          token: token,
          timer: timer,
          challenge_id: challenge.id,
          deadline: challenge.deadline_ms
        }
    }
  end

  defp answer_policy(%{counter: counter} = state, _) when counter == 0xFFFF_FFFF_FFFF_FFFF,
    do: close(state, :request_id_exhausted)

  defp answer_policy(state, result) do
    decision =
      case result do
        {:ok, decision} ->
          if now() < state.policy.deadline, do: decision, else: %{"action" => "reject"}

        _ ->
          %{"action" => "reject"}
      end

    id = "agent-" <> Integer.to_string(state.counter + 1)
    parameters = %{"challenge_id" => state.policy.challenge_id, "decision" => decision}

    request(
      state.port,
      id,
      "agent_reply",
      parameters,
      max(state.pending[state.active].deadline - now(), 1)
    )

    updated = drop_policy(state)
    %{updated | counter: state.counter + 1, policy_control: id}
  end

  defp drop_policy(%{policy: nil} = state), do: state

  defp drop_policy(state) do
    Process.cancel_timer(state.policy.timer)
    Process.demonitor(state.policy.monitor, [:flush])
    Process.exit(state.policy.pid, :kill)
    %{state | policy: nil}
  end

  defp expiry_code("pair"), do: :pairing_rejected
  defp expiry_code(_), do: :timeout

  defp now, do: System.monotonic_time(:millisecond)
end
