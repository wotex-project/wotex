defmodule Wotex.BLE do
  @moduledoc "Consumer-neutral BLE operations over an explicitly supplied real client port."

  import Kernel, except: [send: 2]
  alias Wotex.BLE.{Address, Error, PortCall, Procedure, Session, Value}
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

  @doc "Describes one implemented backend profile without probing a device."
  @spec capabilities(term()) :: {:ok, map()} | {:error, Error.t()}
  def capabilities(:oneshot), do: {:ok, capabilities()}

  def capabilities(:gatt) do
    {:ok,
     Map.merge(capabilities(), %{
       operations: [:read, :write, :discover, :pair, :subscribe, :unsubscribe, :health_check],
       transport: :bluez_dbus,
       supports_streaming: true,
       discovery_capable: true
     })}
  end

  def capabilities(_), do: {:error, Error.new(:unsupported_profile)}

  @doc "Returns the native-value one-shot Runtime binding profile."
  @spec profile() :: Wotex.Runtime.BindingProfile.t()
  def profile do
    {:ok, profile} = profile(:oneshot)
    profile
  end

  @doc "Builds one admitted Runtime profile without starting a backend."
  @spec profile(term()) :: {:ok, Wotex.Runtime.BindingProfile.t()} | {:error, Error.t()}
  def profile(:oneshot) do
    {:ok, profile} =
      Wotex.Runtime.BindingProfile.new(
        id: :ble,
        schemes: ["ble"],
        operations: [:readproperty, :writeproperty],
        media_types: []
      )

    {:ok, profile}
  end

  def profile(:gatt) do
    Wotex.Runtime.BindingProfile.new(
      id: :ble_gatt,
      schemes: ["ble"],
      operations: [
        :readproperty,
        :writeproperty,
        :observeproperty,
        :unobserveproperty,
        :subscribeevent,
        :unsubscribeevent
      ],
      media_types: []
    )
  end

  def profile(_), do: {:error, Error.new(:unsupported_profile)}

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
        {:error, error} when type == :write ->
          if session.client == Wotex.BLE.BlueZ and
               match?(%Wotex.BLE.BlueZ.Connection{}, session.handle),
             do: {:error, error},
             else: {:error, Error.unknown_effect(error)}

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

  @doc "Reads raw bytes or an explicitly selected value codec from a GATT address."
  @spec read(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def read(session, address, options \\ [])

  def read(%Session{} = session, address, options) do
    with {:ok, config} <- Procedure.options(options, session.timeout),
         {:ok, address} <- Address.new(address),
         message = Map.put(Map.from_struct(address), :type, :read),
         {:ok, bytes} <- send(%{session | timeout: config.timeout}, message) do
      Value.decode(bytes, config.type, config.codec)
    end
  end

  def read(_, _, _), do: {:error, Error.new(:invalid_session)}

  @doc "Writes an explicit value codec and waits for acknowledged GATT completion."
  @spec write(term(), term(), term(), term()) :: {:ok, :written} | {:error, Error.t()}
  def write(session, address, value, options \\ [])

  def write(%Session{} = session, address, value, options) do
    with {:ok, config} <- Procedure.options(options, session.timeout),
         {:ok, address} <- Address.new(address),
         {:ok, bytes} <- Value.encode(value, config.type, config.codec) do
      message = Map.merge(Map.from_struct(address), %{type: :write, value: bytes})

      case send(%{session | timeout: config.timeout}, message) do
        {:ok, :written} = result -> result
        {:error, _} = error -> error
        _ -> {:error, Error.unknown_effect(Error.new(:invalid_transport_return))}
      end
    end
  end

  def write(_, _, _, _), do: {:error, Error.new(:invalid_session)}

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

  @doc "Queries live persistent peer state; one-shot clients require an explicit probe."
  @spec health_check(term()) :: {:ok, map()} | {:error, Error.t()}
  def health_check(%Session{client: Wotex.BLE.BlueZ} = session),
    do: Wotex.BLE.BlueZ.health_check(session.handle, session.timeout)

  def health_check(_), do: {:error, Error.new(:probe_required)}

  @doc "Subscribes a receiver to validated persistent BlueZ value changes."
  @spec subscribe(term(), term()) :: {:ok, Wotex.BLE.Subscription.t()} | {:error, Error.t()}
  def subscribe(%Session{client: Wotex.BLE.BlueZ} = session, request),
    do: Wotex.BLE.BlueZ.subscribe(session.handle, request, session.timeout)

  def subscribe(%Session{}, _), do: {:error, Error.new(:not_supported)}
  def subscribe(_, _), do: {:error, Error.new(:invalid_session)}

  @doc "Cancels a same-session subscription after releasing its native resources."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(%Session{client: Wotex.BLE.BlueZ} = session, subscription),
    do: Wotex.BLE.BlueZ.unsubscribe(session.handle, subscription)

  def unsubscribe(%Session{}, _), do: {:error, Error.new(:not_supported)}
  def unsubscribe(_, _), do: {:error, Error.new(:invalid_session)}

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
