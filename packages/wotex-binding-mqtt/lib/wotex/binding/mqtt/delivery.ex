defmodule Wotex.Binding.MQTT.Delivery do
  @moduledoc """
  Represents one immutable, credential-free MQTT Application Message delivery.

  `new/2` combines an encoded payload with a validated Topic Name, Quality of
  Service (QoS) level, and retained-message flag. `normalize/1` admits only an
  existing `t:t/0` at the consumer client boundary, preventing arbitrary maps
  from being treated as broker deliveries. Accessors expose the payload and
  protocol metadata without exposing the opaque struct representation.

  Inspection omits the payload and includes only Topic Name, QoS, and retained
  status. This keeps application values out of routine logs while preserving
  the metadata required by `Wotex.Binding.MQTT.Transport`. The value contains no
  broker handle, connection state, execution context, or credentials. It records
  what the client reported; it does not prove broker persistence, freshness, or
  canonical Property state.
  """

  alias Wotex.Binding.MQTT.{Error, QoS, Topic}

  @derive {Inspect, only: [:topic, :qos, :retain]}
  @opaque t :: %__MODULE__{
            payload: binary(),
            topic: String.t(),
            qos: QoS.t(),
            retain: boolean()
          }

  @enforce_keys [:payload, :topic, :qos, :retain]
  defstruct [:payload, :topic, :qos, :retain]

  @doc "Builds a delivery from an encoded payload and MQTT delivery metadata."
  @spec new(binary(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(payload, opts) when is_binary(payload) and is_list(opts) do
    topic = Keyword.get(opts, :topic)
    retain = Keyword.get(opts, :retain, false)

    with :ok <- Topic.validate_name(topic),
         {:ok, qos} <- QoS.normalize(Keyword.get(opts, :qos, 0)),
         :ok <- validate_retain(retain) do
      {:ok, %__MODULE__{payload: payload, topic: topic, qos: qos, retain: retain}}
    end
  end

  def new(_, _) do
    {:error,
     Error.new(
       :invalid_delivery,
       :client,
       :protocol,
       "delivery requires a binary payload and keyword options"
     )}
  end

  @doc "Validates a delivery value received across the consumer client boundary."
  @spec normalize(term()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(%__MODULE__{} = delivery), do: {:ok, delivery}

  def normalize(_) do
    {:error,
     Error.new(
       :invalid_delivery,
       :client,
       :protocol,
       "client delivery must be an MQTT delivery value"
     )}
  end

  @doc "Returns the encoded MQTT Application Message payload."
  @spec payload(t()) :: binary()
  def payload(%__MODULE__{payload: payload}), do: payload

  @doc "Returns the delivery Topic Name."
  @spec topic(t()) :: String.t()
  def topic(%__MODULE__{topic: topic}), do: topic

  @doc "Returns the delivery QoS level."
  @spec qos(t()) :: QoS.t()
  def qos(%__MODULE__{qos: qos}), do: qos

  @doc "Returns whether the delivery has retained-message semantics."
  @spec retained?(t()) :: boolean()
  def retained?(%__MODULE__{retain: retain}), do: retain

  defp validate_retain(value) when is_boolean(value), do: :ok

  defp validate_retain(_),
    do:
      {:error,
       Error.new(:invalid_delivery_retain, :client, :protocol, "delivery retain must be boolean")}
end
