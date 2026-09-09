defmodule Wotex.BACnet.Client do
  @moduledoc "Explicit client port; the consumer owns its implementation, supervision and trust policy."

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}
  @doc "Establishes a finite typed subscription within the supplied timeout."
  @callback subscribe(term(), Wotex.BACnet.COVRequest.t(), pid(), pos_integer()) ::
              {:ok, Wotex.BACnet.Subscription.t()} | {:error, term()}

  @doc "Cancels the original subscription and releases its owned listener and timers."
  @callback unsubscribe(term(), Wotex.BACnet.Subscription.t(), pos_integer()) ::
              :ok | {:error, term()}

  @optional_callbacks subscribe: 4, unsubscribe: 3
end
