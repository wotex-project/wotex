defmodule Wotex.Thread do
  @moduledoc """
  Executes bounded Thread management operations through an explicit client.

  `Wotex.Thread` is the package facade for connection lifecycle and both
  the read-only daemon operations and explicit native SDK management APIs.
  `connect/1` returns a `Wotex.Thread.Session`, `send/2` performs one request,
  and `disconnect/1` releases the selected client handle.
  `with_connection/2` provides deterministic cleanup around the same API.

  ## Execution boundary

  The consumer selects a `Wotex.Thread.Client`, supplies credentials and radio
  configuration, and owns authorization, routing and supervision.
  `Wotex.Thread.Daemon` connects to a consumer-owned daemon;
  `Wotex.Thread.OpenThread` explicitly acquires and cleans up its SDK resources. Loading this
  module starts no process and changes no Operational Dataset. Native Dataset
  updates, network formation and commissioner operations require explicit calls. Thread provides
  network management; application Property, Action, and Event operations remain
  with their protocol bindings. Unsupported receive, probe, and subscription
  operations return explicit failures.
  """

  import Kernel, except: [send: 2]
  alias Wotex.Thread.{Dataset, Error, OpenThread, PortCall, Session, State, Subscription}
  @operations [:state, :version, :network_name, :rloc16]

  @doc "Reports the operations implemented by this library's validated client boundary."
  @spec capabilities() :: %{
          operations: [:state | :version | :network_name | :rloc16, ...],
          transport: :explicit_client,
          bidirectional: true,
          reliable: false,
          ordered: false,
          multicast: false,
          qos_levels: [],
          max_payload_size: 65_536,
          connection_oriented: true,
          supports_streaming: false,
          discovery_capable: false
        }
  def capabilities,
    do: %{
      operations: @operations,
      transport: :explicit_client,
      bidirectional: true,
      reliable: false,
      ordered: false,
      multicast: false,
      qos_levels: [],
      max_payload_size: 65_536,
      connection_oriented: true,
      supports_streaming: false,
      discovery_capable: false
    }

  @doc "Opens the supplied client module; absent transport fails explicitly."
  @spec connect(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  def connect(opts) when is_list(opts) do
    if unique_options?(opts, %{}, 0), do: open(opts), else: {:error, Error.new(:invalid_options)}
  end

  def connect(_), do: {:error, Error.new(:invalid_options)}

  @doc "Validates and executes one operation without implicit retry."
  @spec send(Session.t(), map()) :: {:ok, term()} | {:error, Error.t()}
  def send(%Session{} = session, %{type: type} = message) when type in @operations do
    with :ok <- Session.validate(session), :ok <- validate(message) do
      started = System.monotonic_time()
      result = PortCall.invoke(session.client, :request, [session.handle, message, session.timeout])

      :telemetry.execute(
        [:wotex, :thread, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{operation: type, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      case result do
        {:ok, _} = result -> result
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_transport_return)}
      end
    end
  end

  def send(_, _), do: {:error, Error.new(:invalid_message)}

  @doc "Releases the explicit handle; the client owns idempotent transport cleanup."
  @spec disconnect(Session.t()) :: :ok | {:error, Error.t()}
  def disconnect(%Session{} = session) do
    with :ok <- Session.validate(session) do
      case PortCall.invoke(session.client, :disconnect, [session.handle]) do
        :ok -> :ok
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_transport_return)}
      end
    end
  end

  def disconnect(_), do: {:error, Error.new(:invalid_session)}

  @doc "Reads the owned SDK's typed, non-secret state with an optional finite timeout."
  @spec inspect_state(term(), term()) :: {:ok, State.t()} | {:error, Error.t()}
  def inspect_state(session, options) do
    entered = System.monotonic_time(:millisecond)

    with :ok <- Session.validate(session),
         {:ok, timeout} <- inspection_timeout(options, session.timeout),
         :ok <- native_client(session) do
      remaining = timeout - (System.monotonic_time(:millisecond) - entered)

      if remaining > 0,
        do: native_exchange(session, %{type: :inspect}, remaining),
        else: {:error, Error.new(:timeout)}
    end
  end

  @doc "Validates a Dataset through the owned SDK without changing network or stored state."
  @spec validate_dataset(term(), term(), term(), term()) :: :ok | {:error, Error.t()}
  def validate_dataset(session, dataset, kind, timeout) do
    message = %{type: :validate_dataset, dataset: dataset, kind: kind}

    case native_request(session, message, timeout) do
      {:ok, nil} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Explicitly exports the active or pending Dataset, including its credential bytes."
  @spec get_dataset(term(), term(), term()) :: {:ok, Dataset.t()} | {:error, Error.t()}
  def get_dataset(session, kind, timeout),
    do: native_request(session, %{type: :get_dataset, kind: kind}, timeout)

  @doc "Sets explicit IPv6 and Thread enable states on the owned SDK instance."
  @spec set_enabled(term(), term(), term()) :: {:ok, State.t()} | {:error, Error.t()}
  def set_enabled(session, state, timeout),
    do: native_request(session, %{type: :set_enabled, state: state}, timeout)

  @doc "Forms an explicitly authorized new network and waits for the observed leader role."
  @spec form_network(term(), term(), term()) :: {:ok, State.t()} | {:error, Error.t()}
  def form_network(session, dataset, timeout),
    do: native_request(session, %{type: :form_network, dataset: dataset}, timeout)

  @doc "Submits an Active Dataset update and waits for acceptance, without asserting effectiveness."
  @spec management_active_set(term(), term(), term()) ::
          {:ok, %{accepted: true, effective: :not_verified}} | {:error, Error.t()}
  def management_active_set(session, update, timeout),
    do: native_request(session, %{type: :management_active_set, update: update}, timeout)

  @doc "Submits a Pending Dataset update and waits for acceptance, without asserting activation."
  @spec management_pending_set(term(), term(), term()) ::
          {:ok, %{accepted: true, effective: :not_verified}} | {:error, Error.t()}
  def management_pending_set(session, update, timeout),
    do: native_request(session, %{type: :management_pending_set, update: update}, timeout)

  @doc "Starts the owned commissioner and waits for its active state callback."
  @spec commissioner_start(term(), term()) :: {:ok, %{state: :active}} | {:error, Error.t()}
  def commissioner_start(session, options),
    do: native_options_request(session, %{type: :commissioner_start}, options)

  @doc "Stops the owned commissioner and clears its finite admission records."
  @spec commissioner_stop(term(), term()) :: {:ok, %{state: :disabled}} | {:error, Error.t()}
  def commissioner_stop(session, options),
    do: native_options_request(session, %{type: :commissioner_stop}, options)

  @doc "Installs a typed, finite joiner admission in the owned active commissioner."
  @spec add_joiner(term(), term(), term()) ::
          {:ok, %{identity: map(), lifetime_s: 1..3600}} | {:error, Error.t()}
  def add_joiner(session, admission, timeout),
    do: native_request(session, %{type: :add_joiner, admission: admission}, timeout)

  @doc "Removes exactly the specified typed joiner identity from the owned commissioner."
  @spec remove_joiner(term(), term(), term()) :: :ok | {:error, Error.t()}
  def remove_joiner(session, identity, timeout),
    do: native_ack(session, %{type: :remove_joiner, identity: identity}, timeout)

  @doc "Starts one owned Joiner attempt and waits for its final completion callback."
  @spec joiner_start(term(), term(), term()) ::
          {:ok, %{joined: true}} | {:error, Error.t()}
  def joiner_start(session, config, timeout),
    do: native_request(session, %{type: :joiner_start, config: config}, timeout)

  @doc "Stops the owned Joiner attempt without enabling Thread or retrying it."
  @spec joiner_stop(term(), term()) :: :ok | {:error, Error.t()}
  def joiner_stop(session, options),
    do: native_options_ack(session, %{type: :joiner_stop}, options)

  @doc "Runs work with guaranteed handle cleanup when the function returns or raises."
  @spec with_connection(keyword(), (Session.t() -> term())) :: term()
  def with_connection(opts, fun) when is_function(fun, 1) do
    with {:ok, session} <- connect(opts) do
      try do
        fun.(session)
      after
        disconnect(session)
      end
    end
  end

  def with_connection(_, _), do: {:error, Error.new(:invalid_callback)}

  @doc "Unsolicited receive requires a separately graduated subscription transport."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "No fabricated liveness result is returned without a protocol probe."
  @spec health_check(term()) :: {:error, Error.t()}
  def health_check(_), do: {:error, Error.new(:probe_required)}

  @doc """
  Subscribes a receiver to non-secret State reports of an owned OpenThread session.

  The request is `%{type: :state}` with optional `receiver` (default caller),
  `max_queue_length` (1..10000, default 1000) and `timeout` (default the Session
  limit). Success follows native listener registration; the receiver then gets
  one initial snapshot and later coalesced snapshots as
  `{:wotex_thread, reference, {:ok, %Wotex.Thread.State{}, %{changed_flags: flags}}}`,
  or one terminal `{:wotex_thread, reference, {:error, error}}`. Sessions of
  other clients return the `:not_supported` sentinel; State subscriptions are
  native control reports, not Runtime application streams.
  """
  @spec subscribe(term(), term()) ::
          {:ok, Subscription.t()} | {:error, Error.t()} | :not_supported
  def subscribe(%Session{client: OpenThread} = session, request) do
    with :ok <- Session.validate(session),
         {:ok, receiver, queue_limit, timeout} <- subscription_request(request, session.timeout) do
      OpenThread.subscribe(session.handle, receiver, queue_limit, timeout)
    end
  end

  def subscribe(_, _), do: :not_supported

  @doc """
  Cancels a native State subscription and waits for its retirement.

  Repeated cancellation of a closed handle and cancellation after the owning
  session ended return `:ok`. Sessions of other clients return `:not_supported`.
  """
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()} | :not_supported
  def unsubscribe(%Session{client: OpenThread} = session, subscription) do
    with :ok <- Session.validate(session),
         do: OpenThread.unsubscribe(session.handle, subscription, session.timeout)
  end

  def unsubscribe(_, _), do: :not_supported

  defp subscription_request(%{type: :state} = request, default_timeout) do
    receiver = Map.get(request, :receiver, self())
    queue_limit = Map.get(request, :max_queue_length, 1000)
    timeout = Map.get(request, :timeout, default_timeout)

    if Enum.all?(Map.keys(request), &(&1 in [:type, :receiver, :max_queue_length, :timeout])) and
         is_pid(receiver) and node(receiver) == node() and is_integer(queue_limit) and
         queue_limit in 1..10_000 and is_integer(timeout) and timeout in 1..60_000,
       do: {:ok, receiver, queue_limit, timeout},
       else: {:error, Error.new(:invalid_subscription)}
  end

  defp subscription_request(_, _), do: {:error, Error.new(:invalid_subscription)}

  defp open(opts) do
    client = Keyword.get(opts, :client)
    timeout = Keyword.get(opts, :timeout, 5000)

    if is_atom(client) and not is_nil(client) and is_integer(timeout) and timeout in 1..60_000 do
      case PortCall.invoke(client, :connect, [Keyword.drop(opts, [:client])]) do
        {:ok, handle} -> {:ok, %Session{client: client, handle: handle, timeout: timeout}}
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_transport_return)}
      end
    else
      {:error, Error.new(:transport_required)}
    end
  end

  defp native_options_request(session, message, options) do
    entered = System.monotonic_time(:millisecond)

    with :ok <- Session.validate(session),
         {:ok, timeout} <- inspection_timeout(options, session.timeout) do
      remaining = timeout - (System.monotonic_time(:millisecond) - entered)

      if remaining > 0,
        do: native_request(session, message, remaining),
        else: {:error, Error.new(:timeout)}
    end
  end

  defp native_options_ack(session, message, options) do
    case native_options_request(session, message, options) do
      {:ok, nil} -> :ok
      {:error, _} = error -> error
    end
  end

  defp native_ack(session, message, timeout) do
    case native_request(session, message, timeout) do
      {:ok, nil} -> :ok
      {:error, _} = error -> error
    end
  end

  defp native_request(session, message, timeout) do
    entered = System.monotonic_time(:millisecond)

    with :ok <- Session.validate(session),
         {:ok, timeout} <- inspection_timeout([timeout: timeout], session.timeout),
         {:ok, _} <- Wotex.Thread.OpenThread.Request.encode(message),
         :ok <- native_client(session) do
      remaining = timeout - (System.monotonic_time(:millisecond) - entered)

      if remaining > 0,
        do: native_exchange(session, message, remaining),
        else: {:error, Error.new(:timeout)}
    end
  end

  defp native_exchange(session, message, timeout) do
    started = System.monotonic_time()
    result = OpenThread.request(session.handle, message, timeout)

    :telemetry.execute(
      [:wotex, :thread, :request, :stop],
      %{duration: System.monotonic_time() - started},
      %{operation: message.type, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
    )

    result
  end

  defp native_client(%Session{client: OpenThread}), do: :ok
  defp native_client(_), do: {:error, Error.new(:not_supported)}

  defp inspection_timeout([], timeout), do: {:ok, timeout}

  defp inspection_timeout([timeout: timeout], _) when is_integer(timeout) and timeout in 1..60_000,
    do: {:ok, timeout}

  defp inspection_timeout(_, _), do: {:error, Error.new(:invalid_options)}

  defp unique_options?([], _, _), do: true

  defp unique_options?([{key, _} | rest], seen, count)
       when is_atom(key) and not is_map_key(seen, key) and count < 64,
       do: unique_options?(rest, Map.put(seen, key, true), count + 1)

  defp unique_options?(_, _, _), do: false

  defp validate(message), do: Wotex.Thread.Address.validate_message(message)
end
