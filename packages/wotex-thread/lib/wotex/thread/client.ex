defmodule Wotex.Thread.Client do
  @moduledoc """
  Defines the client port for one explicitly configured Thread management session.

  A client validates its options in `c:connect/1`, performs one bounded request
  in `c:request/3`, and releases its handle in `c:disconnect/1`. The opaque
  handle returned by `c:connect/1` is stored in `Wotex.Thread.Session` and is
  validated according to the selected first-party adapter at public boundaries.

  ## Consumer responsibility

  The consumer chooses the implementation and owns daemon startup, radio and
  interface selection, credentials, trust policy, authorization, and
  supervision. Client failures are normalized as `Wotex.Thread.Error`; raw
  daemon responses, key material, socket state, and unbounded output must not
  enter public errors. The daemon request profile remains read-only; the native
  SDK profile admits separately validated management commands. Neither profile
  silently retries mutations.
  """

  @doc "Opens a client handle using explicit configuration. No simulator fallback is allowed."
  @callback connect(keyword()) :: {:ok, term()} | {:error, term()}

  @doc "Executes a validated operation within a finite timeout, preserving protocol errors."
  @callback request(term(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}

  @doc "Releases only resources owned by this handle; must be idempotent."
  @callback disconnect(term()) :: :ok | {:error, term()}
end
