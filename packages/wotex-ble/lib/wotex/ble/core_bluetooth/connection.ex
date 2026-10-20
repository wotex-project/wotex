defmodule Wotex.BLE.CoreBluetooth.Connection do
  @moduledoc """
  Owns one bounded CoreBluetooth native generation.

  Handles bind a local process, private reference and consumer-supplied generation.
  At most 64 calls are admitted, including one active native procedure. Queued
  deadlines and caller loss remove unsent work; active loss retires the entire
  generation. Close joins native retirement and guardian exit within 1,500 ms.
  The consumer must keep admitted artifact paths immutable through execution.

  Explicit streams share 64 native report credits across sixteen live owners.
  A public claim fences early reports; exact receiver admission returns credit.
  Cancellation fences delivery before native stop and may close the generation
  when another operation holds native control. At most 256 retired handles are
  retained for exact idempotent cancellation within this generation.
  """
  use GenServer

  alias Wotex.BLE.{Address, Error}
  alias Wotex.BLE.BlueZ.{Artifacts, Frame, SubscriptionOwner}
  alias Wotex.BLE.CoreBluetooth.{Options, ReportFlow, Response, Stream}

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

  @doc "Starts a bounded receiver-owned notification or indication stream."
  @spec subscribe(term(), term(), term()) :: {:ok, Wotex.BLE.Subscription.t()} | {:error, Error.t()}
  def subscribe(handle, request, timeout) do
    with :ok <- valid_handle(handle),
         {:ok, config} <- Stream.options(request, timeout, self()) do
      result =
        call(
          handle.pid,
          {:subscribe, handle, request, timeout, now() + config.timeout},
          config.timeout + 1700
        )

      case result do
        {:ok, subscription} ->
          GenServer.cast(handle.pid, {:subscription_claimed, handle, subscription})

        _ ->
          :ok
      end

      result
    end
  end

  @doc "Fences delivery and joins retirement of a same-generation subscription."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(handle, subscription) do
    with :ok <- valid_handle(handle),
         true <- Stream.handle?(subscription),
         true <-
           subscription.session_reference === handle.reference and
             subscription.generation === handle.generation do
      case SubscriptionOwner.cancel(subscription, 1700, false) do
        {:error, %Error{code: :disconnected}} ->
          call(handle.pid, {:retire_lost_subscription, handle, subscription}, 1700)

        result ->
          result
      end
    else
      _ -> {:error, Error.new(:invalid_subscription)}
    end
  end

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
       subscriptions: %{},
       retired_subscriptions: %{},
       flow: ReportFlow.new(options.generation),
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

  def handle_call({:subscribe, handle, request, timeout, deadline}, from, %{phase: :ready} = state) do
    with true <- handle === state.handle,
         true <- deadline > now(),
         true <- length(state.queue) + if(state.active, do: 1, else: 0) < 64,
         true <- map_size(state.subscriptions) < 16,
         {:ok, config} <- Stream.options(request, timeout, elem(from, 0)),
         :ok <- selection(config.address, state.handle.generation),
         {:ok, route} <- route(config.address, state.routes),
         {:ok, _} <- Stream.mode(route, config.requested_mode),
         :ok <- available(state, route),
         true <-
           config.credit +
             Enum.reduce(state.subscriptions, 0, fn {_, item}, total ->
               total + item.config.credit
             end) <= 64 do
      token = make_ref()

      owner_config = Map.put(config, :establishing_caller, elem(from, 0))

      case SubscriptionOwner.start(state.handle, owner_config, {self(), token}, token, deadline) do
        {:ok, pid} ->
          parameters = %{
            "stream_version" => 1,
            "address" => %{"generation" => route.generation, "route" => route.route},
            "mode" => Atom.to_string(config.requested_mode),
            "credit" => config.credit
          }

          entry =
            stream_entry(:subscribe, parameters, {pid, token}, deadline)
            |> Map.merge(%{config: config, route: route})

          record = %{
            monitor: Process.monitor(pid),
            config: config,
            route: route,
            id: nil,
            waiter: from,
            caller: Process.monitor(elem(from, 0)),
            public_token: token,
            public_handle: nil,
            claimed: false,
            deadline: deadline,
            timer: nil,
            buffer: [],
            closing: false,
            retired: false
          }

          state = %{
            state
            | subscriptions: Map.put(state.subscriptions, pid, record),
              queue: Enum.concat(state.queue, [entry])
          }

          continue(dispatch(state))

        _ ->
          {:reply, {:error, Error.new(:transport_error)}, state}
      end
    else
      {:error, _} = error ->
        {:reply, error, state}

      false when handle !== state.handle ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      _ ->
        {:reply, {:error, Error.new(if(deadline <= now(), do: :timeout, else: :resource_limit))},
         state}
    end
  end

  def handle_call({:subscribe, handle, _, _, _}, _, state),
    do:
      {:reply,
       {:error, Error.new(if(handle === state.handle, do: :disconnected, else: :invalid_handle))},
       state}

  def handle_call(
        {:retire_lost_subscription, handle, %Wotex.BLE.Subscription{} = subscription},
        from,
        state
      ) do
    cond do
      handle !== state.handle ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      state.retired_subscriptions[{subscription.pid, subscription.reference}] === subscription ->
        {:reply, :ok, state}

      match?(%{public_handle: ^subscription}, state.subscriptions[subscription.pid]) and
          length(state.close_waiters) < 64 ->
        continue(
          close(%{state | close_waiters: [from | state.close_waiters]}, Error.new(:disconnected))
        )

      true ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}
    end
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
  def handle_cast(
        {:subscription_claimed, handle, %Wotex.BLE.Subscription{} = subscription},
        %{handle: handle, phase: :ready} = state
      ) do
    case state.subscriptions[subscription.pid] do
      %{public_handle: ^subscription, claimed: false} = item ->
        if now() < item.deadline do
          Process.demonitor(item.caller, [:flush])
          Process.cancel_timer(item.timer)
          Enum.each(Enum.reverse(item.buffer), &send(subscription.pid, &1))
          item = %{item | claimed: true, caller: nil, timer: nil, public_token: nil, buffer: []}
          {:noreply, %{state | subscriptions: Map.put(state.subscriptions, subscription.pid, item)}}
        else
          continue(close(state, Error.new(:timeout)))
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(
        {reference, :unsubscribe, pid, from},
        %{handle: %{reference: reference}, phase: :ready} = state
      ),
      do: continue(cancel_subscription(state, pid, from))

  def handle_cast({_, :unsubscribe, _, _}, state), do: {:noreply, state}
  def handle_cast(_, state), do: {:noreply, state}

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
    state = drop_starting(state, expired, :timeout)
    Enum.each(expired, &reply(&1, {:error, Error.new(:timeout)}))
    {:noreply, %{state | queue: queue}}
  end

  def handle_info({:subscription_claim_timeout, pid}, state) do
    if match?(%{claimed: false}, state.subscriptions[pid]),
      do: continue(close(state, Error.new(:timeout))),
      else: {:noreply, state}
  end

  def handle_info({token, result}, state) when is_reference(token) do
    case Enum.find(state.subscriptions, fn {_, item} ->
           item.public_token === token and item.waiter != nil
         end) do
      {pid, item} ->
        public_subscription(state, pid, item, result)

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    lost_subscriber = Enum.find(state.subscriptions, fn {_, item} -> item.caller == ref end)

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

      lost_subscriber ->
        {pid, _} = lost_subscriber
        continue(cancel_dead_caller(state, pid))

      Enum.any?(state.subscriptions, fn {_, item} -> item.monitor == ref end) ->
        continue(close(state, Error.new(:disconnected)))

      true ->
        {removed, queue} = Enum.split_with(state.queue, &(&1.monitor == ref))
        Enum.each(removed, &release/1)
        {:noreply, %{state | queue: queue}}
    end
  end

  def handle_info(
        {:ble_report_consumed, reference, pid, sequence, token},
        %{handle: %{reference: reference}, phase: :ready} = state
      ) do
    case state.subscriptions[pid] do
      %{id: id, closing: false} when id != nil ->
        {ack, flow} = ReportFlow.consume(state.flow, pid, id, sequence, token)
        continue(acknowledge(%{state | flow: flow}, ack))

      _ ->
        {:noreply, state}
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
         true <-
           kind != :read or
             (not ReportFlow.used?(state.flow, route.route) and
                Enum.all?(state.subscriptions, fn {_, item} -> item.route.route != route.route end)),
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

  defp frame(%{phase: :closing} = state, %{"event" => event})
       when event in ["notification", "notification_retired"], do: state

  defp frame(state, %{"event" => "notification"} = frame) do
    case ReportFlow.report(state.flow, frame) do
      {:ok, pid, id, receipt, event, flow} ->
        state = %{state | flow: flow}
        message = {:ble_stream, id, receipt, event}

        case state.subscriptions[pid] do
          %{closing: false, claimed: true} ->
            send(pid, message)
            state

          %{closing: false} = item ->
            if length(item.buffer) < item.config.credit,
              do: put_in(state.subscriptions[pid].buffer, [message | item.buffer]),
              else: close(state, Error.new(:invalid_response))

          _ ->
            state
        end

      _ ->
        close(state, Error.new(:invalid_response))
    end
  end

  defp frame(
         %{active: %{kind: :unsubscribe, from: {pid, _}, parameters: %{"subscription_id" => id}}} =
           state,
         %{"event" => "notification_retired", "subscription_id" => id} = frame
       ) do
    case ReportFlow.retire(state.flow, frame) do
      {:ok, ^id, ^pid, ack, flow} ->
        state = put_in(state.subscriptions[pid].retired, true)
        acknowledge(%{state | flow: flow}, ack)

      _ ->
        close(state, Error.new(:invalid_response))
    end
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
    if error.code in @fatal or active.kind in [:open, :subscribe, :unsubscribe] or state.waiter do
      close(%{state | active: %{active | outcome: outcome}}, error)
    else
      reply(active, outcome)
      dispatch(%{state | active: nil})
    end
  end

  defp deliver_native(state, _, _), do: close(state, Error.new(:invalid_response))

  defp validated_result(%{kind: :subscribe} = active, {:ok, result}, _),
    do: Stream.binding(result, active.id, active.config, active.route)

  defp validated_result(%{kind: :unsubscribe}, {:ok, nil}, _), do: {:ok, :unsubscribed}

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

  defp success(%{active: %{kind: :subscribe, from: {pid, _}} = active} = state, binding) do
    case ReportFlow.open(state.flow, pid, binding) do
      {:ok, flow} ->
        state = put_in(state.subscriptions[pid].id, active.id)

        state =
          put_in(
            state.subscriptions[pid].timer,
            Process.send_after(
              self(),
              {:subscription_claim_timeout, pid},
              max(active.deadline - now(), 0)
            )
          )

        reply(active, {:ok, binding})
        dispatch(%{state | active: nil, flow: flow})

      _ ->
        close(state, Error.new(:invalid_response))
    end
  end

  defp success(%{active: %{kind: :unsubscribe, from: {pid, _}} = active} = state, :unsubscribed) do
    case state.subscriptions[pid] do
      %{retired: true} = item ->
        release_subscription(item)
        if item.waiter, do: GenServer.reply(item.waiter, {:error, Error.new(:disconnected)})
        reply(active, :ok)

        retired =
          if item.public_handle,
            do:
              Map.put(
                state.retired_subscriptions,
                {pid, item.public_handle.reference},
                item.public_handle
              ),
            else: state.retired_subscriptions

        dispatch(%{
          state
          | active: nil,
            subscriptions: Map.delete(state.subscriptions, pid),
            retired_subscriptions: retired
        })

      _ ->
        close(state, Error.new(:invalid_response))
    end
  end

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

        if entry.kind == :unsubscribe,
          do: close(state, Error.new(:disconnected)),
          else: dispatch(drop_starting(state, [entry]))

      entry.deadline <= now() ->
        state = drop_starting(state, [entry], :timeout)
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

  defp available(state, route) do
    if ReportFlow.used?(state.flow, route.route) or
         Enum.any?(state.subscriptions, fn {_, item} -> item.route.route == route.route end),
       do: {:error, Error.new(:not_permitted)},
       else: :ok
  end

  defp public_subscription(state, pid, item, {:ok, subscription} = result) do
    with true <- state.phase == :ready and now() < item.deadline,
         true <- Stream.handle?(subscription),
         true <- subscription.pid == pid and item.id != nil,
         true <- subscription.session_reference === state.handle.reference,
         true <- subscription.generation === state.handle.generation do
      GenServer.reply(item.waiter, result)
      item = %{item | waiter: nil, public_handle: subscription}
      {:noreply, %{state | subscriptions: Map.put(state.subscriptions, pid, item)}}
    else
      _ ->
        continue(
          close(state, Error.new(if(now() >= item.deadline, do: :timeout, else: :invalid_response)))
        )
    end
  end

  defp public_subscription(state, _, _, {:error, %Error{} = error}),
    do: continue(close(state, error))

  defp public_subscription(state, _, _, _), do: continue(close(state, Error.new(:invalid_response)))

  defp drop_starting(state, entries, code \\ :disconnected) do
    Enum.reduce(entries, state, fn
      %{kind: :subscribe, from: {pid, _}}, state ->
        {item, subscriptions} = Map.pop(state.subscriptions, pid)

        if item do
          release_subscription(item)
          if item.waiter, do: GenServer.reply(item.waiter, {:error, Error.new(code)})
        end

        %{state | subscriptions: subscriptions}

      _, state ->
        state
    end)
  end

  defp cancel_dead_caller(state, pid) do
    {removed, queue} =
      Enum.split_with(state.queue, fn entry ->
        entry.kind == :subscribe and elem(entry.from, 0) == pid
      end)

    if removed == [] do
      close(state, Error.new(:disconnected))
    else
      state = drop_starting(%{state | queue: queue}, removed)
      Enum.each(removed, &release/1)
      send(pid, {:ble_stream_closed, state.handle.reference, {:error, Error.new(:disconnected)}})
      dispatch(state)
    end
  end

  defp stream_entry(kind, parameters, from, deadline) do
    token = make_ref()

    %{
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
  end

  defp cancel_subscription(state, pid, from) do
    case state.subscriptions[pid] do
      nil ->
        GenServer.reply(from, :ok)
        state

      %{closing: true} ->
        state

      %{id: nil} = item ->
        state = put_in(state.subscriptions[pid].closing, true)

        if state.active && elem(state.active.from, 0) == pid do
          close(state, Error.new(:disconnected))
        else
          {removed, queue} = Enum.split_with(state.queue, &(elem(&1.from, 0) == pid))
          Enum.each(removed, &release/1)
          release_subscription(item)
          if item.waiter, do: GenServer.reply(item.waiter, {:error, Error.new(:disconnected)})
          GenServer.reply(from, :ok)
          dispatch(%{state | queue: queue, subscriptions: Map.delete(state.subscriptions, pid)})
        end

      %{id: id} ->
        state = put_in(state.subscriptions[pid].closing, true)

        if state.active do
          close(state, Error.new(:disconnected))
        else
          entry =
            stream_entry(
              :unsubscribe,
              %{"stream_version" => 1, "subscription_id" => id},
              from,
              now() + 500
            )

          dispatch(%{state | queue: [entry | state.queue]})
        end
    end
  end

  defp acknowledge(state, nil), do: state

  defp acknowledge(state, frame) do
    if send_control(state.port, frame), do: state, else: close(state, Error.new(:transport_error))
  end

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

    Enum.each(state.subscriptions, fn {pid, item} ->
      if item.waiter, do: GenServer.reply(item.waiter, {:error, error})
      release_subscription(item)
      outcome = if item.closing, do: result, else: {:error, error}
      send(pid, {:ble_stream_closed, state.handle.reference, outcome})
    end)

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

  defp release_subscription(item) do
    Process.demonitor(item.monitor, [:flush])
    if item.caller, do: Process.demonitor(item.caller, [:flush])
    if item.timer, do: Process.cancel_timer(item.timer)
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

  defp send_control(port, frame) do
    Port.command(port, Jason.encode!(frame) <> "\n", [:nosuspend])
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
