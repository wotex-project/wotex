defmodule Wotex.Binding.HTTP.Response do
  @moduledoc """
  Immutable, credential-free HTTP response returned by the supplied client.

  The client provides a complete binary body and raw HTTP fields. Construction
  revalidates status and fields before Runtime response decoding begins.

  `new/3` accepts status codes from 100 through 599, validates the response
  fields with `Wotex.Binding.HTTP.Headers`, and retains the body without
  interpreting its media type. The transport then applies the configured
  header count and aggregate-byte limits before mapping a result. Accessors
  expose the three components to the binding's response mapper. The value
  contains no request credential, client handle, connection state, or redirect
  history.

  The supplied client owns framing, decompression, redirect policy, and body
  collection. It must apply its own transport limits before construction; the
  binding applies the configured representation limit before decoding. A valid
  `t:t/0` proves only that the response has the required local shape. Status and
  content semantics are evaluated by the operation that consumes it.
  """

  alias Wotex.Binding.HTTP.{Error, Headers}

  @type t :: %__MODULE__{status: 100..599, headers: Headers.t(), body: binary()}
  @enforce_keys [:status, :headers, :body]
  defstruct @enforce_keys

  @doc "Builds a validated HTTP response value."
  @spec new(integer(), Headers.t(), binary()) :: {:ok, t()} | {:error, Error.t()}
  def new(status, headers, body) when status in 100..599 and is_binary(body) do
    with {:ok, normalized_headers} <- Headers.new(headers, :response) do
      {:ok, %__MODULE__{status: status, headers: normalized_headers, body: body}}
    end
  end

  def new(_, _, _) do
    {:error,
     Error.new(
       :invalid_response,
       :response,
       "HTTP response requires a status, field list, and binary body"
     )}
  end

  @doc "Returns the HTTP status code."
  @spec status(t()) :: 100..599
  def status(%__MODULE__{status: status}), do: status

  @doc "Returns validated, lowercase HTTP fields."
  @spec headers(t()) :: Headers.t()
  def headers(%__MODULE__{headers: headers}), do: headers

  @doc "Returns the complete response body."
  @spec body(t()) :: binary()
  def body(%__MODULE__{body: body}), do: body
end
