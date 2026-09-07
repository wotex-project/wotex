defmodule Wotex.Runtime.Result do
  @moduledoc """
  The immutable outcome of a protocol exchange.

  A result binds payload, status, and non-secret metadata to the original
  request id and W3C WoT operation. The runtime rejects a transport result whose
  identity or operation does not match the request, preventing accidental
  cross-request attribution.

  `status` is binding-neutral: `:ok` means the protocol exchange completed with
  a representation or acknowledgement, and `:accepted` means the protocol
  accepted the request while the outcome is still pending (for example an
  HTTP 202 or a broker acknowledging a publish). Protocol-specific detail such
  as an HTTP status code or MQTT QoS belongs in `metadata`.

  Success describes the protocol exchange only. It does not assert accepted
  Property truth, committed consumer state, or a physical Action effect.
  """

  alias Wotex.Runtime.Error

  @operations Wotex.Runtime.operations()

  @type status :: :ok | :accepted
  @type t :: %__MODULE__{
          request_id: String.t(),
          operation: atom(),
          status: status(),
          payload: term(),
          metadata: map()
        }

  @statuses [:ok, :accepted]

  @enforce_keys [:request_id, :operation, :status, :payload]
  defstruct [:request_id, :operation, :status, :payload, metadata: %{}]

  @doc "Builds a typed protocol result."
  @spec new(String.t(), atom(), term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(request_id, operation, payload, opts \\ [])

  def new(request_id, operation, payload, opts)
      when is_binary(request_id) and byte_size(request_id) > 0 and operation in @operations and
             is_list(opts) do
    metadata = Keyword.get(opts, :metadata, %{})
    status = Keyword.get(opts, :status, :ok)

    cond do
      not is_map(metadata) ->
        {:error, Error.new(:invalid_result_metadata, :transport, "result metadata must be a map")}

      status not in @statuses ->
        {:error,
         Error.new(:invalid_result_status, :transport, "result status must be :ok or :accepted")}

      true ->
        {:ok,
         %__MODULE__{
           request_id: request_id,
           operation: operation,
           status: status,
           payload: payload,
           metadata: metadata
         }}
    end
  end

  def new(_request_id, _operation, _payload, _opts) do
    {:error,
     Error.new(:invalid_result, :transport, "protocol result identity or operation is invalid")}
  end
end
