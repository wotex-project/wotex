defmodule Wotex.OPCUA.Client do
  @moduledoc """
  Defines the client port for one explicitly configured OPC UA session.

  A client validates endpoint and security options in `c:connect/1`, performs
  one bounded service request in `c:request/3`, and releases its handle in
  `c:disconnect/1`. The handle returned by `c:connect/1` is opaque to the facade
  and is stored in `Wotex.OPCUA.Session` with the implementation and timeout.

  ## Consumer responsibility

  The consumer chooses the implementation and owns credentials, certificate
  provisioning, trust policy, endpoint authorization, session supervision, and
  data-model compatibility. Client failures are normalized as
  `Wotex.OPCUA.Error`; raw exceptions, certificate secrets, and unbounded server
  output must not enter public values. Implementations must not silently
  reconnect or retry a write or call whose remote effect may be unknown.
  """

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}

  @doc """
  Establishes one monitored data-change subscription for a validated request.

  Arguments are the client handle, the validated request, the receiver and the
  finite timeout. A client without subscriptions omits this optional callback.
  """
  @callback subscribe(term(), map(), pid(), pos_integer()) ::
              {:ok, Wotex.OPCUA.Subscription.t()} | {:error, term()}

  @doc "Cancels one subscription; a recorded closed handle returns `:ok`."
  @callback unsubscribe(term(), Wotex.OPCUA.Subscription.t(), pos_integer()) ::
              :ok | {:error, term()}

  @optional_callbacks subscribe: 4, unsubscribe: 3
end
