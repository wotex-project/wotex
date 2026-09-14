defmodule Wotex.Matter.Client do
  @moduledoc """
  Defines the client port for one explicitly configured Matter session.

  A client validates controller options in `c:connect/1`, performs one bounded
  interaction in `c:request/3`, and releases its handle in `c:disconnect/1`.
  The opaque handle returned by `c:connect/1` is stored in
  `Wotex.Matter.Session` and is never interpreted by the package facade.

  ## Consumer responsibility

  The implementation owns integration with its selected Matter SDK or
  controller. The consumer owns commissioning policy, fabric credentials,
  trust configuration, secure-session lifetime, data-model compatibility, and
  process supervision. Client failures are normalized as `Wotex.Matter.Error`; raw SDK
  exceptions, credentials, and unbounded peer output must not enter public
  values. Writes and invokes must not be retried silently because their effect
  may be unknown.
  """

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}

  @doc "Establishes a validated subscription for the exact receiver."
  @callback subscribe(term(), map(), pid(), pos_integer()) ::
              {:ok, term()} | {:error, term()}

  @doc "Cancels a subscription owned by this client handle."
  @callback unsubscribe(term(), term(), pos_integer()) :: :ok | {:error, term()}

  @optional_callbacks subscribe: 4, unsubscribe: 3
end
