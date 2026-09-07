defmodule Wotex.Binding.HTTP.Request do
  @moduledoc """
  Immutable, credential-free HTTP request passed to the supplied client.

  The value is the complete result of Form mapping: an absolute HTTP target,
  validated fields, an optional encoded body, deadline, interaction identity,
  selected media type, streaming intent, and the response and event byte limits
  the client must honor. Authentication travels separately through the client
  callback.

  The deadline is absolute: an integer is a point on the calling node's
  monotonic clock in milliseconds and a `DateTime` is a UTC instant. The client
  reads its own clock and computes the remaining budget with
  `Wotex.Runtime.Context.remaining_ms/2`; this package never reads a clock.

  `max_response_bytes` and `max_event_bytes` travel with the request so a client
  can abort an oversized body or event while it is still reading. The binding
  repeats both checks on the complete value it receives.
  """

  alias Wotex.Binding.HTTP.{Error, Headers}
  alias Wotex.Runtime.Context

  @type t :: %__MODULE__{
          method: String.t(),
          uri: String.t(),
          headers: Headers.t(),
          body: binary() | nil,
          request_id: String.t(),
          deadline: Context.deadline(),
          operation: atom(),
          media_type: String.t(),
          stream?: boolean(),
          max_response_bytes: pos_integer(),
          max_event_bytes: pos_integer()
        }

  @enforce_keys [
    :method,
    :uri,
    :headers,
    :body,
    :request_id,
    :deadline,
    :operation,
    :media_type,
    :stream?,
    :max_response_bytes,
    :max_event_bytes
  ]
  defstruct @enforce_keys

  @doc "Builds a validated HTTP request value."
  @spec new(String.t(), String.t(), Headers.t(), binary() | nil, keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def new(method, uri, headers, body, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      build(method, uri, headers, body, opts)
    else
      invalid_request()
    end
  end

  def new(_, _, _, _, _), do: invalid_request()

  defp build(method, uri, headers, body, opts) do
    request_id = Keyword.get(opts, :request_id)
    operation = Keyword.get(opts, :operation)
    media_type = Keyword.get(opts, :media_type, "application/json")
    stream? = Keyword.get(opts, :stream?, false)
    deadline = Keyword.get(opts, :deadline)
    max_response_bytes = Keyword.get(opts, :max_response_bytes)
    max_event_bytes = Keyword.get(opts, :max_event_bytes)

    with :ok <- validate_method(method),
         :ok <- validate_uri(uri),
         {:ok, normalized_headers} <- Headers.new(headers, :request),
         :ok <- validate_body(body),
         :ok <- validate_identity(request_id, operation),
         :ok <- validate_deadline(deadline),
         :ok <- validate_media_type(media_type),
         :ok <- validate_limit(max_response_bytes, :max_response_bytes),
         :ok <- validate_limit(max_event_bytes, :max_event_bytes),
         true <- is_boolean(stream?) do
      {:ok,
       %__MODULE__{
         method: method,
         uri: uri,
         headers: normalized_headers,
         body: body,
         request_id: request_id,
         deadline: deadline,
         operation: operation,
         media_type: media_type,
         stream?: stream?,
         max_response_bytes: max_response_bytes,
         max_event_bytes: max_event_bytes
       }}
    else
      false -> {:error, Error.new(:invalid_stream_flag, :request, "stream flag must be boolean")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp invalid_request do
    {:error, Error.new(:invalid_request, :request, "HTTP request options are invalid")}
  end

  @doc "Returns the case-sensitive HTTP method token."
  @spec method(t()) :: String.t()
  def method(%__MODULE__{method: method}), do: method

  @doc "Returns the absolute HTTP or HTTPS target URI."
  @spec uri(t()) :: String.t()
  def uri(%__MODULE__{uri: uri}), do: uri

  @doc "Returns validated, lowercase HTTP fields."
  @spec headers(t()) :: Headers.t()
  def headers(%__MODULE__{headers: headers}), do: headers

  @doc "Returns the encoded body, or `nil` when no body is present."
  @spec body(t()) :: binary() | nil
  def body(%__MODULE__{body: body}), do: body

  @doc "Returns the caller-supplied request identity."
  @spec request_id(t()) :: String.t()
  def request_id(%__MODULE__{request_id: request_id}), do: request_id

  @doc "Returns the caller-supplied absolute deadline."
  @spec deadline(t()) :: Context.deadline()
  def deadline(%__MODULE__{deadline: deadline}), do: deadline

  @doc "Returns the exact W3C WoT operation."
  @spec operation(t()) :: atom()
  def operation(%__MODULE__{operation: operation}), do: operation

  @doc "Returns the JSON representation media type selected from the Form."
  @spec media_type(t()) :: String.t()
  def media_type(%__MODULE__{media_type: media_type}), do: media_type

  @doc "Returns whether this request opens a Server-Sent Events stream."
  @spec stream?(t()) :: boolean()
  def stream?(%__MODULE__{stream?: stream?}), do: stream?

  @doc "Returns the maximum complete response body the client may read."
  @spec max_response_bytes(t()) :: pos_integer()
  def max_response_bytes(%__MODULE__{max_response_bytes: limit}), do: limit

  @doc "Returns the maximum data size of one Server-Sent Event the client may deliver."
  @spec max_event_bytes(t()) :: pos_integer()
  def max_event_bytes(%__MODULE__{max_event_bytes: limit}), do: limit

  defp validate_method(method) do
    if Headers.token?(method) do
      :ok
    else
      {:error, Error.new(:invalid_method, :request, "HTTP method must be a non-empty token")}
    end
  end

  defp validate_uri(uri) when is_binary(uri) do
    case URI.new(uri) do
      {:ok, parsed} ->
        validate_parsed_uri(uri, parsed)

      {:error, _} ->
        {:error, Error.new(:invalid_uri, :request, "HTTP target URI is invalid")}
    end
  end

  defp validate_uri(_),
    do: {:error, Error.new(:invalid_uri, :request, "HTTP target URI must be a string")}

  defp validate_parsed_uri(uri, parsed) do
    cond do
      not String.valid?(uri) or Regex.match?(~r/[\x00-\x20\x7F]/, uri) ->
        {:error, Error.new(:invalid_uri, :request, "HTTP target URI contains invalid bytes")}

      parsed.scheme not in ["http", "https"] ->
        {:error, Error.new(:unsupported_scheme, :request, "target URI must use HTTP or HTTPS")}

      not (is_binary(parsed.host) and parsed.host != "") ->
        {:error, Error.new(:invalid_uri, :request, "HTTP target URI must contain a host")}

      not is_nil(parsed.userinfo) ->
        {:error,
         Error.new(
           :uri_credentials_forbidden,
           :request,
           "credentials must not appear in the target URI"
         )}

      not is_nil(parsed.fragment) ->
        {:error,
         Error.new(
           :uri_fragment_forbidden,
           :request,
           "HTTP target URI cannot contain a fragment"
         )}

      true ->
        :ok
    end
  end

  defp validate_body(nil), do: :ok
  defp validate_body(body) when is_binary(body), do: :ok

  defp validate_body(_),
    do: {:error, Error.new(:invalid_body, :request, "HTTP request body must be binary or nil")}

  defp validate_identity(request_id, operation) when is_binary(request_id) do
    if byte_size(String.trim(request_id)) > 0 and operation in Wotex.Runtime.operations() do
      :ok
    else
      invalid_identity()
    end
  end

  defp validate_identity(_, _), do: invalid_identity()

  defp invalid_identity do
    {:error,
     Error.new(:invalid_request_identity, :request, "request identity or operation is invalid")}
  end

  defp validate_deadline(nil), do: :ok
  defp validate_deadline(deadline) when is_integer(deadline), do: :ok
  defp validate_deadline(%DateTime{}), do: :ok

  defp validate_deadline(_),
    do: {:error, Error.new(:invalid_deadline, :request, "deadline must be absolute or nil")}

  defp validate_media_type(media_type) when is_binary(media_type) and byte_size(media_type) > 0,
    do: :ok

  defp validate_media_type(_),
    do: {:error, Error.new(:invalid_media_type, :request, "media type must be non-empty")}

  defp validate_limit(value, _) when is_integer(value) and value > 0, do: :ok

  defp validate_limit(_, name) do
    {:error,
     Error.new(:invalid_byte_limit, :request, "request byte limits must be positive integers", %{
       option: name
     })}
  end
end
