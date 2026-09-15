defmodule Wotex.Matter.RuntimeRelay do
  @moduledoc """
  Owns a Matter subscription route for one Runtime stream.

  This internal relay starts explicitly with a consumer-owned Runtime process,
  validates report paths and typed values, and retains at most 64 pending frames.
  Frame tokens bind decoding to the original owner, request and generation.
  Native report credit is returned only when that owner consumes a validated
  frame. A suspended relay or Runtime owner therefore retains its native credit.
  Owner death, overflow and terminal errors close the original subscription and
  controller; module loading starts no process or protocol activity.
  """

  use GenServer

  alias Wotex.Matter
  alias Wotex.Matter.{Address, Descriptor, Error, Native, Session, Subscription}
  alias Wotex.Matter.Native.Delivery
  alias Wotex.Matter.RuntimeRelay.{Frame, Handle}

  @opening_limit 64
  @default_owner_queue_limit 1_000
  @cleanup_timeout 1_000

  @doc false
  @spec start(
          pid(),
          String.t(),
          atom(),
          atom(),
          Address.t(),
          keyword(),
          keyword(),
          pos_integer()
        ) :: {:ok, Handle.t()} | {:error, Error.t()}
  def start(
        owner,
        request_id,
        operation,
        kind,
        %Address{} = address,
        client_options,
        stream_options,
        timeout
      )
      when is_pid(owner) and is_binary(request_id) and request_id != "" and
             operation in [:observeproperty, :subscribeevent] and
             kind in [:attribute, :event] and is_list(client_options) and
             is_list(stream_options) and is_integer(timeout) do
    init = %{
      state: :opening,
      owner: owner,
      request_id: request_id,
      operation: operation,
      kind: kind,
      address: address,
      client_options: client_options,
      stream_options: stream_options,
      timeout: timeout
    }

    case GenServer.start(__MODULE__, init, timeout: timeout + 250) do
      {:ok, pid} -> GenServer.call(pid, :handle)
      {:error, %Error{}} = error -> error
      {:error, {:shutdown, %Error{} = error}} -> {:error, error}
      {:error, _} -> {:error, Error.new(:subscription_failed)}
    end
  catch
    :exit, _ -> {:error, Error.new(:subscription_failed)}
  end

  def start(_, _, _, _, _, _, _, _), do: {:error, Error.new(:invalid_subscription)}

  @doc false
  @spec close(term()) :: :ok | {:error, Error.t()}
  def close(%Handle{pid: pid, generation: generation})
      when is_pid(pid) and is_binary(generation) do
    GenServer.call(pid, {:close, generation}, @cleanup_timeout + 250)
  catch
    :exit, _ -> :ok
  end

  def close(_), do: {:error, Error.new(:invalid_handle)}

  @doc false
  @spec decode(term(), String.t(), atom(), atom(), Address.t()) ::
          {:ok, term(), map()} | {:error, Error.t()} | :ignore
  def decode(
        %Frame{pid: pid, generation: generation, token: token, value: value},
        request_id,
        operation,
        kind,
        %Address{} = address
      )
      when is_pid(pid) and is_binary(generation) and is_reference(token) and
             is_binary(request_id) do
    GenServer.call(
      pid,
      {:decode, generation, token, value, request_id, operation, kind, address},
      1_000
    )
  catch
    :exit, _ -> :ignore
  end

  def decode(_, _, _, _, _), do: :ignore

  @impl GenServer
  def init(init) do
    relay = self()
    watcher = spawn(fn -> watch_owner(init.owner, relay) end)

    with true <- Process.alive?(init.owner),
         {:ok, native_request, owner_queue_limit} <-
           subscription_request(init.kind, init.address, init.stream_options),
         {:ok, session} <- Matter.connect(init.client_options),
         {:ok, subscription} <- subscribe(session, native_request) do
      bind(init, watcher, relay, session, subscription, owner_queue_limit)
    else
      false -> {:stop, {:shutdown, Error.new(:receiver_closed)}}
      {:error, %Error{} = error} -> {:stop, {:shutdown, error}}
    end
  end

  @impl GenServer
  def handle_call(:handle, _, %{state: :bound} = state) do
    {:reply, {:ok, %Handle{pid: self(), generation: state.generation}}, state}
  end

  def handle_call(:handle, _, state),
    do: {:reply, {:error, Error.new(:invalid_handle)}, state}

  def handle_call(
        {:decode, generation, token, value, request_id, operation, kind, address},
        {owner, _},
        %{owner: owner, generation: generation, state: :bound} = state
      ) do
    identity = {request_id, operation, kind, address}

    case Map.fetch(state.pending, token) do
      {:ok, {^identity, ^value, native_delivery}} ->
        acknowledge_native(native_delivery)
        {:reply, decode_delivery(value), %{state | pending: Map.delete(state.pending, token)}}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:decode, _, _, _, _, _, _, _}, _, state), do: {:reply, :ignore, state}

  def handle_call({:close, generation}, _, %{generation: generation} = state) do
    {result, state} = close_resources(%{state | state: :closing})
    {:stop, :normal, result, state}
  end

  def handle_call({:close, _}, _, state),
    do: {:reply, {:error, Error.new(:invalid_handle)}, state}

  @impl GenServer
  def handle_continue(:flush_opening, state) do
    opening = state.opening
    state = %{state | opening: []}

    Enum.reduce_while(opening, {:noreply, state}, fn message, {:noreply, current} ->
      case handle_info(message, current) do
        {:noreply, _} = result -> {:cont, result}
        result -> {:halt, result}
      end
    end)
  end

  @impl GenServer
  def handle_info(
        {:wotex_matter, reference,
         %Delivery{connection: connection, generation: generation, reference: reference} = delivery},
        %{
          reference: reference,
          state: :bound,
          session: %Session{
            client: Native,
            handle: %Native.Handle{pid: connection, generation: generation}
          }
        } = state
      ) do
    case delivery.value do
      {:ok, value, metadata} ->
        case project(value, metadata, state) do
          {:ok, payload, projected} -> enqueue({:ok, payload, projected}, state, delivery)
          {:error, %Error{} = error} -> terminate_stream(error, :transport_down, state)
        end

      other ->
        handle_info({:wotex_matter, reference, other}, state)
    end
  end

  def handle_info(
        {:wotex_matter, reference, {:ok, value, metadata}},
        %{reference: reference, state: :bound} = state
      ) do
    case project(value, metadata, state) do
      {:ok, payload, projected} -> enqueue({:ok, payload, projected}, state)
      {:error, %Error{} = error} -> terminate_stream(error, :transport_down, state)
    end
  end

  def handle_info(
        {:wotex_matter, reference, {:error, %Error{} = error}},
        %{reference: reference, state: :bound} = state
      ),
      do: terminate_stream(error, terminal_status(error), state)

  def handle_info(
        {:wotex_matter, reference, {:status, _, _}},
        %{reference: reference, state: :bound} = state
      ),
      do: terminate_stream(Error.new(:unsupported_stream_status), :transport_down, state)

  def handle_info(
        {:DOWN, monitor, :process, owner, _},
        %{owner_monitor: monitor, owner: owner} = state
      ) do
    {_, state} = close_resources(%{state | state: :closing})
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{closed?: false} = state) do
    close_resources(state)
    :ok
  end

  def terminate(_, _), do: :ok

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} ->
        {:state,
         Map.take(state, [:state, :operation, :kind, :address, :owner_queue_limit, :closed?])}

      {:message, _} ->
        {:message, :redacted}

      {:reason, _} ->
        {:reason, :redacted}

      {:log, _} ->
        {:log, []}

      entry ->
        entry
    end)
  end

  defp subscribe(session, request) do
    result =
      case session do
        %Session{client: Native, handle: handle, timeout: timeout} ->
          normalized =
            request
            |> Map.drop([:receiver, :max_queue_length])
            |> Map.put(:queue_limit, request.max_queue_length)

          Native.subscribe_acknowledged(handle, normalized, self(), timeout)

        _ ->
          Matter.subscribe(session, request)
      end

    case result do
      {:ok, %Subscription{} = subscription} ->
        {:ok, subscription}

      {:error, %Error{} = error} ->
        Matter.disconnect(session)
        {:error, error}
    end
  end

  defp bind(init, watcher, relay, session, subscription, owner_queue_limit) do
    case opening_reports(subscription.reference, [], 0) do
      {:ok, opening} ->
        generation = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        owner_monitor = Process.monitor(init.owner)
        send(watcher, {:runtime_relay_bound, relay})

        state =
          init
          |> Map.drop([:client_options, :stream_options])
          |> Map.merge(%{
            state: :bound,
            owner_monitor: owner_monitor,
            session: session,
            subscription: subscription,
            reference: subscription.reference,
            generation: generation,
            owner_queue_limit: owner_queue_limit,
            opening: opening,
            pending: %{},
            closed?: false
          })

        {:ok, state, {:continue, :flush_opening}}

      {:error, %Error{} = error} ->
        abandon(session, subscription)
        {:stop, {:shutdown, error}}
    end
  end

  defp opening_reports(reference, reports, count) do
    receive do
      {:wotex_matter, ^reference, _} = report when count < @opening_limit ->
        opening_reports(reference, [report | reports], count + 1)

      {:wotex_matter, ^reference, _} ->
        {:error, Error.new(:receiver_overflow)}
    after
      0 -> {:ok, Enum.reverse(reports)}
    end
  end

  defp abandon(session, subscription) do
    session = %{session | timeout: min(session.timeout, @cleanup_timeout)}
    Matter.unsubscribe(session, subscription)
    Matter.disconnect(session)
    :ok
  end

  defp subscription_request(kind, address, options) do
    allowed = [:min_interval_s, :max_interval_s, :max_queue_length, :owner_queue_limit]
    keys = if Keyword.keyword?(options), do: Keyword.keys(options), else: []
    minimum = Keyword.get(options, :min_interval_s, 1)
    maximum = Keyword.get(options, :max_interval_s, 60)
    native_queue = Keyword.get(options, :max_queue_length, 1_000)
    owner_queue = Keyword.get(options, :owner_queue_limit, @default_owner_queue_limit)

    if valid_option_keys?(keys, allowed) and valid_intervals?(minimum, maximum) and
         valid_queue_limit?(native_queue) and valid_queue_limit?(owner_queue) do
      {:ok,
       %{
         kind: kind,
         paths: [Map.from_struct(address)],
         min_interval_s: minimum,
         max_interval_s: maximum,
         resubscribe: false,
         max_queue_length: native_queue,
         receiver: self()
       }, owner_queue}
    else
      {:error, Error.new(:invalid_subscription)}
    end
  end

  defp project(value, %{kind: :attribute, path: path, data_version: version} = metadata, %{
         kind: :attribute,
         address: address
       }) do
    with {:ok, ^address} <- Address.new(path),
         true <- success_status?(metadata),
         true <- is_nil(version) or (is_integer(version) and version in 0..0xFFFFFFFF),
         {:ok, value} <- Descriptor.validate_element(:attribute, address, :read, value) do
      {:ok, value,
       %{
         matter_kind: :attribute,
         path: Map.from_struct(address),
         status: 0,
         data_version: version
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp project(
         value,
         %{
           kind: :event,
           path: path,
           event_number: number,
           priority: priority,
           timestamp: timestamp
         } = metadata,
         %{kind: :event, address: address}
       ) do
    with {:ok, ^address} <- Address.new(path),
         true <- success_status?(metadata),
         true <- is_integer(number) and number in 0..0xFFFFFFFFFFFFFFFF,
         true <- is_integer(priority) and priority in 0..255,
         true <- valid_timestamp?(timestamp),
         {:ok, value} <- Descriptor.validate_element(:event, address, :read, value) do
      {:ok, value,
       %{
         matter_kind: :event,
         path: Map.from_struct(address),
         status: 0,
         event_number: number,
         priority: priority,
         timestamp: timestamp
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  defp project(_, _, _), do: {:error, Error.new(:invalid_transport_return)}

  defp enqueue(delivery, state, native_delivery \\ nil)

  defp enqueue(_, %{pending: pending} = state, _) when map_size(pending) >= @opening_limit,
    do: terminate_stream(Error.new(:receiver_overflow), :transport_down, state)

  defp enqueue(delivery, state, native_delivery) do
    case Process.info(state.owner, :message_queue_len) do
      {:message_queue_len, length} when length < state.owner_queue_limit ->
        token = make_ref()
        value = encode_delivery(delivery)
        frame = %Frame{pid: self(), generation: state.generation, token: token, value: value}
        identity = {state.request_id, state.operation, state.kind, state.address}
        send(state.owner, {:wotex_transport_frame, frame})

        {:noreply,
         %{state | pending: Map.put(state.pending, token, {identity, value, native_delivery})}}

      _ ->
        terminate_stream(Error.new(:receiver_overflow), :transport_down, state)
    end
  end

  defp acknowledge_native(%Delivery{} = delivery) do
    send(
      delivery.connection,
      {:native_report_consumed, delivery.generation, delivery.reference, delivery.sequence,
       delivery.token}
    )

    :ok
  end

  defp acknowledge_native(nil), do: :ok

  defp terminate_stream(error, status, state) do
    send(state.owner, {:wotex_transport, {:error, error}})
    {_, state} = close_resources(%{state | state: :closing})
    send(state.owner, {:wotex_transport_status, status})
    {:stop, :normal, state}
  end

  defp terminal_status(%Error{code: :receiver_overflow}), do: :transport_down
  defp terminal_status(_), do: :session_lost

  defp encode_delivery({:ok, value, metadata}), do: {:value, value, metadata}
  defp encode_delivery({:error, %Error{} = error}), do: {:error, error}

  defp decode_delivery({:value, value, metadata}), do: {:ok, value, metadata}
  defp decode_delivery({:error, %Error{} = error}), do: {:error, error}

  defp close_resources(%{closed?: true} = state), do: {:ok, state}

  defp close_resources(state) do
    session = %{state.session | timeout: min(state.session.timeout, @cleanup_timeout)}
    unsubscribe = Matter.unsubscribe(session, state.subscription)
    disconnect = Matter.disconnect(session)

    result =
      case {unsubscribe, disconnect} do
        {:ok, :ok} -> :ok
        {{:error, %Error{} = error}, _} -> {:error, error}
        {_, {:error, %Error{} = error}} -> {:error, error}
      end

    {result,
     %{state | state: :closed, session: nil, subscription: nil, pending: %{}, closed?: true}}
  end

  defp valid_timestamp?(%{kind: kind, value: value} = timestamp)
       when map_size(timestamp) == 2 and kind in [:epoch, :system],
       do: is_integer(value) and value in 0..0xFFFFFFFFFFFFFFFF

  defp valid_timestamp?(_), do: false

  defp success_status?(metadata), do: Map.get(metadata, :status, 0) == 0

  defp valid_option_keys?(keys, allowed),
    do: length(keys) == length(Enum.uniq(keys)) and keys -- allowed == []

  defp valid_intervals?(minimum, maximum),
    do:
      is_integer(minimum) and minimum in 0..65_535 and is_integer(maximum) and
        maximum in 1..65_535 and minimum <= maximum

  defp valid_queue_limit?(value), do: is_integer(value) and value in 1..10_000

  defp watch_owner(owner, relay) do
    owner_monitor = Process.monitor(owner)
    relay_monitor = Process.monitor(relay)

    receive do
      {:DOWN, ^owner_monitor, :process, ^owner, _} ->
        Process.exit(relay, :kill)

      {:DOWN, ^relay_monitor, :process, ^relay, _} ->
        :ok

      {:runtime_relay_bound, ^relay} ->
        Process.demonitor(owner_monitor, [:flush])
        Process.demonitor(relay_monitor, [:flush])
        :ok
    end
  end
end
