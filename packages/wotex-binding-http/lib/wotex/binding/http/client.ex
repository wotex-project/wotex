defmodule Wotex.Binding.HTTP.Client do
  @moduledoc """
  Port implemented by a consumer-supplied HTTP client.

  The second argument to `request/3` and `subscribe/4` is the ephemeral
  credential resolved by Wotex Runtime. It is deliberately separate from the
  immutable request and must not be retained, logged, returned, or included in
  an event handler. Client configuration must not contain credentials.

  A streaming implementation parses Server-Sent Events framing and invokes the
  supplied handler with `Wotex.Binding.HTTP.SSE.Event` values. The binding
  decodes each event's JSON data. Connection ownership, redirects, TLS policy,
  pooling policy, deadlines, backpressure, and reconnection remain explicit
  responsibilities of the client and consumer host.
  """

  alias Wotex.Binding.HTTP.{Request, Response}
  alias Wotex.Binding.HTTP.SSE.Event

  @type config :: term()
  @type credential :: term()
  @type handle :: term()
  @type event_handler :: (Event.t() -> :ok)

  @callback request(Request.t(), credential(), config()) ::
              {:ok, Response.t()} | {:error, term()}

  @callback subscribe(Request.t(), credential(), event_handler(), config()) ::
              {:ok, handle(), Response.t()} | {:error, term()}

  @callback close(handle(), config()) :: :ok | {:error, term()}
end
