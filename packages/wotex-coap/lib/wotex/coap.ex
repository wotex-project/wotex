defmodule Wotex.CoAP do
  @moduledoc """
  Executes bounded Constrained Application Protocol exchanges over UDP, DTLS,
  or an explicitly selected native OSCORE session.

  `Wotex.CoAP` is the package facade for connection lifecycle and native
  request construction. `connect/1` starts one caller-scoped
  `Wotex.CoAP.Connection`; `message/1` validates a request map;
  `send/2` performs a correlated exchange; and `disconnect/1` closes the exact
  socket owner. GET, POST, PUT, and DELETE helpers assemble complete bodies.
  `discover/2` returns bounded CoRE links. `subscribe/2` establishes an owned
  Observe relationship, and `unsubscribe/2` cancels its exact generation.
  The session serializes requests and applies a finite timeout.

  ## Execution boundary

  Loading the module performs no network operation. The consumer supplies a
  numeric IPv4 or IPv6 destination and owns routing, authorization,
  supervision, and credential policy. Explicit `coaps` sessions use Datagram
  Transport Layer Security (DTLS) 1.2 with validated PSK or PKI values from
  `Wotex.CoAP.Security`. Explicit `coap` sessions with an OSCORE credential and
  verified `native_backend` use the pinned native owner for unary exchanges.
  Multicast and extended tokens remain unsupported. The separate compatibility
  `receive/2` callback is unsupported because `send/2` returns its correlated
  response directly.
  """

  import Kernel, except: [send: 2]
  alias Wotex.CoAP.{Codec, Connection, Error, Message, Security}
  alias Wotex.CoAP.Native.Connection, as: NativeConnection
  @methods %{get: 1, post: 2, put: 3, delete: 4}
  @formats %{text: 0, link_format: 40, octet_stream: 42, json: 50, cbor: 60}
  @type session :: %{pid: pid(), timeout: pos_integer()}

  @doc """
  Returns the pure Runtime profile for unary UDP interactions.

      iex> Wotex.Runtime.BindingProfile.id(Wotex.CoAP.profile())
      :coap

  Profile construction starts no process and checks no installed backend.
  """
  @spec profile() :: Wotex.Runtime.BindingProfile.t()
  def profile, do: runtime_profile(:coap, [:readproperty, :writeproperty, :invokeaction])

  @doc "Selects an admitted UDP, DTLS, or OSCORE Runtime profile without acquisition."
  @spec profile(term()) :: {:ok, Wotex.Runtime.BindingProfile.t()} | {:error, Error.t()}
  def profile(:udp), do: {:ok, profile()}

  def profile(mode) when mode in [:udp_observe, :dtls, :oscore] do
    id = %{udp_observe: :coap_observe, dtls: :coaps, oscore: :coap_oscore}[mode]

    {:ok,
     runtime_profile(id, [
       :readproperty,
       :writeproperty,
       :invokeaction,
       :observeproperty,
       :unobserveproperty,
       :subscribeevent,
       :unsubscribeevent
     ])}
  end

  def profile(_), do: {:error, Error.new(:unsupported_profile)}

  defp runtime_profile(id, operations) do
    {:ok, profile} =
      Wotex.Runtime.BindingProfile.new(
        id: id,
        schemes: [if(id == :coaps, do: "coaps", else: "coap")],
        operations: operations,
        media_types: ["application/json", "application/octet-stream", "text/plain;charset=utf-8"]
      )

    profile
  end

  @doc """
  Reports the implemented baseline exchange profile.

  `:max_datagram_size` is the 1152-byte wire limit; `:max_body_size` is the
  1 MiB complete-body limit. The legacy `:max_payload_size` key remains an
  alias of the datagram limit, not the maximum reassembled body size.
  """
  @spec capabilities() :: %{
          bidirectional: true,
          reliable: false,
          ordered: false,
          multicast: false,
          qos_levels: [:at_most_once, ...],
          max_payload_size: 1152,
          max_datagram_size: 1152,
          max_body_size: 1_048_576,
          connection_oriented: false,
          supports_streaming: true,
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
      max_datagram_size: 1152,
      max_body_size: 1_048_576,
      connection_oriented: false,
      supports_streaming: true,
      discovery_capable: true
    }

  @doc "Explicitly opens an owned UDP, DTLS, or native OSCORE session."
  @spec connect(keyword()) :: {:ok, session()} | {:error, term()}
  def connect(opts) do
    case connection_adapter(opts) do
      {:ok, :datagram, options} ->
        with {:ok, config} <- Connection.config(options),
             {:ok, pid} <- Connection.start_link(options),
             do: {:ok, %{pid: pid, timeout: config.timeout}}

      {:ok, :native, options} ->
        with {:ok, config} <- NativeConnection.config(options),
             {:ok, pid} <- NativeConnection.start(options),
             do: {:ok, %{pid: pid, timeout: config.timeout}}

      {:error, %Error{}} = error ->
        error
    end
  end

  @doc "Performs a synchronous exchange from a legacy-shaped method/path/payload map."
  @spec send(session(), map()) :: {:ok, Message.t()} | {:error, Error.t()}
  def send(session, input), do: send(session, input, [])

  @doc false
  @spec send(session(), map(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def send(session, input, options) do
    with :ok <- session(session),
         {:ok, message} <- message(input) do
      case session_adapter(session.pid) do
        :native ->
          NativeConnection.request(
            session.pid,
            native_request(input, message),
            session.timeout,
            native_request_options(options)
          )

        :datagram ->
          Connection.transfer(session.pid, message, session.timeout, options)
      end
    end
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

  @doc "Discovers bounded raw links with GET/Accept 40 under one complete-body deadline."
  @spec discover(session(), map()) :: {:ok, [Wotex.CoAP.LinkFormat.link()]} | {:error, Error.t()}
  def discover(session, input) do
    with :ok <- session(session),
         {:ok, request_input, request} <- discovery_request(input),
         {:ok, reply} <- discovery_transfer(session, request_input, request),
         do: discovery_links(reply)
  end

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
    with :ok <- session(value) do
      case NativeConnection.close(value.pid) do
        {:error, %Error{code: :invalid_session}} -> Connection.close(value.pid)
        result -> result
      end
    end
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

  @doc "Establishes one dedicated native observation after validating its initial representation."
  @spec subscribe(session(), binary() | map()) ::
          {:ok, Wotex.CoAP.Subscription.t()} | {:error, Error.t()}
  def subscribe(session, path) when is_binary(path),
    do: subscribe(session, %{path: path})

  def subscribe(session, %{path: path} = input) when map_size(input) <= 7 do
    with :ok <- session(session),
         true <-
           Map.keys(input) --
             [
               :path,
               :receiver,
               :renew,
               :max_queue_length,
               :confirmable,
               :accept,
               :observation_kind
             ] == [] do
      receiver = Map.get(input, :receiver, self())

      common = [
        renew: Map.get(input, :renew, true),
        max_queue_length: Map.get(input, :max_queue_length, 1000)
      ]

      case session_adapter(session.pid) do
        :native ->
          options =
            common ++
              [
                confirmable: Map.get(input, :confirmable, true),
                accept: Map.get(input, :accept),
                observation_kind: Map.get(input, :observation_kind, :property)
              ]

          NativeConnection.observe(session.pid, path, receiver, options, session.timeout)

        :datagram ->
          Connection.observe(session.pid, path, receiver, common, session.timeout)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_observation_options)}
    end
  end

  def subscribe(_, _), do: {:error, Error.new(:invalid_observation_options)}

  @doc "Cancels the exact original subscription and releases its dedicated session."
  @spec unsubscribe(session(), Wotex.CoAP.Subscription.t()) :: :ok | {:error, Error.t()}
  def unsubscribe(session, handle) do
    with :ok <- session(session) do
      case NativeConnection.unobserve(session.pid, handle, session.timeout) do
        {:error, %Error{code: :invalid_session}} ->
          Connection.unobserve(session.pid, handle, session.timeout)

        result ->
          result
      end
    end
  end

  defp method(session, method, path, payload, options) do
    with {:ok, options} <- helper_options(options, %{}),
         do: send(session, Map.merge(options, %{method: method, path: path, payload: payload}))
  end

  defp helper_options([], values), do: {:ok, values}

  defp helper_options([{key, value} | rest], values)
       when key in [:confirmable, :content_format, :accept] and not is_map_key(values, key),
       do: helper_options(rest, Map.put(values, key, value))

  defp helper_options(_, _), do: {:error, Error.new(:invalid_request)}

  defp discovery_request(input) when is_map(input) and map_size(input) <= 1 do
    query = Map.get(input, :query)

    if Map.keys(input) -- [:query] == [] and
         (is_nil(query) or
            (is_binary(query) and byte_size(query) <= 1024 and
               not String.starts_with?(query, "?"))) do
      path = "/.well-known/core" <> if(is_nil(query), do: "", else: "?" <> query)
      request_input = %{method: :get, path: path, accept: 40}

      case message(request_input) do
        {:ok, request} -> {:ok, request_input, request}
        {:error, %Error{}} = error -> error
      end
    else
      {:error, Error.new(:invalid_discovery_request)}
    end
  end

  defp discovery_request(_), do: {:error, Error.new(:invalid_discovery_request)}

  defp discovery_links(%Message{code: 69} = reply) do
    case Codec.option(reply, 12) do
      [value] when value in [<<40>>, <<0, 40>>] -> Wotex.CoAP.LinkFormat.decode(reply.payload)
      _ -> {:error, Error.new(:unexpected_content_format)}
    end
  end

  defp discovery_links(_), do: {:error, Error.new(:invalid_discovery_response)}

  defp discovery_transfer(session, input, request) do
    case session_adapter(session.pid) do
      :native ->
        NativeConnection.request(
          session.pid,
          native_request(input, request),
          session.timeout,
          max_body_size: 65_536
        )

      :datagram ->
        Connection.transfer(session.pid, request, session.timeout, max_body_size: 65_536)
    end
  end

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

  defp connection_adapter(options) do
    with {:ok, values} <- connection_options(options, %{}) do
      case Map.get(values, :security) do
        %Security{mode: :oscore} -> native_connection_options(options, values)
        _ -> {:ok, :datagram, options}
      end
    end
  end

  defp connection_options([], values), do: {:ok, values}

  defp connection_options([{key, value} | rest], values) when is_atom(key) do
    if Map.has_key?(values, key),
      do: {:error, Error.new(:invalid_options)},
      else: connection_options(rest, Map.put(values, key, value))
  end

  defp connection_options(_, _), do: {:error, Error.new(:invalid_options)}

  defp native_connection_options(options, values) do
    if Map.get(values, :scheme, :coap) == :coap do
      {:ok, :native, Keyword.delete(options, :scheme)}
    else
      {:error, Error.new(:unsupported_security)}
    end
  end

  defp session_adapter(pid) do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_owner}) do
      {{:dictionary, :wotex_coap_owner}, {NativeConnection, generation, admission}}
      when is_integer(generation) and is_reference(admission) ->
        :native

      _ ->
        :datagram
    end
  end

  defp native_request(input, message) do
    request = %{
      method: input.method,
      path: input.path,
      confirmable: message.type == :con
    }

    request
    |> put_format(:accept, Map.get(input, :accept))
    |> put_format(:content_format, Map.get(input, :content_format))
    |> put_payload(input)
  end

  defp native_request_options([]), do: []

  defp native_request_options(options) when is_list(options) do
    if Keyword.keyword?(options) and Keyword.keys(options) -- [:max_body_size] == [],
      do: options,
      else: :invalid
  end

  defp native_request_options(_), do: :invalid

  defp put_format(request, _, nil), do: request

  defp put_format(request, key, value) do
    {:ok, value} = format(value)
    Map.put(request, key, value)
  end

  defp put_payload(request, input) do
    if Map.has_key?(input, :payload),
      do: Map.put(request, :payload, Map.fetch!(input, :payload)),
      else: request
  end
end
