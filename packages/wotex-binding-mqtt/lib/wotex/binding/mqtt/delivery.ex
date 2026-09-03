defmodule Wotex.Binding.MQTT.Delivery do
  @moduledoc "Immutable, credential-free MQTT Application Message delivery."

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

  def new(_payload, _opts) do
    {:error,
     Error.new(
       :invalid_delivery,
       :client,
       "delivery requires a binary payload and keyword options"
     )}
  end

  @doc "Validates a delivery value received across the consumer client boundary."
  @spec normalize(term()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(%__MODULE__{} = delivery), do: {:ok, delivery}

  def normalize(_delivery) do
    {:error,
     Error.new(:invalid_delivery, :client, "client delivery must be an MQTT delivery value")}
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

  defp validate_retain(_value),
    do: {:error, Error.new(:invalid_delivery_retain, :client, "delivery retain must be boolean")}
end
