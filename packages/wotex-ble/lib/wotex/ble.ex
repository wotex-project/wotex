defmodule Wotex.BLE do
  @moduledoc "Consumer-neutral BLE operations over an explicitly supplied real client port."

  import Kernel, except: [send: 2]
  alias Wotex.BLE.{Error, PortCall, Session}
  @operations [:read, :write]

  @doc "Reports the operations implemented by this library's validated client boundary."
  @spec capabilities() :: %{
          operations: [:read | :write, ...],
          transport: :explicit_client,
          bidirectional: true,
          reliable: false,
          ordered: false,
          multicast: false,
          qos_levels: [],
          max_payload_size: 512,
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
      max_payload_size: 512,
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
        [:wotex, :ble, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{operation: type, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      case result do
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

  @doc "Returns typed, bounded discovery pages from a persistent BlueZ session."
  @spec discover(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def discover(session, options \\ [])

  def discover(%Session{client: Wotex.BLE.BlueZ} = session, options),
    do: Wotex.BLE.BlueZ.discover(session.handle, options, session.timeout)

  def discover(%Session{}, _), do: {:error, Error.new(:not_supported)}
  def discover(_, _), do: {:error, Error.new(:invalid_session)}

  @doc "Pairs the selected persistent peer using an explicit consumer Agent decision."
  @spec pair(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def pair(%Session{client: Wotex.BLE.BlueZ} = session, request),
    do: Wotex.BLE.BlueZ.pair(session.handle, request, session.timeout)

  def pair(%Session{}, _), do: {:error, Error.new(:not_supported)}
  def pair(_, _), do: {:error, Error.new(:invalid_session)}

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

  defp validate(message), do: Wotex.BLE.Address.validate_message(message)
end
