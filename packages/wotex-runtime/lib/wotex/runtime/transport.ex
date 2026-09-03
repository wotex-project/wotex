defmodule Wotex.Runtime.Transport do
  @moduledoc """
  Port implemented by a protocol binding or consumer transport.

  `request/3` performs one exchange in the caller process. `subscribe/4`
  establishes a long-lived exchange for an explicitly supervised subscription
  and sends `{:wotex_transport, payload}` to the supplied receiver.
  `unsubscribe/4` releases the returned handle.

  Long-lived connection ownership, protocol retries, pooling, telemetry, and
  provider behavior remain with the implementation. Every callback receives
  consumer configuration explicitly; no binding is discovered from application
  environment or a global registry.
  """

  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @typedoc "Consumer-owned configuration passed unchanged to every callback."
  @type config :: term()

  @typedoc "Opaque subscription handle returned by the transport implementation."
  @type handle :: term()

  @doc "Executes one credentialed protocol request."
  @callback request(Request.t(), ExecutionContext.t(), config()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc "Starts a protocol subscription and directs values to `receiver`."
  @callback subscribe(Request.t(), pid(), ExecutionContext.t(), config()) ::
              {:ok, handle()} | {:error, term()}

  @doc "Stops the protocol subscription represented by `handle`."
  @callback unsubscribe(handle(), Request.t(), ExecutionContext.t(), config()) ::
              :ok | {:error, term()}
end
