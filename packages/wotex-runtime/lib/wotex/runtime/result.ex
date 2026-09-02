defmodule Wotex.Runtime.Result do
  @moduledoc """
  Immutable outcome of a protocol exchange.

  Success does not assert accepted Property truth or a physical Action effect.
  """

  alias Wotex.Runtime.Error

  @operations ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a

  @opaque t :: %__MODULE__{
            request_id: String.t(),
            operation: atom(),
            status: term(),
            payload: term(),
            metadata: map()
          }

  @enforce_keys [:request_id, :operation, :status, :payload]
  defstruct [:request_id, :operation, :status, :payload, metadata: %{}]

  @doc "Builds a typed protocol result."
  @spec new(String.t(), atom(), term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(request_id, operation, payload, opts \\ [])

  def new(request_id, operation, payload, opts)
      when is_binary(request_id) and byte_size(request_id) > 0 and operation in @operations and
             is_list(opts) do
    metadata = Keyword.get(opts, :metadata, %{})

    if is_map(metadata) do
      {:ok,
       %__MODULE__{
         request_id: request_id,
         operation: operation,
         status: Keyword.get(opts, :status, :ok),
         payload: payload,
         metadata: metadata
       }}
    else
      {:error, Error.new(:invalid_result_metadata, :transport, "result metadata must be a map")}
    end
  end

  def new(_request_id, _operation, _payload, _opts) do
    {:error,
     Error.new(:invalid_result, :transport, "protocol result identity or operation is invalid")}
  end
end
