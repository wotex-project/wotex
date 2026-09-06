defmodule Wotex.Binding.HTTP.Transport do
  @moduledoc """
  Wotex Runtime transport backed by a consumer-supplied HTTP client port.

  It maps Runtime requests into HTTP values, normalizes callback failures,
  decodes finite JSON responses, and converts client-framed SSE events into
  Runtime notifications. Network processes and connection lifecycles remain
  owned by the caller.
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
        receiver,
        %ExecutionContext{} = context,
        %Config{} = config
      )
      when is_pid(receiver) do
    with {:ok, http_request} <- Form.build(request, config),
         true <- HTTPRequest.stream?(http_request),
         handler = event_handler(http_request, receiver, config),
         {:ok, subscription} <-
           call_subscribe(http_request, context.credential, handler, config) do
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
       "Runtime request, receiver, execution context, and HTTP config are required"
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

  defp call_request(request, credential, config) do
    {module, client_config} = Config.client(config)

    returned =
      try do
        module.request(request, credential, client_config)
      rescue
        _ -> {:client_exception, nil}
      end

    case returned do
      {:ok, %Response{} = response} -> revalidate_response(response)
      {:error, _} -> {:error, client_error(:client_request_failed, :client)}
      {:client_exception, nil} -> {:error, client_error(:client_request_exception, :client)}
      _ -> {:error, client_error(:invalid_client_return, :client)}
    end
  end

  defp call_subscribe(request, credential, handler, config) do
    {module, client_config} = Config.client(config)

    returned =
      try do
        module.subscribe(request, credential, handler, client_config)
      rescue
        _ -> {:client_exception, nil}
      end

    case returned do
      {:ok, handle, %Response{} = response} ->
        with {:ok, validated} <- revalidate_response(response),
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

      {:error, _} ->
        {:error, client_error(:client_subscribe_failed, :subscription)}

      {:client_exception, nil} ->
        {:error, client_error(:client_subscribe_exception, :subscription)}

      _ ->
        {:error, client_error(:invalid_client_return, :subscription)}
    end
  end

  defp call_close(module, handle, config) do
    {_, client_config} = Config.client(config)

    returned =
      try do
        module.close(handle, client_config)
      rescue
        _ -> {:client_exception, nil}
      end

    case returned do
      :ok -> :ok
      {:error, _} -> {:error, client_error(:client_close_failed, :subscription)}
      {:client_exception, nil} -> {:error, client_error(:client_close_exception, :subscription)}
      _ -> {:error, client_error(:invalid_client_return, :subscription)}
    end
  end

  defp close_after_failed_handshake(module, handle, client_config) do
    try do
      module.close(handle, client_config)
    rescue
      _ -> :ok
    end
  end

  defp revalidate_response(%Response{} = response) do
    Response.new(Response.status(response), Response.headers(response), Response.body(response))
  end

  defp to_result(request, response, config) do
    status = Response.status(response)
    body = Response.body(response)

    cond do
      status not in 200..299 ->
        {:error,
         Error.new(:http_status, :response, "HTTP response status is not successful", %{
           request_id: HTTPRequest.request_id(request),
           operation: HTTPRequest.operation(request),
           status: status
         })}

      byte_size(body) > Config.max_response_bytes(config) ->
        {:error,
         Error.new(:response_body_too_large, :response, "HTTP response exceeds byte limit", %{
           max_bytes: Config.max_response_bytes(config)
         })}

      status in [204, 205] and body != "" ->
        {:error,
         Error.new(:unexpected_response_body, :response, "HTTP status requires an empty body", %{
           status: status
         })}

      true ->
        with :ok <- validate_response_media_type(request, response),
             {:ok, payload} <- decode_body(body, Config.max_response_bytes(config)),
             {:ok, metadata} <- response_metadata(request, response),
             {:ok, result} <-
               Result.new(
                 HTTPRequest.request_id(request),
                 HTTPRequest.operation(request),
                 payload,
                 status: status,
                 metadata: metadata
               ) do
          {:ok, result}
        else
          {:error, %Error{} = error} -> {:error, error}
          {:error, _} -> {:error, client_error(:result_build_failed, :response)}
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
         %{media_type: normalize_media_type(actual)}
       )}
    end
  end

  defp decode_body("", _), do: {:ok, nil}
  defp decode_body(body, max_bytes), do: Codec.decode(body, max_bytes)

  defp response_metadata(request, response) do
    headers = Response.headers(response)

    with {:ok, location} <-
           resolve_location(HTTPRequest.uri(request), Headers.get(headers, "location")) do
      http = %{
        method: HTTPRequest.method(request),
        request_uri: HTTPRequest.uri(request),
        headers: headers
      }

      metadata =
        if is_nil(location), do: %{http: http}, else: %{http: Map.put(http, :location, location)}

      {:ok, metadata}
    end
  end

  defp resolve_location(_, nil), do: {:ok, nil}

  defp resolve_location(base, location) when is_binary(location) do
    resolved =
      base
      |> URI.parse()
      |> URI.merge(location)
      |> URI.to_string()

    case HTTPRequest.new("GET", resolved, [], nil,
           request_id: "location-validation",
           operation: :queryaction,
           media_type: "application/json",
           stream?: false
         ) do
      {:ok, _} -> {:ok, resolved}
      {:error, _} -> invalid_location()
    end
  rescue
    URI.Error -> invalid_location()
  end

  defp invalid_location do
    {:error, Error.new(:invalid_location, :response, "HTTP Location field is invalid")}
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
           %{status: Response.status(response)}
         )}

      normalize_media_type(content_type) != @event_stream ->
        {:error,
         Error.new(
           :sse_handshake_media_type,
           :subscription,
           "SSE handshake must return text/event-stream"
         )}

      Response.body(response) != "" ->
        {:error,
         Error.new(
           :sse_handshake_body,
           :subscription,
           "SSE handshake response value must not buffer stream data"
         )}

      true ->
        :ok
    end
  end

  defp event_handler(request, receiver, config) do
    request_id = HTTPRequest.request_id(request)
    operation = HTTPRequest.operation(request)
    max_bytes = Config.max_event_bytes(config)

    fn event ->
      payload = decode_event(event, request_id, operation, max_bytes)
      send(receiver, {:wotex_transport, payload})
      :ok
    end
  end

  defp decode_event(%Event{} = event, request_id, operation, max_bytes) do
    if byte_size(Event.data(event)) > max_bytes do
      {:error,
       Error.new(:sse_event_too_large, :subscription, "SSE event exceeds byte limit", %{
         max_bytes: max_bytes,
         request_id: request_id,
         operation: operation
       })}
    else
      case Codec.decode(Event.data(event), max_bytes) do
        {:ok, data} -> {:ok, Notification.new(event, data, request_id, operation)}
        {:error, %Error{} = error} -> {:error, error}
      end
    end
  end

  defp decode_event(_, request_id, operation, _) do
    {:error,
     Error.new(:invalid_sse_event, :subscription, "client delivered an invalid SSE event", %{
       request_id: request_id,
       operation: operation
     })}
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

  defp client_error(code, phase),
    do: Error.new(code, phase, "supplied HTTP client failed or violated its contract")
end
