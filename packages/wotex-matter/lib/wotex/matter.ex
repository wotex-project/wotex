defmodule Wotex.Matter do
  @moduledoc """
  Executes bounded Matter operations through an explicitly selected client.

  `Wotex.Matter` is the package facade for connection lifecycle and native
  read, write, invoke, and batch-read requests. `connect/1` returns a
  `Wotex.Matter.Session`, `send/2` validates and performs one concrete request,
  and `read_paths/3` preserves each concrete batch result. `disconnect/1`
  releases only the resources represented by that session. `with_connection/2`
  provides deterministic cleanup around the same API.

  ## Execution boundary

  The consumer selects a `Wotex.Matter.Client` and owns commissioning, fabric
  storage, attestation, secure sessions, credentials, authorization, routing,
  and supervision. Loading the module starts no controller or Python process.
  Subscription delivery is unsupported and is not simulated. A successful
  interaction is protocol evidence for the addressed path; it does not
  establish canonical Property state, authorization, or a certified physical
  effect.
  """

  import Kernel, except: [send: 2]
  alias Wotex.Matter.{AttributeReport, EndpointCatalogue, Error, EventReport}
  alias Wotex.Matter.{PathResults, PortCall, ReadPath, Session, Standalone}
  @operations [:read, :write, :invoke, :read_paths, :read_events]
  @send_operations [:read, :write, :invoke, :read_paths]

  @doc "Reports the operations implemented by this library's validated client boundary."
  @spec capabilities() :: %{
          operations: [:read | :write | :invoke | :read_paths | :read_events, ...],
          transport: :explicit_client,
          bidirectional: true,
          reliable: false,
          ordered: false,
          multicast: false,
          qos_levels: [],
          max_payload_size: 65_536,
          connection_oriented: true,
          supports_streaming: false,
          discovery_capable: true
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
      discovery_capable: true
    }

  @doc "Opens the supplied client module; absent transport fails explicitly."
  @spec connect(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  def connect(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: open(opts), else: {:error, Error.new(:invalid_options)}
  end

  def connect(_), do: {:error, Error.new(:invalid_options)}

  @doc "Validates and executes one operation without implicit retry."
  @spec send(Session.t(), map()) :: {:ok, term()} | {:error, Error.t()}
  def send(%Session{} = session, %{type: type} = message) when type in @send_operations do
    with :ok <- validate(message) do
      started = System.monotonic_time()
      result = PortCall.invoke(session.client, :request, [session.handle, message, session.timeout])

      :telemetry.execute(
        [:wotex, :matter, :request, :stop],
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

  @doc "Reads one bounded batch and preserves every concrete per-path result."
  @spec read_paths(Session.t(), [ReadPath.t() | map()], keyword()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def read_paths(session, paths, options \\ [])

  def read_paths(%Session{} = session, paths, options) do
    with {:ok, paths} <- read_path_list(paths),
         {:ok, timeout} <- read_options(options, session.timeout) do
      started = System.monotonic_time()
      message = %{type: :read_paths, paths: Enum.map(paths, &Map.from_struct/1)}

      result =
        case PortCall.invoke(session.client, :request, [session.handle, message, timeout]) do
          {:ok, results} -> PathResults.normalize(paths, results)
          {:error, _} = error -> error
        end

      :telemetry.execute(
        [:wotex, :matter, :request, :stop],
        %{duration: System.monotonic_time() - started},
        %{operation: :read_paths, result: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      result
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_transport_return)}
    end
  end

  def read_paths(_, _, _), do: {:error, Error.new(:invalid_message)}

  @doc "Reads one admitted concrete attribute through its generated-schema descriptor."
  @spec read_attribute(Session.t(), term(), keyword()) ::
          {:ok, AttributeReport.t()} | {:error, Error.t()}
  def read_attribute(session, address, options \\ []),
    do: Standalone.read_attribute(session, address, options)

  @doc "Writes one admitted concrete attribute without automatic retry or readback."
  @spec write_attribute(Session.t(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def write_attribute(session, address, value, options \\ []),
    do: Standalone.write_attribute(session, address, value, options)

  @doc "Invokes one admitted concrete command without automatic replay."
  @spec invoke_command(Session.t(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def invoke_command(session, address, value, options \\ []),
    do: Standalone.invoke_command(session, address, value, options)

  @doc "Reads concrete event paths while preserving native event identity and per-path status."
  @spec read_events(Session.t(), list(), keyword()) ::
          {:ok, [%{path: term(), result: {:ok, EventReport.t()} | {:error, Error.t()}}]}
          | {:error, Error.t()}
  def read_events(session, paths, options \\ []),
    do: Standalone.read_events(session, paths, options)

  @doc "Builds a bounded non-atomic endpoint catalogue from concrete Descriptor reads."
  @spec discover_endpoints(Session.t(), term(), keyword()) ::
          {:ok, EndpointCatalogue.t()} | {:error, Error.t()}
  def discover_endpoints(session, node, options \\ []),
    do: Standalone.discover_endpoints(session, node, options)

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

  defp validate(message), do: Wotex.Matter.Address.validate_message(message)

  defp read_path_list(paths) when is_list(paths) and length(paths) in 1..64 do
    result =
      Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
        case ReadPath.new(path) do
          {:ok, path} -> {:cont, {:ok, [path | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp read_path_list(_), do: {:error, Error.new(:invalid_path_batch)}

  defp read_options(options, default) when is_list(options) do
    if Keyword.keyword?(options) and
         length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))) and
         Keyword.keys(options) -- [:timeout] == [] do
      timeout = Keyword.get(options, :timeout, default)

      if is_integer(timeout) and timeout in 1..60_000,
        do: {:ok, timeout},
        else: {:error, Error.new(:invalid_options)}
    else
      {:error, Error.new(:invalid_options)}
    end
  end

  defp read_options(_, _), do: {:error, Error.new(:invalid_options)}
end
