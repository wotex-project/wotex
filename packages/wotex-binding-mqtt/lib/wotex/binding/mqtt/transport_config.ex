defmodule Wotex.Binding.MQTT.TransportConfig do
  @moduledoc """
  Configures the MQTT Runtime transport around a consumer-supplied client port.

  `new/3` verifies that the client exports the required publish, read,
  subscribe, and unsubscribe callbacks. It stores the client's opaque
  configuration separately from a finite Property-read timeout and a positive
  JSON payload limit. The defaults are 5000 milliseconds and 1 MiB.

  A `t:t/0` is immutable and intentionally contains no credential. Credentials
  arrive through `Wotex.Runtime.ExecutionContext` only for the immediate client
  call and must not be retained in `client_config`. Inspection exposes the
  client module and public limits while omitting the opaque client value.
  Constructing this value loads no connection, starts no process, and performs
  no broker I/O. `read_timeout/1` and `max_payload_bytes/1` expose the two bounds
  used by `Wotex.Binding.MQTT.Transport`.
  """

  alias Wotex.Binding.MQTT.Error

  @callbacks [publish: 3, read: 4, subscribe: 4, unsubscribe: 4]
  @default_read_timeout 5_000
  @default_max_payload_bytes 1_048_576
  @allowed_options [:read_timeout, :max_payload_bytes]

  @derive {Inspect, only: [:client, :read_timeout, :max_payload_bytes]}
  @opaque t :: %__MODULE__{
            client: module(),
            client_config: term(),
            read_timeout: pos_integer(),
            max_payload_bytes: pos_integer()
          }

  @enforce_keys [:client, :client_config, :read_timeout, :max_payload_bytes]
  defstruct @enforce_keys

  @doc "Builds transport configuration around a consumer-supplied client port."
  @spec new(module(), term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(client, client_config, opts \\ [])

  def new(client, client_config, opts)
      when is_atom(client) and not is_nil(client) and is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_client(client),
         {:ok, read_timeout} <- positive_option(opts, :read_timeout, @default_read_timeout),
         {:ok, max_payload_bytes} <-
           positive_option(opts, :max_payload_bytes, @default_max_payload_bytes) do
      {:ok,
       %__MODULE__{
         client: client,
         client_config: client_config,
         read_timeout: read_timeout,
         max_payload_bytes: max_payload_bytes
       }}
    end
  end

  def new(_client, _client_config, _opts) do
    {:error,
     Error.new(
       :invalid_transport_configuration,
       :configuration,
       :permanent,
       "transport configuration input is invalid"
     )}
  end

  @doc "Returns the finite maximum duration of a Property read."
  @spec read_timeout(t()) :: pos_integer()
  def read_timeout(%__MODULE__{read_timeout: timeout}), do: timeout

  @doc "Returns the encoded or received JSON payload byte limit."
  @spec max_payload_bytes(t()) :: pos_integer()
  def max_payload_bytes(%__MODULE__{max_payload_bytes: max_bytes}), do: max_bytes

  defp validate_options(opts) do
    if Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in @allowed_options)) do
      :ok
    else
      {:error,
       Error.new(
         :invalid_transport_options,
         :configuration,
         :permanent,
         "transport options contain an unsupported key"
       )}
    end
  end

  defp validate_client(client) do
    if Code.ensure_loaded?(client) and
         Enum.all?(@callbacks, fn {function, arity} ->
           function_exported?(client, function, arity)
         end) do
      :ok
    else
      {:error,
       Error.new(
         :invalid_client_port,
         :configuration,
         :permanent,
         "client module must implement the MQTT client port"
       )}
    end
  end

  defp positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _invalid ->
        {:error,
         Error.new(
           :invalid_transport_option,
           :configuration,
           :permanent,
           "transport limits must be positive integers"
         )}
    end
  end
end
