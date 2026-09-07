defmodule Wotex.Runtime.Subscription do
  @moduledoc """
  Caller-supervised process for one Property observation or Event subscription.

  Started only through a child specification built by
  `Wotex.Runtime.ConsumedThing`. Initialization returns immediately and the
  protocol subscription is opened in a continuation, so a slow or unreachable
  transport never blocks the consumer's supervisor. Credentials are resolved
  immediately before the open and close exchanges and are never kept in state.

  The receiver is monitored: if it exits, the subscription unsubscribes and
  stops. A linked transport process that exits, or a transport status of
  `:session_lost` or `:transport_down`, is reported to the receiver before the
  process stops with a `:shutdown` reason, leaving the restart decision to the
  consumer's supervisor. An optional `max_queue_length` bounds the receiver's
  mailbox: when exceeded, deliveries are dropped or the subscription stops
  according to the `overflow` policy.

  Every event delivered to the receiver is `{:wotex_runtime, id, event}` with
  `event` being `{:ok, value, meta}`, `{:error, %Wotex.Runtime.Error{}}`, or
  `{:status, status}`.
  """

  use GenServer

  alias Wotex.Runtime.{Context, Error, ExecutionContext, PortCall, Telemetry}

  @type status :: :reconnected | :session_lost | :transport_down | :receiver_down | :overloaded
  @type event :: {:ok, term(), map()} | {:error, Error.t()} | {:status, status()}

  @doc false
  @spec start_link(%{required(:name) => GenServer.name() | nil, optional(atom()) => term()}) ::
          GenServer.on_start()
  def start_link(%{name: nil} = init), do: GenServer.start_link(__MODULE__, init)
  def start_link(%{name: name} = init), do: GenServer.start_link(__MODULE__, init, name: name)

  @doc "Stops a subscription after requesting protocol unsubscription."
  @spec stop(GenServer.server(), timeout()) :: :ok | {:error, Error.t()}
  def stop(server, timeout \\ 5_000), do: GenServer.call(server, :stop, timeout)

  @impl GenServer
  def init(init) do
    Process.flag(:trap_exit, true)
    state = Map.merge(init, %{handle: nil, closed?: false, active?: false, monitor: nil})
    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    case monitor_receiver(state) do
      {:ok, monitored} -> open(monitored)
      {:error, reason} -> {:stop, {:shutdown, reason}, %{state | closed?: true}}
    end
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    result = close(state)
    {:stop, :normal, result, %{state | closed?: true}}
  end

  @impl GenServer
  def handle_info({:wotex_transport_frame, frame}, state) do
    {module, config} = state.transport

    event =
      if function_exported?(module, :decode_frame, 3) do
        module
        |> PortCall.invoke(
          :decode_frame,
          [frame, state.start_request, config],
          :subscription,
          identity(state)
        )
        |> normalize_frame(state)
      else
        {:error,
         Error.new(
           :undecodable_frame,
           :subscription,
           "transport delivered a frame without decode_frame/3",
           identity(state)
         )}
      end

    deliver(event, state)
  end

  def handle_info({:wotex_transport, delivery}, state) do
    deliver(normalize_delivery(delivery, state), state)
  end

  def handle_info({:wotex_transport_status, status}, state) when status in [:reconnected] do
    Telemetry.execute([:subscription, :status], Map.put(identity(state), :status, status))
    forward({:status, status}, state)
    {:noreply, state}
  end

  def handle_info({:wotex_transport_status, status}, state)
      when status in [:session_lost, :transport_down] do
    stop_after_status(status, state)
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    Telemetry.execute([:subscription, :status], Map.put(identity(state), :status, :receiver_down))
    {:stop, {:shutdown, :receiver_down}, %{state | monitor: nil}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: stop_after_status(:transport_down, state)

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(reason, state) do
    Telemetry.execute([:subscription, :close], Map.put(identity(state), :reason, reason))

    cond do
      state.closed? -> :ok
      state.active? -> close(state)
      true -> :ok
    end
  end

  defp open(state) do
    case subscribe(state) do
      {:ok, handle} ->
        Telemetry.execute([:subscription, :open], identity(state))
        {:noreply, %{state | handle: handle, active?: true}}

      {:error, error} ->
        forward({:error, error}, state)
        {:stop, {:shutdown, error}, %{state | closed?: true}}
    end
  end

  defp deliver(:ignore, state), do: {:noreply, state}

  defp deliver(event, state) do
    case overflow(state) do
      :ok ->
        forward(event, state)

        Telemetry.execute(
          [:subscription, :deliver],
          Map.put(identity(state), :outcome, elem(event, 0))
        )

        {:noreply, state}

      {:drop, queue_length} ->
        Telemetry.execute([:subscription, :drop], %{queue_length: queue_length}, identity(state))
        {:noreply, state}

      {:stop, queue_length} ->
        Telemetry.execute([:subscription, :drop], %{queue_length: queue_length}, identity(state))
        forward({:status, :overloaded}, state)
        {:stop, {:shutdown, :overloaded}, state}
    end
  end

  defp overflow(%{max_queue_length: nil}), do: :ok

  defp overflow(%{max_queue_length: max, overflow: policy} = state) do
    case receiver_pid(state) do
      pid when is_pid(pid) ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, length} when length >= max -> {policy, length}
          _other -> :ok
        end

      _not_found ->
        :ok
    end
  end

  defp stop_after_status(status, state) do
    Telemetry.execute([:subscription, :status], Map.put(identity(state), :status, status))
    forward({:status, status}, state)
    {:stop, {:shutdown, status}, state}
  end

  defp forward(event, state), do: send(state.receiver, {:wotex_runtime, state.id, event})

  defp monitor_receiver(state) do
    case receiver_pid(state) do
      pid when is_pid(pid) ->
        if Process.alive?(pid),
          do: {:ok, %{state | monitor: Process.monitor(pid)}},
          else: {:error, :receiver_down}

      _not_found ->
        {:error, :receiver_down}
    end
  end

  defp receiver_pid(%{receiver: pid}) when is_pid(pid), do: pid
  defp receiver_pid(%{receiver: name}) when is_atom(name), do: Process.whereis(name)

  defp normalize_frame({:ok, value, meta}, _state) when is_map(meta), do: {:ok, value, meta}
  defp normalize_frame(:ignore, _state), do: :ignore

  defp normalize_frame({:error, external}, state) do
    {:error,
     :undecodable_frame
     |> Error.new(:subscription, "transport could not decode a frame", identity(state))
     |> Error.with_cause(external)}
  end

  defp normalize_frame(_invalid, state) do
    {:error,
     Error.new(
       :invalid_transport_return,
       :subscription,
       "decode_frame/3 returned an invalid value",
       identity(state)
     )}
  end

  defp normalize_delivery({:ok, value, meta}, _state) when is_map(meta), do: {:ok, value, meta}

  defp normalize_delivery({:error, external}, state) do
    {:error,
     :transport_delivery_failed
     |> Error.new(:subscription, "transport reported a delivery failure", identity(state))
     |> Error.with_cause(external)}
  end

  defp normalize_delivery(_invalid, state) do
    {:error,
     Error.new(
       :invalid_transport_delivery,
       :subscription,
       "transport delivery must be {:ok, value, meta} or {:error, reason}",
       identity(state)
     )}
  end

  defp subscribe(state) do
    with {:ok, execution_context} <-
           resolve_credentials(
             state.credentials,
             state.start_security,
             state.start_request.form,
             state.context,
             state
           ),
         {module, config} = state.transport do
      module
      |> PortCall.invoke(
        :subscribe,
        [state.start_request, self(), execution_context, config],
        :subscription,
        identity(state)
      )
      |> normalize_subscribe(state)
    end
  end

  defp close(state) do
    {module, config} = state.transport

    {execution_context, credential_error} =
      case resolve_credentials(
             state.credentials,
             state.stop_security,
             state.stop_request.form,
             state.context,
             state
           ) do
        {:ok, execution_context} -> {execution_context, nil}
        {:error, error} -> {ExecutionContext.new(state.context, nil), error}
      end

    result =
      module
      |> PortCall.invoke(
        :unsubscribe,
        [state.handle, state.stop_request, execution_context, config],
        :subscription,
        identity(state)
      )
      |> normalize_unsubscribe(state)

    case {result, credential_error} do
      {:ok, nil} -> :ok
      {:ok, error} -> {:error, error}
      {{:error, error}, _credential_error} -> {:error, error}
    end
  end

  defp resolve_credentials({module, config}, security, form, %Context{} = context, state) do
    case PortCall.invoke(
           module,
           :resolve,
           [security, form, context, config],
           :credentials,
           identity(state)
         ) do
      {:ok, credential} ->
        {:ok, ExecutionContext.new(context, credential)}

      {:error, %Error{code: :port_exception} = error} ->
        {:error, error}

      {:error, external} ->
        {:error,
         :credential_resolution_failed
         |> Error.new(:credentials, "credential resolution failed", identity(state))
         |> Error.with_cause(external)}

      _invalid ->
        {:error,
         Error.new(
           :invalid_credentials_return,
           :credentials,
           "credential port returned an invalid value",
           identity(state)
         )}
    end
  end

  defp normalize_subscribe({:ok, handle}, _state), do: {:ok, handle}

  defp normalize_subscribe({:error, %Error{code: :port_exception} = error}, _state),
    do: {:error, error}

  defp normalize_subscribe({:error, external}, state) do
    {:error,
     :transport_subscribe_failed
     |> Error.new(:subscription, "transport subscription failed", identity(state))
     |> Error.with_cause(external)}
  end

  defp normalize_subscribe(_invalid, state) do
    {:error,
     Error.new(
       :invalid_transport_return,
       :subscription,
       "transport returned an invalid value",
       identity(state)
     )}
  end

  defp normalize_unsubscribe(:ok, _state), do: :ok

  defp normalize_unsubscribe({:error, %Error{code: :port_exception} = error}, _state),
    do: {:error, error}

  defp normalize_unsubscribe({:error, external}, state) do
    {:error,
     :transport_unsubscribe_failed
     |> Error.new(:subscription, "transport unsubscription failed", identity(state))
     |> Error.with_cause(external)}
  end

  defp normalize_unsubscribe(_invalid, state) do
    {:error,
     Error.new(
       :invalid_transport_return,
       :subscription,
       "transport returned an invalid value",
       identity(state)
     )}
  end

  defp identity(state) do
    %{
      subscription_id: state.id,
      request_id: Context.request_id(state.context),
      operation: state.start_request.operation,
      affordance_type: state.start_request.affordance_type,
      affordance_name: state.start_request.affordance_name
    }
  end
end
