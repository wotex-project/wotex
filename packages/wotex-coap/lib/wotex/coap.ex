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
  def send(session, input) do
    with :ok <- session(session),
         {:ok, message} <- message(input),
         do: Connection.transfer(session.pid, message, session.timeout)
  end

  @doc "Gets a complete binary representation using explicit native request options."
  @spec get(session(), binary(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def get(session, path, options \\ []), do: method(session, :get, path, <<>>, options)

  @doc "Posts an explicit binary body and returns the complete response."
  @spec post(session(), binary(), binary(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def post(session, path, payload, options \\ []),
    do: method(session, :post, path, payload, options)

  @doc "Puts an explicit binary body and returns the complete response."
  @spec put(session(), binary(), binary(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def put(session, path, payload, options \\ []), do: method(session, :put, path, payload, options)

  @doc "Deletes a resource with an empty request body and explicit native options."
  @spec delete(session(), binary(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def delete(session, path, options \\ []), do: method(session, :delete, path, <<>>, options)

  @doc "Builds an immutable request with an explicit method and optional raw payload."
  @spec message(term()) :: {:ok, Message.t()} | {:error, Error.t()}
  def message(%{method: method, path: path} = input) when is_binary(path) do
    with true <-
           map_size(input) <= 6 and
             Map.keys(input) -- [:method, :path, :payload, :confirmable, :content_format, :accept] ==
               [],
         true <- byte_size(path) <= 4096 and String.valid?(path) and clean_reference?(path),
         {:ok, uri} <- URI.new(path),
         true <-
           is_nil(uri.scheme) and is_nil(uri.host) and is_nil(uri.userinfo) and is_nil(uri.fragment),
         {:ok, code} <- Map.fetch(@methods, method),
         {:ok, format} <- format(Map.get(input, :content_format)),
         {:ok, accept} <- format(Map.get(input, :accept)),
         payload = Map.get(input, :payload, <<>>),
         true <- is_binary(payload) and byte_size(payload) <= 1_048_576,
         true <- is_boolean(Map.get(input, :confirmable, true)),
         {:ok, path_options} <- path_options(uri.path || "") do
      query = query_options(uri.query)
      content = optional_option(12, format)
      accepted = optional_option(17, accept)

      message = %Message{
        type: if(Map.get(input, :confirmable, true), do: :con, else: :non),
        code: code,
        message_id: 0,
        options: path_options ++ content ++ query ++ accepted,
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
  @spec disconnect(session()) :: :ok | {:error, Error.t()}
  def disconnect(value) do
    with :ok <- session(value), do: Connection.close(value.pid)
  end

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

  defp method(session, method, path, payload, options) do
    with {:ok, options} <- helper_options(options, %{}),
         do: send(session, Map.merge(options, %{method: method, path: path, payload: payload}))
  end

  defp helper_options([], values), do: {:ok, values}

  defp helper_options([{key, value} | rest], values)
       when key in [:confirmable, :content_format, :accept] and not is_map_key(values, key),
       do: helper_options(rest, Map.put(values, key, value))

  defp helper_options(_, _), do: {:error, Error.new(:invalid_request)}

  defp session(%{pid: pid, timeout: timeout} = value)
       when map_size(value) == 2 and is_pid(pid) and is_integer(timeout) and timeout in 1..60_000,
       do: :ok

  defp session(_), do: {:error, Error.new(:invalid_session)}

  defp clean_reference?(<<>>), do: true

  defp clean_reference?(<<"%", a, b, rest::binary>>)
       when a in ?0..?9 or a in ?A..?F or a in ?a..?f do
    (b in ?0..?9 or b in ?A..?F or b in ?a..?f) and clean_reference?(rest)
  end

  defp clean_reference?(<<byte, _::binary>>) when byte <= 32 or byte == 127 or byte == ?%, do: false
  defp clean_reference?(<<_, rest::binary>>), do: clean_reference?(rest)

  defp path_options(path) when path in ["", "/"], do: {:ok, []}

  defp path_options(path) do
    path =
      case path do
        <<"/", rest::binary>> -> rest
        relative -> relative
      end

    segments =
      path
      |> String.split("/")
      |> Enum.map(&URI.decode/1)

    if Enum.any?(segments, &(&1 in [".", ".."])),
      do: {:error, Error.new(:invalid_request)},
      else: {:ok, Enum.map(segments, &{11, &1})}
  end

  defp query_options(nil), do: []
  defp query_options(query), do: for(q <- String.split(query, "&"), do: {15, URI.decode(q)})
  defp optional_option(_, nil), do: []
  defp optional_option(number, value), do: [{number, Codec.uint(value)}]

  defp format(nil), do: {:ok, nil}
  defp format(value) when is_integer(value) and value in 0..65_535, do: {:ok, value}
  defp format(value), do: Map.fetch(@formats, value)
end
