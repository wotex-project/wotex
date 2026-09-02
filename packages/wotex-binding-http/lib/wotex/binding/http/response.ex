defmodule Wotex.Binding.HTTP.Response do
  @moduledoc "Immutable, credential-free HTTP response returned by the supplied client."

  alias Wotex.Binding.HTTP.{Error, Headers}

  @opaque t :: %__MODULE__{status: 100..599, headers: Headers.t(), body: binary()}
  @enforce_keys [:status, :headers, :body]
  defstruct @enforce_keys

  @doc "Builds a validated HTTP response value."
  @spec new(integer(), Headers.t(), binary()) :: {:ok, t()} | {:error, Error.t()}
  def new(status, headers, body) when status in 100..599 and is_binary(body) do
    with {:ok, normalized_headers} <- Headers.new(headers, :response) do
      {:ok, %__MODULE__{status: status, headers: normalized_headers, body: body}}
    end
  end

  def new(_status, _headers, _body) do
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
