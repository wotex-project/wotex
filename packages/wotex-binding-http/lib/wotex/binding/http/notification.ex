defmodule Wotex.Binding.HTTP.Notification do
  @moduledoc """
  Immutable Runtime notification decoded from one dispatched Server-Sent Event.

  It preserves the SSE event type, identifier, retry hint, and originating WoT
  interaction identity while exposing the event data as a decoded JSON value.
  """

  alias Wotex.Binding.HTTP.SSE.Event

  @type t :: %__MODULE__{
          data: term(),
          event: String.t() | nil,
          id: String.t() | nil,
          retry: non_neg_integer() | nil,
          request_id: String.t(),
          operation: :observeproperty | :subscribeevent
        }

  @enforce_keys [:data, :event, :id, :retry, :request_id, :operation]
  defstruct @enforce_keys

  @doc false
  @spec new(Event.t(), term(), String.t(), :observeproperty | :subscribeevent) :: t()
  def new(%Event{} = event, data, request_id, operation)
      when is_binary(request_id) and operation in [:observeproperty, :subscribeevent] do
    %__MODULE__{
      data: data,
      event: Event.event(event),
      id: Event.id(event),
      retry: Event.retry(event),
      request_id: request_id,
      operation: operation
    }
  end

  @doc "Returns the decoded JSON value."
  @spec data(t()) :: term()
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

  @doc "Returns the caller-supplied request identity."
  @spec request_id(t()) :: String.t()
  def request_id(%__MODULE__{request_id: request_id}), do: request_id

  @doc "Returns the stream-opening WoT operation."
  @spec operation(t()) :: :observeproperty | :subscribeevent
  def operation(%__MODULE__{operation: operation}), do: operation
end
