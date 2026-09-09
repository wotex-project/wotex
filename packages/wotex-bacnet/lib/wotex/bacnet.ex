defmodule Wotex.BACnet do
  @moduledoc """
  Executes bounded BACnet operations through an explicitly selected client.

  `Wotex.BACnet` is the package entry point for connection lifecycle and native
  BACnet requests. `connect/1` validates client configuration and returns a
  `Wotex.BACnet.Session`; `send/2` accepts the supported request maps; and
  `disconnect/1` releases only the resources represented by that session.
  `with_connection/2` provides the same lifecycle with deterministic cleanup.

  ## Execution boundary

  The consumer selects the `Wotex.BACnet.Client` implementation, supplies
  addressing and timeouts, and owns credentials, authorization, supervision,
  and routing policy. Loading this module performs no network operation.
  Native helpers provide single and sequential Property reads, writes, and
  explicit Who-Is discovery. `subscribe/2` establishes finite object or Property
  Change of Value (COV) subscriptions through a supported client. `profile/0`
  and `profile/1` declare the corresponding Runtime Property operations.
  `receive/2` remains unsupported; `health_check/2` requires an explicit probe.
  A successful BACnet exchange is protocol evidence only;
  it does not establish canonical Property state or authorization.
  """

  import Kernel, except: [send: 2]
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Error, NativeCall, PortCall, Session, Subscription}
  @operations [:read_property, :write_property]

  @doc "Reports the operations implemented by this library's validated client boundary."
  @spec capabilities() :: %{
          operations: [:read_property | :write_property, ...],
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

  @doc "Returns the pure native read/write Runtime profile; it performs no discovery or startup."
  @spec profile() :: Wotex.Runtime.BindingProfile.t()
  def profile do
    {:ok, profile} = profile(:ip)
    profile
  end

  @doc "Returns an explicit native Property profile, with optional COV observations."
  @spec profile(term()) :: {:ok, Wotex.Runtime.BindingProfile.t()} | {:error, Error.t()}
  def profile(mode) when mode in [:ip, :ip_cov] do
    operations = [:readproperty, :writeproperty]

    operations =
      if mode == :ip_cov, do: operations ++ [:observeproperty, :unobserveproperty], else: operations

    Wotex.Runtime.BindingProfile.new(
      id: if(mode == :ip, do: :bacnet, else: :bacnet_cov),
      schemes: ["bacnet"],
      operations: operations,
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
  def send(%Session{timeout: timeout} = session, message)
      when is_integer(timeout) and timeout in 1..60_000,
      do: send_deadline(session, message, System.monotonic_time(:millisecond) + timeout)

  def send(_, _), do: {:error, Error.new(:invalid_message)}

  @doc false
  @spec send_deadline(Session.t(), map(), integer()) :: {:ok, term()} | {:error, Error.t()}
  def send_deadline(%Session{} = session, %{type: type} = message, deadline)
      when type in @operations and is_integer(deadline) do
    with :ok <- validate(message) do
      started = System.monotonic_time()
      result = NativeCall.invoke(session, :request, message, deadline)

      :telemetry.execute(
        [:wotex, :bacnet, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{operation: type, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      case result do
        {:not_started, error} ->
          {:error, error}

        {:error, error}
        when type in [:write, :write_property, :invoke, :call] and
               session.client not in [Wotex.BACnet.BACstack, Wotex.BACnet.IPv4] ->
          {:error, Error.with_effect(error, :unknown)}

        {:ok, _} = result ->
          result

        {:error, _} = error ->
          error
      end
    end
  end

  def send_deadline(_, _, _), do: {:error, Error.new(:invalid_message)}

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

  @doc "Reads one entire Property as a validated native BACnet value."
  @spec read_property(Session.t(), atom() | 0..1023, 0..4_194_302, atom() | 0..4_194_303) ::
          {:ok, Encoding.t() | [Encoding.t()]} | {:error, Error.t()}
  def read_property(session, object, instance, property),
    do: Wotex.BACnet.NativeHelpers.read_property(session, object, instance, property)

  @doc "Writes one entire Property without a priority override, requiring its matching ACK."
  @spec write_property(
          Session.t(),
          atom() | 0..1023,
          0..4_194_302,
          atom() | 0..4_194_303,
          Encoding.t() | [Encoding.t()]
        ) :: :ok | {:error, Error.t()}
  def write_property(session, object, instance, property, value),
    do: Wotex.BACnet.NativeHelpers.write_property(session, object, instance, property, value)

  @doc "Reads 1..64 distinct Properties sequentially under one admission slot and deadline."
  @spec read_properties(Session.t(), atom() | 0..1023, 0..4_194_302, [atom() | 0..4_194_303]) ::
          {:ok, %{non_neg_integer() => Encoding.t() | [Encoding.t()]}} | {:error, Error.t()}
  def read_properties(session, object, instance, properties),
    do: Wotex.BACnet.NativeHelpers.read_properties(session, object, instance, properties)

  @doc "Collects finite Who-Is observations without changing the configured route."
  @spec who_is(Session.t(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          {:ok, [Wotex.BACnet.Device.t()]} | {:error, Error.t()}
  def who_is(session, low_limit \\ nil, high_limit \\ nil),
    do: Wotex.BACnet.NativeDiscovery.who_is(session, low_limit, high_limit)

  @doc "Unsolicited receive requires a separately graduated subscription transport."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "No fabricated liveness result is returned without a protocol probe."
  @spec health_check(term()) :: {:error, Error.t()}
  def health_check(_), do: {:error, Error.new(:probe_required)}

  @doc "Reports healthy only after a validated explicit ReadProperty probe succeeds."
  @spec health_check(term(), term()) :: {:ok, :healthy} | {:error, Error.t()}
  def health_check(%Session{timeout: timeout} = session, %{type: :read_property} = probe)
      when is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    with :ok <- validate(probe),
         {:ok, value} <- send_deadline(session, probe, deadline),
         :ok <- Wotex.BACnet.Value.validate_read(value),
         true <- System.monotonic_time(:millisecond) < deadline do
      {:ok, :healthy}
    else
      false -> {:error, Error.new(:deadline_exceeded)}
      {:error, _} = error -> error
    end
  end

  def health_check(_, _), do: {:error, Error.new(:invalid_health_probe)}

  @doc "Establishes a finite native COV subscription through the selected client."
  @spec subscribe(term(), term()) :: {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(%Session{timeout: timeout} = session, request)
      when is_integer(timeout) and timeout in 1..60_000,
      do: subscribe_deadline(session, request, System.monotonic_time(:millisecond) + timeout)

  def subscribe(_, _), do: {:error, Error.new(:invalid_subscription)}

  @doc false
  @spec subscribe_deadline(term(), term(), term()) :: {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe_deadline(session, request, deadline),
    do: Wotex.BACnet.NativeSubscription.open(session, request, deadline)

  @doc "Cancels through the original client and validates the opaque subscription handle."
  @spec unsubscribe(term(), term()) :: :ok | {:error, Error.t()}
  def unsubscribe(%Session{client: client, timeout: timeout} = session, subscription)
      when is_atom(client) and not is_nil(client) and is_integer(timeout) and
             timeout in 1..60_000 do
    if Subscription.valid?(subscription) do
      case PortCall.optional(client, :unsubscribe, [session.handle, subscription, timeout]) do
        :ok -> :ok
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_transport_return)}
      end
    else
      {:error, Error.new(:invalid_subscription)}
    end
  end

  def unsubscribe(_, _), do: {:error, Error.new(:invalid_subscription)}

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

  defp validate(message), do: Wotex.BACnet.Address.validate_message(message)
end
