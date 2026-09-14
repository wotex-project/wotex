defmodule Wotex.Binding.HTTP.Form do
  @moduledoc """
  Builds an immutable HTTP request from an already selected Runtime Form.

  This internal mapper applies the package's operation-to-method defaults or a
  valid explicit method on a single-operation Form. It validates JSON media
  types, composes configured and Form headers, encodes bounded request content,
  and carries the interaction identity, deadline, and response limits into
  `Wotex.Binding.HTTP.Request`. Stream operations require the explicit `sse`
  subprotocol and select the event-stream Accept field.

  Action status queries and cancellation resolve an explicit target or prior
  result location against the selected href. `Wotex.Binding.HTTP.EmptyBody`
  preserves absence separately from JSON null. Contradictory headers, unsupported
  operations, missing targets, and invalid Form terms return structured binding
  errors. Mapping performs no I/O or credential handling and does not authorize
  either the selected Form or a resolved Action target. Draft-derived behavior
  follows the package's dated baseline without claiming W3C Profile conformance.
  """

  alias Wotex.Binding.HTTP.{Codec, Config, EmptyBody, Error, Headers}
  alias Wotex.Binding.HTTP.Request, as: HTTPRequest
  alias Wotex.Form, as: CoreForm
  alias Wotex.Runtime.{Request, Result}

  @default_methods %{
    readproperty: "GET",
    writeproperty: "PUT",
    invokeaction: "POST",
    observeproperty: "GET",
    queryaction: "GET",
    cancelaction: "DELETE",
    subscribeevent: "GET"
  }
  @stream_operations [:observeproperty, :subscribeevent]
  @target_operations [:queryaction, :cancelaction]
  @body_operations [:writeproperty, :invokeaction]
  @json "application/json"
  @event_stream "text/event-stream"

  @doc false
  @spec build(Request.t(), Config.t()) :: {:ok, HTTPRequest.t()} | {:error, Error.t()}
  def build(%Request{} = request, %Config{} = config) do
    form = CoreForm.to_map(request.form)
    stream? = request.operation in @stream_operations

    with :ok <- validate_stream_form(form, stream?),
         {:ok, media_type} <- media_type(form),
         {:ok, method} <- method(form, request.operation),
         {:ok, form_headers} <- form_headers(form),
         headers = Headers.merge(Config.headers(config), form_headers),
         {:ok, body} <- body(request.operation, request.input, Config.max_request_bytes(config)),
         {:ok, uri} <- target_uri(request),
         {:ok, representation_headers} <-
           representation_headers(headers, body, media_type, stream?) do
      HTTPRequest.new(method, uri, representation_headers, body,
        request_id: request.request_id,
        deadline: request.deadline,
        operation: request.operation,
        media_type: media_type,
        stream?: stream?,
        max_response_bytes: Config.max_response_bytes(config),
        max_event_bytes: Config.max_event_bytes(config),
        max_header_count: Config.max_header_count(config),
        max_header_bytes: Config.max_header_bytes(config),
        max_uri_bytes: Config.max_uri_bytes(config)
      )
    end
  end

  def build(_, _) do
    {:error,
     Error.new(:invalid_runtime_request, :request, "Runtime request and HTTP config are required")}
  end

  defp validate_stream_form(form, true) do
    if Map.get(form, "subprotocol") == "sse" do
      :ok
    else
      {:error,
       Error.new(
         :unsupported_subprotocol,
         :form,
         "streaming Forms must explicitly declare the sse subprotocol"
       )}
    end
  end

  defp validate_stream_form(_, false), do: :ok

  defp media_type(form) do
    input_type = Map.get(form, "contentType", @json)

    output_type =
      case Map.get(form, "response") do
        %{"contentType" => type} -> type
        _ -> input_type
      end

    with {:ok, normalized_input} <- json_media_type(input_type),
         {:ok, normalized_output} <- json_media_type(output_type),
         true <- normalized_input == normalized_output do
      {:ok, normalized_input}
    else
      false ->
        {:error,
         Error.new(
           :unsupported_response_media_type,
           :form,
           "request and response representations must both be application/json"
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp json_media_type(type) when is_binary(type) do
    normalized = normalize_media_type(type)

    if normalized == @json do
      {:ok, normalized}
    else
      {:error,
       Error.new(
         :unsupported_media_type,
         :form,
         "HTTP binding supports only application/json representations",
         %{media_type: normalized}
       )}
    end
  end

  defp json_media_type(_) do
    {:error, Error.new(:invalid_media_type, :form, "Form contentType must be a string")}
  end

  defp method(form, operation) do
    case Map.fetch(form, "htv:methodName") do
      {:ok, explicit} ->
        explicit_method(explicit, form_operations(form))

      :error ->
        default_method(operation)
    end
  end

  defp explicit_method(method, [_]) when is_binary(method) do
    if Headers.token?(method) do
      {:ok, method}
    else
      {:error, Error.new(:invalid_method, :form, "htv:methodName must be an HTTP token")}
    end
  end

  defp explicit_method(_, operations) when length(operations) > 1 do
    {:error,
     Error.new(
       :method_on_multi_operation_form,
       :form,
       "htv:methodName is not permitted on a Form with multiple operations"
     )}
  end

  defp explicit_method(_, _) do
    {:error, Error.new(:invalid_method, :form, "htv:methodName must be an HTTP token")}
  end

  defp default_method(operation) do
    case Map.fetch(@default_methods, operation) do
      {:ok, method} ->
        {:ok, method}

      :error ->
        {:error, Error.new(:no_default_method, :form, "operation has no HTTP request mapping")}
    end
  end

  defp form_operations(%{"op" => operation}) when is_binary(operation), do: [operation]
  defp form_operations(%{"op" => operations}) when is_list(operations), do: operations
  defp form_operations(_), do: []

  defp form_headers(form) do
    case Map.get(form, "htv:headers", []) do
      values when is_list(values) ->
        values
        |> Enum.map(&form_header/1)
        |> collect_headers()

      _ ->
        {:error, Error.new(:invalid_form_headers, :form, "htv:headers must be an array")}
    end
  end

  defp form_header(%{"htv:fieldName" => name} = header) when is_binary(name) do
    value = Map.get(header, "htv:fieldValue", "")

    if is_binary(value) do
      {:ok, {name, value}}
    else
      {:error,
       Error.new(:invalid_form_header, :form, "htv:fieldValue must be a string when present")}
    end
  end

  defp form_header(_) do
    {:error, Error.new(:invalid_form_header, :form, "htv:headers entries require htv:fieldName")}
  end

  defp collect_headers(results) do
    result =
      Enum.reduce_while(results, {:ok, []}, fn
        {:ok, header}, {:ok, headers} -> {:cont, {:ok, [header | headers]}}
        {:error, %Error{} = error}, _ -> {:halt, {:error, error}}
      end)

    case result do
      {:ok, headers} -> Headers.new(Enum.reverse(headers), :request)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp body(:writeproperty, %EmptyBody{}, _) do
    {:error, Error.new(:missing_input, :request, "writeproperty requires a JSON input")}
  end

  defp body(operation, %EmptyBody{}, _) when operation in @body_operations,
    do: {:ok, nil}

  defp body(operation, input, max_bytes) when operation in @body_operations,
    do: Codec.encode(input, max_bytes)

  defp body(operation, _, _) when operation in @target_operations,
    do: {:ok, nil}

  defp body(operation, input, _)
       when operation in [:readproperty, :observeproperty, :subscribeevent] do
    if is_nil(input) or match?(%EmptyBody{}, input) do
      {:ok, nil}
    else
      {:error, Error.new(:unexpected_input, :request, "operation does not define a request body")}
    end
  end

  defp body(_, _, _) do
    {:error, Error.new(:unsupported_operation, :request, "operation is not supported by HTTP")}
  end

  defp target_uri(%Request{operation: operation, input: input, resolved_href: base})
       when operation in @target_operations do
    case action_target(input) do
      {:ok, href} -> resolve_reference(base, href)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp target_uri(%Request{resolved_href: href}), do: {:ok, href}

  defp action_target(%Result{metadata: metadata, payload: payload}) do
    location = get_in(metadata, [:http, :location])

    cond do
      is_binary(location) and location != "" -> {:ok, location}
      is_map(payload) -> action_target(payload)
      true -> missing_action_target()
    end
  end

  defp action_target(%{"href" => href}) when is_binary(href) and href != "", do: {:ok, href}
  defp action_target(%{href: href}) when is_binary(href) and href != "", do: {:ok, href}
  defp action_target(href) when is_binary(href) and href != "", do: {:ok, href}
  defp action_target(_), do: missing_action_target()

  defp missing_action_target do
    {:error,
     Error.new(
       :missing_action_target,
       :request,
       "queryaction and cancelaction require an ActionStatus href or prior result"
     )}
  end

  defp resolve_reference(base, reference) do
    resolved =
      base
      |> URI.parse()
      |> URI.merge(reference)
      |> URI.to_string()

    {:ok, resolved}
  rescue
    URI.Error ->
      {:error, Error.new(:invalid_action_target, :request, "ActionStatus href is invalid")}
  end

  defp representation_headers(headers, body, media_type, stream?) do
    accept = if stream?, do: @event_stream, else: media_type

    case ensure_header(headers, "accept", accept) do
      {:ok, with_accept} -> maybe_content_type(with_accept, body, media_type)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp maybe_content_type(headers, nil, _), do: {:ok, headers}

  defp maybe_content_type(headers, _, media_type),
    do: ensure_header(headers, "content-type", media_type)

  defp ensure_header(headers, name, value) do
    case Headers.get(headers, name) do
      nil ->
        {:ok, Headers.put(headers, name, value)}

      existing ->
        if normalize_media_type(existing) == normalize_media_type(value) do
          {:ok, headers}
        else
          {:error,
           Error.new(:conflicting_header, :form, "HTTP field conflicts with Form representation", %{
             name: name
           })}
        end
    end
  end

  defp normalize_media_type(value) do
    value
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end
end
