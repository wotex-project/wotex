defmodule Wotex.Binding.HTTP.Subscription do
  @moduledoc """
  Opaque, credential-free handle for one explicitly opened SSE connection.

  The value binds the supplied client's opaque handle to the originating
  request and stream operation. Only the matching close operation and client
  configuration instance can consume it. The handle retains only a non-secret
  instance reference, never the client configuration or opening credentials.
  """

  alias Wotex.Binding.HTTP.Config

  @derive {Inspect, only: [:client_module, :request_id, :operation]}
  @type t :: %__MODULE__{
          client_module: module(),
          client_handle: term(),
          instance_ref: reference(),
          request_id: String.t(),
          operation: :observeproperty | :subscribeevent
        }

  @enforce_keys [:client_module, :client_handle, :instance_ref, :request_id, :operation]
  defstruct @enforce_keys

  @doc false
  @spec new(Config.t(), term(), String.t(), :observeproperty | :subscribeevent) :: t()
  def new(%Config{} = config, client_handle, request_id, operation)
      when is_binary(request_id) and
             operation in [:observeproperty, :subscribeevent] do
    {client_module, _} = Config.client(config)

    %__MODULE__{
      client_module: client_module,
      client_handle: client_handle,
      instance_ref: Config.instance_ref(config),
      request_id: request_id,
      operation: operation
    }
  end

  @doc false
  @spec unwrap(t()) :: {module(), term(), String.t(), :observeproperty | :subscribeevent}
  def unwrap(%__MODULE__{} = subscription) do
    {
      subscription.client_module,
      subscription.client_handle,
      subscription.request_id,
      subscription.operation
    }
  end
end
