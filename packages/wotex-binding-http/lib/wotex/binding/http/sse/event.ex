defmodule Wotex.Binding.HTTP.SSE.Event do
  @moduledoc """
  Immutable Server-Sent Event after client-owned stream framing.

  The client joins repeated `data` lines and validates SSE framing before
  constructing this value. The binding then validates field values and decodes
  the complete data payload as JSON.

  `new/2` retains the joined data together with optional event type,
  last-event identifier, and non-negative reconnection delay. Event and
  identifier values must be valid text without null, carriage-return, or
  line-feed bytes. Accessors expose each field without granting the binding
  ownership of stream parsing or reconnect policy.

  The value represents one event after dispatch framing, not an HTTP response
  chunk. `Wotex.Binding.HTTP.Transport` decodes its JSON data;
  `Wotex.Binding.HTTP.Notification` builds Runtime delivery metadata.
  The client remains responsible for
  byte framing, line joining, connection lifetime, backpressure, and deciding
  whether to act on the optional retry field.
  """

  alias Wotex.Binding.HTTP.Error

  @type t :: %__MODULE__{
          data: binary(),
          event: String.t() | nil,
          id: String.t() | nil,
          retry: non_neg_integer() | nil
        }

  @enforce_keys [:data]
  defstruct [:data, :event, :id, :retry]

  @doc "Builds a dispatched Server-Sent Event value."
  @spec new(binary(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(data, opts \\ [])

  def new(data, opts) when is_binary(data) and is_list(opts) do
    if Keyword.keyword?(opts), do: build(data, opts), else: invalid_event()
  end

  def new(_, _), do: invalid_event()

  defp build(data, opts) do
    event = Keyword.get(opts, :event)
    id = Keyword.get(opts, :id)
    retry = Keyword.get(opts, :retry)

    with :ok <- validate_line_value(event, :event),
         :ok <- validate_line_value(id, :id),
         :ok <- validate_retry(retry) do
      {:ok, %__MODULE__{data: data, event: event, id: id, retry: retry}}
    end
  end

  defp invalid_event do
    {:error,
     Error.new(:invalid_sse_event, :subscription, "SSE event input is invalid", %{}, :protocol)}
  end

  @doc "Returns the event data after SSE line joining and before JSON decoding."
  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data

  @doc "Returns the optional SSE event type."
  @spec event(t()) :: String.t() | nil
  def event(%__MODULE__{event: event}), do: event

  @doc "Returns the optional SSE last-event identifier."
  @spec id(t()) :: String.t() | nil
  def id(%__MODULE__{id: id}), do: id

  @doc "Returns the optional SSE reconnection delay in milliseconds."
  @spec retry(t()) :: non_neg_integer() | nil
  def retry(%__MODULE__{retry: retry}), do: retry

  defp validate_line_value(nil, _), do: :ok

  defp validate_line_value(value, field) when is_binary(value) do
    if String.valid?(value) and not Regex.match?(~r/[\x00\x0A\x0D]/, value) do
      :ok
    else
      {:error,
       Error.new(
         :invalid_sse_field,
         :subscription,
         "SSE field contains invalid bytes",
         %{field: field},
         :protocol
       )}
    end
  end

  defp validate_line_value(_, field) do
    {:error,
     Error.new(
       :invalid_sse_field,
       :subscription,
       "SSE field must be a string or nil",
       %{field: field},
       :protocol
     )}
  end

  defp validate_retry(nil), do: :ok
  defp validate_retry(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_retry(_),
    do:
      {:error,
       Error.new(
         :invalid_sse_retry,
         :subscription,
         "SSE retry must be non-negative",
         %{},
         :protocol
       )}
end
