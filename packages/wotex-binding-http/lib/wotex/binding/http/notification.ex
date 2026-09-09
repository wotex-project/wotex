defmodule Wotex.Binding.HTTP.Notification do
  @moduledoc """
  Credential-free delivery metadata for one decoded Server-Sent Event.

  Wotex Runtime delivers `{:wotex_runtime, id, {:ok, data, meta}}` to the
  consumer receiver. This module builds the `meta` map: it preserves the SSE
  event type, identifier, and retry hint together with the originating WoT
  interaction identity, while the decoded JSON value travels as `data`.

  The map contains no credential, connection, or client value.

  `new/3` is called after Server-Sent Events framing and payload decoding. It
  accepts only Property observation and Event subscription operations, keeping
  transport bookkeeping separate from the application value delivered by
  `Wotex.Runtime`.
  """

  alias Wotex.Binding.HTTP.SSE.Event

  @typedoc "Stream-opening W3C WoT operation."
  @type operation :: :observeproperty | :subscribeevent

  @type t :: %{
          event: String.t() | nil,
          id: String.t() | nil,
          retry: non_neg_integer() | nil,
          request_id: String.t(),
          operation: operation()
        }

  @doc "Builds the delivery metadata for one dispatched Server-Sent Event."
  @spec new(Event.t(), String.t(), operation()) :: t()
  def new(%Event{} = event, request_id, operation)
      when is_binary(request_id) and operation in [:observeproperty, :subscribeevent] do
    %{
      event: Event.event(event),
      id: Event.id(event),
      retry: Event.retry(event),
      request_id: request_id,
      operation: operation
    }
  end
end
