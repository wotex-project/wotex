defmodule Wotex.Thread do
  @moduledoc "Consumer-neutral Thread operations over an explicitly supplied real client port."

  import Kernel, except: [send: 2]
  alias Wotex.Thread.{Error, OpenThread, PortCall, Session, State}
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
        do: OpenThread.request(session.handle, %{type: :inspect}, remaining),
        else: {:error, Error.new(:timeout)}
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

  def with_connection(_, _), do: {:error, Error.new(:invalid_callback)}

  @doc "Unsolicited receive requires a separately graduated subscription transport."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "No fabricated liveness result is returned without a protocol probe."
  @spec health_check(term()) :: {:error, Error.t()}
  def health_check(_), do: {:error, Error.new(:probe_required)}

  @doc "Baseline client ports do not imply subscription support."
  @spec subscribe(term(), term()) :: :not_supported
  def subscribe(_, _), do: :not_supported

  @doc "No subscription is created by this baseline."
  @spec unsubscribe(term(), term()) :: :not_supported
  def unsubscribe(_, _), do: :not_supported

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
