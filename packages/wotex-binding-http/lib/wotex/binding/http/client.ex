defmodule Wotex.Binding.HTTP.Client do
  @moduledoc """
  Defines the complete network boundary implemented by a consumer-supplied HTTP client.

  The second argument to `request/3` and `subscribe/4` is the ephemeral
  credential resolved by Wotex Runtime. It is deliberately separate from the
  immutable request and must not be retained, logged, returned, or included in
  an event handler. Client configuration must not contain credentials.

  A streaming implementation parses Server-Sent Events framing and invokes the
  supplied handler with `Wotex.Binding.HTTP.SSE.Event` values. The binding
  decodes each event's JSON data. Connection ownership, redirects, TLS policy,
  pooling policy, deadlines, backpressure, and reconnection remain explicit
  responsibilities of the client and consumer host.

  Implementations should translate transport-library failures into their own
  reason terms. The binding normalizes those reasons before returning a public
  error, so neither credentials nor client-specific failure values escape the
  callback boundary.
  """

  alias Wotex.Binding.HTTP.{Request, Response}
  alias Wotex.Binding.HTTP.SSE.Event

  @typedoc "Non-credential client options supplied by the consumer host."
  @type config :: term()

  @typedoc "Credential material valid only for the duration of one callback invocation."
  @type credential :: term()

  @typedoc "Opaque identity of exactly one client-owned SSE connection."
  @type handle :: term()

  @typedoc "Callback invoked once for each complete, client-framed SSE event."
  @type event_handler :: (Event.t() -> :ok)

  @doc """
  Executes one finite HTTP request.

  `request` contains the method, absolute target, validated fields, encoded
  body, deadline, and interaction identity. `credential` is intentionally not
  part of that value and may be used only while performing this call. `config`
  is the non-secret value supplied when the binding was configured.

  Return a validated `Wotex.Binding.HTTP.Response` containing the complete body,
  or an implementation-specific error reason. Do not return or retain the
  credential in either branch.
  """
  @callback request(Request.t(), credential(), config()) ::
              {:ok, Response.t()} | {:error, term()}

  @doc """
  Opens one Server-Sent Events response and transfers its lifecycle to the caller.

  The client validates the HTTP exchange at its own transport layer, parses SSE
  framing, and calls `event_handler` with one `Wotex.Binding.HTTP.SSE.Event` per
  dispatched event. On success it returns both an opaque connection `handle`
  and the handshake response. The handle must identify only this connection so
  a later `close/2` cannot affect another subscription.

  The credential has the same ephemeral rules as `request/3` and must never be
  captured by the event handler or stored with the returned handle.
  """
  @callback subscribe(Request.t(), credential(), event_handler(), config()) ::
              {:ok, handle(), Response.t()} | {:error, term()}

  @doc """
  Closes exactly the SSE connection represented by `handle`.

  Closing is an explicit local lifecycle operation; implementations must not
  turn it into an undeclared HTTP interaction. Return `:ok` after the connection
  is closed, or an implementation-specific reason that the binding can
  normalize.
  """
  @callback close(handle(), config()) :: :ok | {:error, term()}
end
