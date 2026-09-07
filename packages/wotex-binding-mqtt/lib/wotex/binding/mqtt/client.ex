defmodule Wotex.Binding.MQTT.Client do
  @moduledoc """
  Consumer-supplied MQTT client port.

  The implementation owns connection lifecycle and MQTT session state. Its
  configuration and returned handles must be credential-free. Credentials are
  available only through the execution context during an immediate callback and
  must not be retained.

  ## Subscription owner and messages

  `subscribe/4` receives the subscription owner: the caller-supervised
  `Wotex.Runtime.Subscription` process that requested the subscription. The
  client sends raw MQTT deliveries to that pid and decodes nothing on its own
  connection process; `Wotex.Binding.MQTT.Transport` decodes each frame in the
  owner instead.

  | Message to the owner | Meaning |
  | --- | --- |
  | `{:wotex_transport_frame, delivery}` | One received `Wotex.Binding.MQTT.Delivery` for a Topic Filter of the subscribe command |
  | `{:wotex_transport_status, :reconnected}` | The connection was re-established and the MQTT Session, including this subscription, was resumed |
  | `{:wotex_transport_status, :session_lost}` | The broker holds no subscription for this owner any more |
  | `{:wotex_transport_status, :transport_down}` | The connection is gone and the client will not restore it |

  A client MUST send `:session_lost` when it reconnects with `clean_start: true`
  (MQTT 5 Clean Start, or MQTT 3.1.1 clean session) or after the Session Expiry
  Interval elapsed, because the broker then no longer holds the subscription. It
  MUST send `:reconnected` only when the Session was resumed and the existing
  subscription survived. The owner reports both statuses to its receiver and
  stops on `:session_lost` and `:transport_down`, leaving the restart and
  resubscription decision to the consumer's supervisor. A client that links its
  connection process to the owner produces `:transport_down` through the exit
  signal instead.

  The owner enforces `Wotex.Binding.MQTT.Command.max_payload_bytes/1` when it
  decodes a frame. A client that can measure the encoded Application Message
  earlier should drop an oversized delivery instead of sending the frame.
  """

  alias Wotex.Binding.MQTT.{Command, Delivery}
  alias Wotex.Runtime.ExecutionContext

  @typedoc "Consumer-owned client configuration passed unchanged to every callback."
  @type config :: term()

  @typedoc "Opaque, credential-free subscription handle owned by the client."
  @type handle :: term()

  @typedoc "The caller-supervised subscription process that receives raw deliveries."
  @type owner :: pid()

  @doc "Publishes the command's encoded JSON Application Message."
  @callback publish(Command.t(), ExecutionContext.t(), config()) :: :ok | {:error, term()}

  @doc "Performs a finite read and returns one MQTT delivery."
  @callback read(Command.t(), pos_integer(), ExecutionContext.t(), config()) ::
              {:ok, Delivery.t()} | {:error, term()}

  @doc "Subscribes and sends every delivery and status to the subscription owner."
  @callback subscribe(Command.t(), owner(), ExecutionContext.t(), config()) ::
              {:ok, handle()} | {:error, term()}

  @doc "Unsubscribes a caller-owned client handle."
  @callback unsubscribe(handle(), Command.t(), ExecutionContext.t(), config()) ::
              :ok | {:error, term()}
end
