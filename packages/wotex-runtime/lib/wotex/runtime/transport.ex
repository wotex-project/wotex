defmodule Wotex.Runtime.Transport do
  @moduledoc """
  Port implemented by a protocol binding or consumer transport.

  `request/3` performs one exchange in the caller process. `subscribe/4`
  establishes a long-lived exchange for an explicitly supervised subscription
  process, the `owner` pid it receives. `unsubscribe/4` releases the returned
  handle.

  ## Messages a transport may send to the owner

  | Message | Meaning |
  | --- | --- |
  | `{:wotex_transport_frame, frame}` | A raw protocol frame; the owner calls `decode_frame/3` in its own process, keeping decoding off the connection's hot path |
  | `{:wotex_transport, {:ok, value, meta}}` | An already decoded value with binding metadata |
  | `{:wotex_transport, {:error, error}}` | A delivery-level failure the receiver should see |
  | `{:wotex_transport_status, status}` | `:reconnected` (session kept), `:session_lost` (server-side subscription gone), or `:transport_down` |

  On `:session_lost` and `:transport_down` the owner notifies its receiver and
  stops with a `:shutdown` reason so the consumer's supervisor policy decides
  whether to restart and resubscribe. A transport that links a connection
  process to the owner gets the same result through the exit signal.

  Long-lived connection ownership, protocol retries, pooling, and provider
  behavior remain with the implementation. Every callback receives consumer
  configuration explicitly; no binding is discovered from application
  environment or a global registry.
  """

  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @typedoc "Metadata delivered with a value: topic, QoS, event id, or similar non-secret detail."
  @type delivery_meta :: map()

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

  @doc """
  Decodes one raw frame delivered as `{:wotex_transport_frame, frame}`.

  Runs in the subscription process. Return `:ignore` for frames that carry no
  value for this subscription (keep-alives, unrelated topics).
  """
  @callback decode_frame(term(), Request.t(), config()) ::
              {:ok, term(), delivery_meta()} | {:error, term()} | :ignore

  @optional_callbacks decode_frame: 3
end
