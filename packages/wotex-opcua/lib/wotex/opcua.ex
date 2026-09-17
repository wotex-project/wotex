defmodule Wotex.OPCUA do
  @moduledoc """
  Executes bounded OPC Unified Architecture operations through an explicit client.

  `Wotex.OPCUA` is the package facade for connection lifecycle and native read,
  write, browse, and call requests supported by the selected client.
  `connect/1` returns a `Wotex.OPCUA.Session`, `send/2` validates and performs
  one request, and `disconnect/1` releases the session resources.
  `with_connection/2` calls the selected client cleanup function when the work
  returns or raises. Custom clients must implement the timeout and resource
  ownership guarantees required by `Wotex.OPCUA.Client`.

  ## Execution boundary

  The consumer selects a `Wotex.OPCUA.Client` and owns endpoint policy,
  credentials, certificates, trust configuration, authorization, and
  supervision. Loading this module opens no channel or Python process.
  The explicitly selected native client can own a persistent Session;
  subscriptions remain unsupported and are not simulated.
  A successful service result is protocol evidence only; it does not establish
  canonical Property state, authorization, or a physical Action effect.
  """

  import Kernel, except: [send: 2]
  alias Wotex.OPCUA.{Error, PortCall, Session}
  @operations [:read, :write, :browse, :call]
  @native_preflight_codes [
    :invalid_value,
    :invalid_node_id,
    :unsupported_protocol,
    :invalid_native_handle,
    :invalid_native_configuration,
    :request_too_large
  ]

  @doc "Reports the operations implemented by this library's validated client boundary."
  @spec capabilities() :: %{
          operations: [:read | :write | :browse | :call, ...],
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
    if Keyword.keyword?(opts), do: open(opts), else: {:error, Error.new(:invalid_options)}
  end

  def connect(_), do: {:error, Error.new(:invalid_options)}

  @doc "Validates and executes one operation without implicit retry."
  @spec send(Session.t(), map()) :: {:ok, term()} | {:error, Error.t()}
  def send(%Session{} = session, %{type: type} = message) when type in @operations do
    with :ok <- validate(message) do
      started = System.monotonic_time()
      result = PortCall.invoke(session.client, :request, [session.handle, message, session.timeout])

      :telemetry.execute(
        [:wotex, :opcua, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{operation: type, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      case result do
        {:error, %Error{code: code} = error}
        when type in [:write, :write_property, :invoke, :call] and
               session.client == Wotex.OPCUA.Open62541 and code in @native_preflight_codes ->
          {:error, error}

        {:error, error} when type in [:write, :write_property, :invoke, :call] ->
          {:error, %{error | effect: :unknown}}

        {:ok, _} = result ->
          result

        {:error, _} = error ->
          error

        _ ->
          {:error, Error.new(:invalid_transport_return)}
      end
    end
  end

  def send(_, _), do: {:error, Error.new(:invalid_message)}

  @doc "Releases the explicit handle; the client owns idempotent transport cleanup."
  @spec disconnect(Session.t()) :: :ok | {:error, Error.t()}
  def disconnect(%Session{} = session) do
    case PortCall.invoke(session.client, :disconnect, [session.handle]) do
      :ok -> :ok
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

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

  @doc "Unsolicited receive requires a separately graduated subscription transport."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "No fabricated liveness result is returned without a protocol probe."
  @spec health_check(term()) :: {:error, Error.t()}
  def health_check(_), do: {:error, Error.new(:probe_required)}

  @doc """
  Probes service health with one concrete Read of `probe.node_id`.

  The probe map contains exactly `node_id`. The result is `:ok` only after the
  selected client returns a successful Read; an open connection alone is not a
  healthy OPC UA service. Failures keep the client's structured Error.
  """
  @spec health_check(term(), term()) :: :ok | {:error, Error.t()}
  def health_check(%Session{} = session, %{node_id: node} = probe) when map_size(probe) == 1 do
    case send(session, %{type: :read, node_id: node}) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def health_check(_, _), do: {:error, Error.new(:invalid_probe)}

  @doc """
  Establishes one monitored data-change subscription through the selected client.

  The request map requires `node_id` and accepts `receiver` (default caller),
  `publishing_interval_ms` (1000, 10..60000), `sampling_interval_ms`
  (1000, 0..60000), `queue_size` (100, 1..1000), `discard_oldest` (true),
  `keepalive_count` (10, 1..1000), `lifetime_count` (30, 3..10000 and at least
  three keepalives) and `max_queue_length` (1000, 1..10000). Unknown keys fail
  before I/O. A client without the optional callback returns `:not_supported`.
  """
  @spec subscribe(term(), term()) ::
          {:ok, Wotex.OPCUA.Subscription.t()} | {:error, Error.t()} | :not_supported
  def subscribe(%Session{client: client} = session, request) do
    if exported?(client, :subscribe, 4) do
      with {:ok, validated} <- subscription_request(request) do
        result =
          PortCall.invoke(client, :subscribe, [
            session.handle,
            Map.delete(validated, :receiver),
            validated.receiver,
            session.timeout
          ])

        :telemetry.execute([:wotex, :opcua, :subscription, :open], %{count: 1}, %{
          result: if(match?({:ok, %Wotex.OPCUA.Subscription{}}, result), do: :ok, else: :error)
        })

        case result do
          {:ok, %Wotex.OPCUA.Subscription{}} -> result
          {:error, _} -> result
          _ -> {:error, Error.new(:invalid_transport_return)}
        end
      end
    else
      :not_supported
    end
  end

  def subscribe(_, _), do: :not_supported

  @doc "Cancels a subscription; a client without the optional callback returns `:not_supported`."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()} | :not_supported
  def unsubscribe(%Session{client: client} = session, subscription) do
    cond do
      not exported?(client, :unsubscribe, 3) ->
        :not_supported

      match?(%Wotex.OPCUA.Subscription{}, subscription) ->
        case PortCall.invoke(client, :unsubscribe, [session.handle, subscription, session.timeout]) do
          {:ok, _} -> {:error, Error.new(:invalid_transport_return)}
          result -> result
        end

      true ->
        {:error, Error.new(:invalid_subscription)}
    end
  end

  def unsubscribe(_, _), do: :not_supported

  @subscription_defaults %{
    publishing_interval_ms: 1000,
    sampling_interval_ms: 1000,
    queue_size: 100,
    discard_oldest: true,
    keepalive_count: 10,
    lifetime_count: 30,
    max_queue_length: 1000
  }
  @subscription_keys [:node_id, :receiver | Map.keys(@subscription_defaults)]

  defp subscription_request(%{node_id: node} = request) do
    request = Map.merge(@subscription_defaults, Map.put_new(request, :receiver, self()))

    with true <- Enum.all?(Map.keys(request), &(&1 in @subscription_keys)),
         {:ok, _} <- Wotex.OPCUA.Address.new(node),
         true <- is_pid(request.receiver),
         true <- interval?(request.publishing_interval_ms, 10),
         true <- interval?(request.sampling_interval_ms, 0),
         true <- count?(request.queue_size, 1, 1000),
         true <- is_boolean(request.discard_oldest),
         true <- count?(request.keepalive_count, 1, 1000),
         true <- count?(request.lifetime_count, 3, 10_000),
         true <- request.lifetime_count >= 3 * request.keepalive_count,
         true <- count?(request.max_queue_length, 1, 10_000) do
      {:ok, request}
    else
      _ -> {:error, Error.new(:invalid_value)}
    end
  end

  defp subscription_request(_), do: {:error, Error.new(:invalid_value)}

  defp interval?(value, minimum) when is_integer(value), do: value >= minimum and value <= 60_000

  defp interval?(value, minimum) when is_float(value),
    do: value >= minimum and value <= 60_000.0

  defp interval?(_, _), do: false

  defp count?(value, minimum, maximum), do: is_integer(value) and value in minimum..maximum

  defp exported?(module, function, arity),
    do:
      is_atom(module) and Code.ensure_loaded?(module) and
        function_exported?(module, function, arity)

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

  defp validate(message), do: Wotex.OPCUA.Address.validate_message(message)
end
