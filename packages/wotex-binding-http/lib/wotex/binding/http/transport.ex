defmodule Wotex.Binding.HTTP.Transport do
  @moduledoc """
  Wotex Runtime transport backed by a consumer-supplied HTTP client port.

  It maps Runtime requests into HTTP values, normalizes callback failures,
  decodes finite JSON responses, and adapts client-framed SSE events into
  Runtime deliveries. Network processes and connection lifecycles remain
  owned by the caller.

  `subscribe/4` hands the client the Runtime subscription process as its owner.
  The client sends raw `{:wotex_transport_frame, event}` messages to that
  process, and `decode_frame/3` runs there: it enforces the configured event
  byte limit, decodes one JSON value, and returns `{:ok, data, meta}`, `:ignore`
  for a keep-alive frame with no data, or a classified binding error. No JSON
  decoding happens on the client's connection process.

  Every returned `Wotex.Binding.HTTP.Error` carries a retry `class`. HTTP status
  408 and a client deadline expiry are `:timeout`, 429 is `:rate_limited`, 502,
  503, and 504 and a failing or raising client call are `:unavailable`, codec,
  representation, handshake, and client-contract failures are `:protocol`, and
  every remaining failure is `:permanent`.
  """

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Binding.HTTP.{
    Codec,
    Config,
    Error,
    Form,
    Headers,
    Notification,
    Response,
    Subscription
  }

  alias Wotex.Binding.HTTP.Request, as: HTTPRequest
  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @event_stream "text/event-stream"
  @stream_operations [:observeproperty, :subscribeevent]
  @accepted_status 202
  @timeout_statuses [408]
  @rate_limited_statuses [429]
  @unavailable_statuses [502, 503, 504]
  @close_operations %{
    observeproperty: :unobserveproperty,
    subscribeevent: :unsubscribeevent
  }

  @impl Wotex.Runtime.Transport
  def request(%Request{} = request, %ExecutionContext{} = context, %Config{} = config) do
    with {:ok, http_request} <- Form.build(request, config),
         false <- HTTPRequest.stream?(http_request),
         {:ok, response} <- call_request(http_request, context.credential, config),
         {:ok, result} <- to_result(http_request, response, config) do
      {:ok, result}
    else
      true ->
        {:error,
         Error.new(:stream_requires_subscribe, :request, "streaming operation requires subscribe/4")}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def request(_, _, _) do
    {:error,
     Error.new(
       :invalid_transport_arguments,
       :request,
       "Runtime request, execution context, and HTTP config are required"
     )}
  end

  @impl Wotex.Runtime.Transport
  def subscribe(
        %Request{} = request,
        owner,
        %ExecutionContext{} = context,
        %Config{} = config
      )
      when is_pid(owner) do
    with {:ok, http_request} <- Form.build(request, config),
         true <- HTTPRequest.stream?(http_request),
         {:ok, subscription} <-
           call_subscribe(http_request, context.credential, owner, config) do
      {:ok, subscription}
    else
      false ->
        {:error,
         Error.new(
           :operation_is_not_streaming,
           :subscription,
           "only observeproperty and subscribeevent open SSE streams"
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def subscribe(_, _, _, _) do
    {:error,
     Error.new(
       :invalid_subscription_arguments,
       :subscription,
       "Runtime request, owner pid, execution context, and HTTP config are required"
     )}
  end

  @impl Wotex.Runtime.Transport
  def unsubscribe(
        %Subscription{} = subscription,
        %Request{} = request,
        %ExecutionContext{},
        %Config{} = config
      ) do
    {client_module, client_handle, _, _} =
      Subscription.unwrap(subscription)

    case validate_close(request, subscription, config) do
      :ok -> call_close(client_module, client_handle, config)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def unsubscribe(_, _, _, _) do
    {:error,
     Error.new(
       :invalid_unsubscribe_arguments,
       :subscription,
       "subscription, Runtime request, execution context, and HTTP config are required"
     )}
  end

  @doc """
  Decodes one client-delivered Server-Sent Event inside the subscription process.

  Wotex Runtime calls this callback for every `{:wotex_transport_frame, event}`
  message the client sends to the subscription owner. A frame with empty data is
  a keep-alive and returns `:ignore`; a frame above the configured event byte
  limit or carrying invalid JSON returns a classified
  `Wotex.Binding.HTTP.Error`.
  """
  @impl Wotex.Runtime.Transport
  def decode_frame(%Event{} = frame, %Request{operation: operation} = request, %Config{} = config)
      when operation in @stream_operations do
    decode_event(frame, request.request_id, operation, Config.max_event_bytes(config))
  end

  def decode_frame(_, _, _) do
    {:error,
     Error.new(
       :invalid_sse_event,
       :subscription,
       "transport frame is not a Server-Sent Event of an open stream",
       %{},
       :protocol
     )}
  end

  defp decode_event(%Event{data: ""}, _, _, _), do: :ignore

  defp decode_event(%Event{data: data} = event, request_id, operation, max_bytes) do
    if byte_size(data) > max_bytes do
      {:error,
       Error.new(
         :sse_event_too_large,
         :subscription,
         "SSE event exceeds byte limit",
         %{max_bytes: max_bytes, request_id: request_id, operation: operation},
         :protocol
       )}
    else
      case Codec.decode(data, max_bytes) do
        {:ok, decoded} -> {:ok, decoded, Notification.new(event, request_id, operation)}
        {:error, %Error{} = error} -> {:error, error}
      end
    end
  end

  defp call_request(request, credential, config) do
    {module, client_config} = Config.client(config)

    try do
      module.request(request, credential, client_config)
    rescue
      _ -> {:error, client_error(:client_request_exception, :client, :unavailable)}
    catch
      _, _ -> {:error, client_error(:client_request_exception, :client, :unavailable)}
    else
      {:ok, %Response{} = response} ->
        revalidate_response(response)

      {:error, reason} ->
        {:error, client_error(:client_request_failed, :client, client_class(reason))}

      _ ->
        {:error, client_error(:invalid_client_return, :client, :protocol)}
    end
  end

  defp call_subscribe(request, credential, owner, config) do
    {module, client_config} = Config.client(config)

    try do
      module.subscribe(request, credential, owner, client_config)
    rescue
      _ -> {:error, client_error(:client_subscribe_exception, :subscription, :unavailable)}
    catch
      _, _ -> {:error, client_error(:client_subscribe_exception, :subscription, :unavailable)}
    else
      {:ok, handle, response} ->
        with {:ok, validated} <- revalidate_subscription_response(response),
             :ok <- validate_handshake(validated) do
          {:ok,
           Subscription.new(
             config,
             handle,
             HTTPRequest.request_id(request),
             HTTPRequest.operation(request)
           )}
        else
          {:error, %Error{} = error} ->
            _ = close_after_failed_handshake(module, handle, client_config)
            {:error, error}
        end

      {:error, reason} ->
        {:error, client_error(:client_subscribe_failed, :subscription, client_class(reason))}

      _ ->
        {:error, client_error(:invalid_client_return, :subscription, :protocol)}
    end
  end

  defp call_close(module, handle, config) do
    {_, client_config} = Config.client(config)

    try do
      module.close(handle, client_config)
    rescue
      _ -> {:error, client_error(:client_close_exception, :subscription, :unavailable)}
    catch
      _, _ -> {:error, client_error(:client_close_exception, :subscription, :unavailable)}
    else
      :ok ->
        :ok

      {:error, reason} ->
        {:error, client_error(:client_close_failed, :subscription, client_class(reason))}

      _ ->
        {:error, client_error(:invalid_client_return, :subscription, :protocol)}
    end
  end

  defp close_after_failed_handshake(module, handle, client_config) do
    module.close(handle, client_config)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp revalidate_response(%Response{} = response) do
    Response.new(Response.status(response), Response.headers(response), Response.body(response))
  end

  defp revalidate_subscription_response(%Response{} = response), do: revalidate_response(response)

  defp revalidate_subscription_response(_) do
    {:error, client_error(:invalid_client_return, :subscription, :protocol)}
  end

  defp to_result(request, response, config) do
    status = Response.status(response)
    body = Response.body(response)

    cond do
      status not in 200..299 ->
        {:error,
         Error.new(
           :http_status,
           :response,
           "HTTP response status is not successful",
           %{
             request_id: HTTPRequest.request_id(request),
             operation: HTTPRequest.operation(request),
             status: status
           },
           status_class(status)
         )}

      byte_size(body) > Config.max_response_bytes(config) ->
        {:error,
         Error.new(
           :response_body_too_large,
           :response,
           "HTTP response exceeds byte limit",
           %{max_bytes: Config.max_response_bytes(config)},
           :protocol
         )}

      status in [204, 205] and body != "" ->
        {:error,
         Error.new(
           :unexpected_response_body,
           :response,
           "HTTP status requires an empty body",
           %{status: status},
           :protocol
         )}

      true ->
        with :ok <- validate_response_media_type(request, response),
             {:ok, payload} <- decode_body(body, Config.max_response_bytes(config)),
             {:ok, metadata} <- response_metadata(request, response),
             {:ok, result} <-
               Result.new(
                 HTTPRequest.request_id(request),
                 HTTPRequest.operation(request),
                 payload,
                 status: result_status(status),
                 metadata: metadata
               ) do
          {:ok, result}
        else
          {:error, %Error{} = error} -> {:error, error}
          {:error, _} -> {:error, client_error(:result_build_failed, :response, :protocol)}
        end
    end
  end

  defp validate_response_media_type(_, %Response{} = response)
       when response.body == "",
       do: :ok

  defp validate_response_media_type(request, response) do
    actual = Headers.get(Response.headers(response), "content-type")

    if is_nil(actual) or normalize_media_type(actual) == HTTPRequest.media_type(request) do
      :ok
    else
      {:error,
       Error.new(
         :unexpected_response_media_type,
         :response,
         "HTTP response is not the Form's JSON representation",
         %{media_type: normalize_media_type(actual)},
         :protocol
       )}
    end
  end

  defp decode_body("", _), do: {:ok, nil}
  defp decode_body(body, max_bytes), do: Codec.decode(body, max_bytes)

  defp response_metadata(request, response) do
    headers = Response.headers(response)

    with {:ok, location} <- resolve_location(request, Headers.get(headers, "location")) do
      http = %{
        method: HTTPRequest.method(request),
        request_uri: HTTPRequest.uri(request),
        status: Response.status(response),
        headers: headers
      }

      metadata =
        if is_nil(location), do: %{http: http}, else: %{http: Map.put(http, :location, location)}

      {:ok, metadata}
    end
  end

  defp resolve_location(_, nil), do: {:ok, nil}

  defp resolve_location(request, location) when is_binary(location) do
    resolved =
      request
      |> HTTPRequest.uri()
      |> URI.parse()
      |> URI.merge(location)
      |> URI.to_string()

    case HTTPRequest.new("GET", resolved, [], nil,
           request_id: "location-validation",
           operation: :queryaction,
           media_type: "application/json",
           stream?: false,
           max_response_bytes: HTTPRequest.max_response_bytes(request),
           max_event_bytes: HTTPRequest.max_event_bytes(request)
         ) do
      {:ok, _} -> {:ok, resolved}
      {:error, _} -> invalid_location()
    end
  rescue
    URI.Error -> invalid_location()
  end

  defp invalid_location do
    {:error,
     Error.new(:invalid_location, :response, "HTTP Location field is invalid", %{}, :protocol)}
  end

  defp validate_handshake(response) do
    content_type = Headers.get(Response.headers(response), "content-type")

    cond do
      Response.status(response) != 200 ->
        {:error,
         Error.new(
           :sse_handshake_status,
           :subscription,
           "SSE handshake must return HTTP status 200",
           %{status: Response.status(response)},
           :protocol
         )}

      normalize_media_type(content_type) != @event_stream ->
        {:error,
         Error.new(
           :sse_handshake_media_type,
           :subscription,
           "SSE handshake must return text/event-stream",
           %{},
           :protocol
         )}

      Response.body(response) != "" ->
        {:error,
         Error.new(
           :sse_handshake_body,
           :subscription,
           "SSE handshake response value must not buffer stream data",
           %{},
           :protocol
         )}

      true ->
        :ok
    end
  end

  defp validate_close(request, subscription, config) do
    {configured_module, _} = Config.client(config)

    cond do
      request.request_id != subscription.request_id ->
        {:error,
         Error.new(
           :subscription_request_mismatch,
           :subscription,
           "close request does not match subscription identity"
         )}

      Map.get(@close_operations, subscription.operation) != request.operation ->
        {:error,
         Error.new(
           :subscription_operation_mismatch,
           :subscription,
           "close operation does not match stream operation"
         )}

      configured_module != subscription.client_module or
          Config.instance_ref(config) != subscription.instance_ref ->
        {:error,
         Error.new(
           :subscription_client_mismatch,
           :subscription,
           "close configuration does not match the opening client"
         )}

      true ->
        :ok
    end
  end

  defp normalize_media_type(nil), do: nil

  defp normalize_media_type(value) do
    value
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp client_error(code, phase, class),
    do:
      Error.new(
        code,
        phase,
        "supplied HTTP client failed or violated its contract",
        %{},
        class
      )

  defp client_class(:timeout), do: :timeout
  defp client_class(_), do: :unavailable

  defp status_class(status) when status in @timeout_statuses, do: :timeout
  defp status_class(status) when status in @rate_limited_statuses, do: :rate_limited
  defp status_class(status) when status in @unavailable_statuses, do: :unavailable
  defp status_class(_), do: :permanent

  defp result_status(@accepted_status), do: :accepted
  defp result_status(_), do: :ok
end
