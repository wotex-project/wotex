defmodule Wotex.Binding.HTTP.Config do
  @moduledoc """
  Immutable configuration for the HTTP Runtime transport.

  Configuration binds a client module to non-secret client options, validated
  static request fields, and independent request, response, and event limits.
  Credential material is never accepted here.

  Supported options are:

  * `:client` — required `{module, client_config}` tuple whose module implements
    `Wotex.Binding.HTTP.Client`;
  * `:headers` — static credential-free request fields, defaulting to `[]`;
  * `:max_request_bytes` — maximum encoded JSON request size;
  * `:max_response_bytes` — maximum complete finite response size;
  * `:max_event_bytes` — maximum data size of one dispatched SSE event.

  Each limit must be a positive integer. Defaults are conservative package
  values and can be tightened by the consumer host.

  Each `new/1` call creates a distinct, non-secret instance reference. Reuse the
  returned configuration for the complete stream lifecycle; reconstructing even
  equal options creates another instance that cannot close existing streams.
  This reference correlates trusted consumer calls, not a security sandbox.
  """

  alias Wotex.Binding.HTTP.{Error, Headers}

  @default_max_request_bytes 1_048_576
  @default_max_response_bytes 4_194_304
  @default_max_event_bytes 1_048_576

  @derive {Inspect,
           only: [
             :client_module,
             :headers,
             :max_request_bytes,
             :max_response_bytes,
             :max_event_bytes
           ]}
  @type t :: %__MODULE__{
          client_module: module(),
          client_config: term(),
          instance_ref: reference(),
          headers: Headers.t(),
          max_request_bytes: pos_integer(),
          max_response_bytes: pos_integer(),
          max_event_bytes: pos_integer()
        }

  @enforce_keys [
    :client_module,
    :client_config,
    :instance_ref,
    :headers,
    :max_request_bytes,
    :max_response_bytes,
    :max_event_bytes
  ]
  defstruct @enforce_keys

  @doc "Builds validated transport configuration around a supplied client port."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: build(opts), else: invalid_options()
  end

  def new(_), do: invalid_options()

  defp build(opts) do
    client = Keyword.get(opts, :client)
    headers = Keyword.get(opts, :headers, [])
    max_request_bytes = Keyword.get(opts, :max_request_bytes, @default_max_request_bytes)
    max_response_bytes = Keyword.get(opts, :max_response_bytes, @default_max_response_bytes)
    max_event_bytes = Keyword.get(opts, :max_event_bytes, @default_max_event_bytes)

    with {:ok, client_module, client_config} <- validate_client(client),
         {:ok, normalized_headers} <- Headers.new(headers, :request),
         :ok <- positive_limit(max_request_bytes, :max_request_bytes),
         :ok <- positive_limit(max_response_bytes, :max_response_bytes),
         :ok <- positive_limit(max_event_bytes, :max_event_bytes) do
      {:ok,
       %__MODULE__{
         client_module: client_module,
         client_config: client_config,
         instance_ref: make_ref(),
         headers: normalized_headers,
         max_request_bytes: max_request_bytes,
         max_response_bytes: max_response_bytes,
         max_event_bytes: max_event_bytes
       }}
    end
  end

  defp invalid_options do
    {:error,
     Error.new(:invalid_config_options, :configuration, "configuration must be a keyword list")}
  end

  @doc "Returns the supplied client module and its non-credential configuration."
  @spec client(t()) :: {module(), term()}
  def client(%__MODULE__{client_module: module, client_config: config}), do: {module, config}

  @doc "Returns the non-secret identity of this immutable transport configuration."
  @spec instance_ref(t()) :: reference()
  def instance_ref(%__MODULE__{instance_ref: ref}), do: ref

  @doc "Returns validated static request fields."
  @spec headers(t()) :: Headers.t()
  def headers(%__MODULE__{headers: headers}), do: headers

  @doc "Returns the maximum encoded request-body size."
  @spec max_request_bytes(t()) :: pos_integer()
  def max_request_bytes(%__MODULE__{max_request_bytes: limit}), do: limit

  @doc "Returns the maximum complete response-body size."
  @spec max_response_bytes(t()) :: pos_integer()
  def max_response_bytes(%__MODULE__{max_response_bytes: limit}), do: limit

  @doc "Returns the maximum data size of one dispatched Server-Sent Event."
  @spec max_event_bytes(t()) :: pos_integer()
  def max_event_bytes(%__MODULE__{max_event_bytes: limit}), do: limit

  defp validate_client({module, config}) when is_atom(module) and not is_nil(module) do
    callbacks = [request: 3, subscribe: 4, close: 2]

    if Code.ensure_loaded?(module) and
         Enum.all?(callbacks, fn {name, arity} -> function_exported?(module, name, arity) end) do
      {:ok, module, config}
    else
      {:error,
       Error.new(
         :invalid_client,
         :configuration,
         "client must implement request/3, subscribe/4, and close/2"
       )}
    end
  end

  defp validate_client(_) do
    {:error,
     Error.new(
       :invalid_client,
       :configuration,
       "client must be a module and configuration tuple"
     )}
  end

  defp positive_limit(value, _) when is_integer(value) and value > 0, do: :ok

  defp positive_limit(_, name) do
    {:error,
     Error.new(:invalid_limit, :configuration, "byte limits must be positive integers", %{
       option: name
     })}
  end
end
