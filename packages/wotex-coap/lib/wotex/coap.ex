defmodule Wotex.CoAP do
  @moduledoc "Consumer-neutral CoAP UDP exchanges and compatibility callbacks."

  import Kernel, except: [send: 2]
  alias Wotex.CoAP.{Codec, Connection, Error, Message}
  @methods %{get: 1, post: 2, put: 3, delete: 4}
  @formats %{text: 0, link_format: 40, octet_stream: 42, json: 50, cbor: 60}
  @type session :: %{pid: pid(), timeout: pos_integer()}

  @doc "Reports the implemented baseline exchange profile."
  @spec capabilities() :: %{
          bidirectional: true,
          reliable: false,
          ordered: false,
          multicast: false,
          qos_levels: [:at_most_once, ...],
          max_payload_size: 1152,
          connection_oriented: false,
          supports_streaming: false,
          discovery_capable: true
        }
  def capabilities,
    do: %{
      bidirectional: true,
      reliable: false,
      ordered: false,
      multicast: false,
      qos_levels: [:at_most_once],
      max_payload_size: 1152,
      connection_oriented: false,
      supports_streaming: false,
      discovery_capable: true
    }

  @doc "Explicitly opens a linked UDP owner; no simulator fallback or security downgrade."
  @spec connect(keyword()) :: {:ok, session()} | {:error, term()}
  def connect(opts) do
    with {:ok, config} <- Connection.config(opts),
         {:ok, pid} <- Connection.start_link(opts),
         do: {:ok, %{pid: pid, timeout: config.timeout}}
  end

  @doc "Performs a synchronous exchange from a legacy-shaped method/path/payload map."
  @spec send(session(), map()) :: {:ok, Message.t()} | {:error, Error.t()}
  def send(%{pid: pid, timeout: timeout}, message) do
    with {:ok, message} <- message(message), do: Connection.transfer(pid, message, timeout)
  end

  @doc "Builds an immutable request with an explicit method and optional raw payload."
  @spec message(term()) :: {:ok, Message.t()} | {:error, Error.t()}
  def message(%{method: method, path: path} = input) when is_binary(path) do
    with {:ok, uri} <- URI.new(path),
         true <- is_nil(uri.scheme) and is_nil(uri.host) and is_nil(uri.fragment),
         {:ok, code} <- Map.fetch(@methods, method),
         {:ok, format} <- format(Map.get(input, :content_format)),
         payload = Map.get(input, :payload, <<>>),
         true <- is_binary(payload) and byte_size(payload) <= 1_048_576,
         true <- is_boolean(Map.get(input, :confirmable, true)) do
      path_options =
        case String.trim_leading(uri.path || "", "/") do
          "" -> []
          path -> for segment <- String.split(path, "/"), do: {11, URI.decode(segment)}
        end

      query =
        if uri.query, do: for(q <- String.split(uri.query, "&"), do: {15, URI.decode(q)}), else: []

      content = if is_nil(format), do: [], else: [{12, Codec.uint(format)}]

      message = %Message{
        type: if(Map.get(input, :confirmable, true), do: :con, else: :non),
        code: code,
        message_id: 0,
        options: path_options ++ content ++ query,
        payload: payload
      }

      with {:ok, _} <- Codec.encode(%{message | payload: <<>>}),
           :ok <- Codec.validate_options(message),
           do: {:ok, message}
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  end

  def message(_), do: {:error, Error.new(:invalid_request)}

  @doc "Closes the owned socket idempotently."
  @spec disconnect(session()) :: :ok
  def disconnect(%{pid: pid}), do: Connection.close(pid)

  @doc "Compatibility receive is unsupported because send returns the correlated response."
  @spec receive(term(), term()) :: {:error, Error.t()}
  def receive(_, _), do: {:error, Error.new(:not_supported)}

  @doc "Performs a live discovery-resource GET as a health probe."
  @spec health_check(session()) :: {:ok, :healthy} | {:error, Error.t()}
  def health_check(conn) do
    case send(conn, %{method: :get, path: "/.well-known/core"}) do
      {:ok, %{code: code}} when code in 64..95 -> {:ok, :healthy}
      {:ok, %{code: code}} -> {:error, Error.new(:remote_response, nil, %{code: code})}
      {:error, _} = error -> error
    end
  end

  @doc "Observe transport graduation is separate from pure freshness support."
  @spec subscribe(term(), term()) :: :not_supported
  def subscribe(_, _), do: :not_supported

  @doc "No observation is created by the baseline exchange profile."
  @spec unsubscribe(term(), term()) :: :not_supported
  def unsubscribe(_, _), do: :not_supported

  defp format(nil), do: {:ok, nil}
  defp format(value) when is_integer(value) and value in 0..65_535, do: {:ok, value}
  defp format(value), do: Map.fetch(@formats, value)
end
