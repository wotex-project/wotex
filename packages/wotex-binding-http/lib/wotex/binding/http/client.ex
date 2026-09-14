defmodule Wotex.Binding.HTTP.Client do
  @moduledoc """
  Defines the complete network boundary implemented by a consumer-supplied HTTP client.

  The second argument to `request/3` and `subscribe/4` is the ephemeral
  credential resolved by Wotex Runtime. It is deliberately separate from the
  immutable request and must not be retained, logged, returned, or captured by
  a connection process. Client configuration must not contain credentials.

  A streaming implementation parses Server-Sent Events framing and sends raw
  `Wotex.Binding.HTTP.SSE.Event` frames to the Runtime subscription process it
  receives as `owner`. Decoding happens in that owner process through
  `Wotex.Binding.HTTP.Transport.decode_frame/3`, so the client's connection
  process never runs the JSON codec. Connection ownership, destination and
  credential-audience authorization, redirects, TLS policy, pooling policy,
  deadlines, backpressure, and reconnection remain explicit responsibilities
  of the client and consumer host.

  Before I/O, the client and host authorize the exact `Request.uri/1`, every
  DNS/IP result, and the proxy route. They repeat that admission for each
  redirect and apply the callback credential only while the admitted target is
  inside its audience. A syntactically valid initial or redirected URI is not
  authorization. The request carries field and URI ceilings for incremental
  response and redirect admission, but the binding cannot observe or enforce
  how arbitrary client code uses them.

  ## Messages the client sends to the owner

  | Message | Meaning |
  | --- | --- |
  | `{:wotex_transport_frame, %Wotex.Binding.HTTP.SSE.Event{}}` | One dispatched Server-Sent Event |
  | `{:wotex_transport_status, :reconnected}` | The stream reopened and the subscription is intact |
  | `{:wotex_transport_status, :session_lost}` | The server-side subscription is gone |
  | `{:wotex_transport_status, :transport_down}` | The client can no longer serve this subscription |

  A client may `Process.monitor/1` or link the owner to release its connection
  when the subscription process stops. Runtime stops the subscription with a
  `:shutdown` reason after `:session_lost` and `:transport_down`, leaving the
  restart decision to the consumer's supervisor.

  Owner monitoring is also a supplied-client establishment obligation. Install
  it before an in-progress connection can outlive `owner`, and abort or close
  that connection if the owner exits before `subscribe/4` returns. While the
  callback is pending, this package has neither the connection nor its handle
  and cannot provide that cleanup or claim it as package behavior.

  Implementations should translate transport-library failures into their own
  reason terms. The binding normalizes those reasons before returning a public
  error, so neither credentials nor client-specific failure values escape the
  callback boundary. The single reason atom the binding interprets is
  `:timeout`, which classifies the failure as a retryable deadline expiry.
  """

  alias Wotex.Binding.HTTP.{Request, Response}

  @typedoc "Non-credential client options supplied by the consumer host."
  @type config :: term()

  @typedoc "Credential material valid only for the duration of one callback invocation."
  @type credential :: term()

  @typedoc "Opaque identity of exactly one client-owned SSE connection."
  @type handle :: term()

  @typedoc "Runtime subscription process that receives frames and status messages."
  @type owner :: pid()

  @doc """
  Executes one finite HTTP request.

  `request` contains the method, absolute target, validated fields, encoded
  body, deadline, admission limits, and interaction identity. `credential` is
  intentionally not part of that value and may be used only while performing
  this call. `config` is the non-secret value supplied when the binding was
  configured.

  Read the matching clock, derive the remaining budget with
  `Wotex.Runtime.Context.remaining_ms/2`, and cancel transport work when that
  budget expires. Return a validated `Wotex.Binding.HTTP.Response` containing
  the complete body, or an implementation-specific error reason. Report
  deadline expiry as `{:error, :timeout}`. Do not return or retain the credential
  in either branch.
  """
  @callback request(Request.t(), credential(), config()) ::
              {:ok, Response.t()} | {:error, term()}

  @doc """
  Opens one Server-Sent Events response and transfers its lifecycle to the caller.

  The client validates the HTTP exchange at its own transport layer, parses SSE
  framing, and sends `{:wotex_transport_frame, event}` to `owner` for each
  dispatched `Wotex.Binding.HTTP.SSE.Event`. On success it returns both an
  opaque connection `handle` and the handshake response. The handle must
  identify only this connection so a later `close/2` cannot affect another
  subscription.

  The credential has the same ephemeral rules as `request/3` and must never be
  captured by a connection process or stored with the returned handle.
  Monitoring `owner` before a pending connection can outlive it, including
  cleanup if `owner` exits before this callback returns, remains the client
  implementation's responsibility.
  """
  @callback subscribe(Request.t(), credential(), owner(), config()) ::
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
