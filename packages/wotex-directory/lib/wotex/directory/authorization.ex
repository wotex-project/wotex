defmodule Wotex.Directory.Authorization do
  @moduledoc """
  Consumer authorization port.

  Implementations decide policy and return `:ok`, `:deny`, or an adapter
  failure. The directory invokes this port before repository access.

  The callback receives the consumer state, the request principal, the
  directory operation, the affected collection or entry, and the opaque
  authorization context. Returning `:deny` represents an expected policy
  decision; returning `{:error, reason}` represents a failure in the policy
  adapter or its dependency. The service translates both outcomes into typed
  directory errors without disclosing repository state.

  Implementations should be deterministic for a given request context and
  should not perform repository mutations. Authorization precedes reads as
  well as writes, including anonymous registration and expiry processing.
  """

  @type operation :: :register | :get | :replace | :patch | :delete | :list | :expire
  @type target :: :collection | {:entry, String.t()}

  @doc "Authorizes one directory operation before any repository access occurs."
  @callback authorize(
              state :: term(),
              principal :: term(),
              operation(),
              target(),
              context :: term()
            ) :: :ok | :deny | {:error, term()}
end
