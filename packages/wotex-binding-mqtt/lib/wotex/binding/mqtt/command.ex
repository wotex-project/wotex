defmodule Wotex.Binding.MQTT.Command do
  @moduledoc """
  Immutable, credential-free MQTT command.

  Publish commands contain one Topic Name and an encoded JSON payload.
  Subscribe and unsubscribe commands contain one or more Topic Filters.
  """

  alias Wotex.Binding.MQTT.{Broker, Error, JSON, QoS, Topic}

  @publish_operations [:writeproperty, :invokeaction]
  @subscribe_operations [:readproperty, :observeproperty, :subscribeevent]
  @unsubscribe_operations [:unobserveproperty, :unsubscribeevent]
  @default_max_payload_bytes 1_048_576

  @derive {Inspect,
           only: [:broker, :packet, :operation, :topic, :filters, :qos, :retain, :content_type]}
  @opaque t :: %__MODULE__{
            broker: Broker.t(),
            packet: :publish | :subscribe | :unsubscribe,
            operation: atom(),
            topic: String.t() | nil,
            filters: [String.t()],
            qos: QoS.t() | nil,
            retain: boolean(),
            payload: binary() | nil,
            content_type: String.t()
          }

  @enforce_keys [
    :broker,
    :packet,
    :operation,
    :topic,
    :filters,
    :qos,
    :retain,
    :payload,
    :content_type
  ]
  defstruct @enforce_keys

  @doc "Builds a PUBLISH command and JSON-encodes its value."
  @spec publish(Broker.t(), atom(), String.t(), JSON.json_value(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def publish(broker, operation, topic, value, opts \\ [])

  def publish(%Broker{} = broker, operation, topic, value, opts)
      when operation in @publish_operations and is_list(opts) do
    with :ok <- Topic.validate_name(topic),
         {:ok, qos} <- QoS.normalize(Keyword.get(opts, :qos, 0)),
         {:ok, retain} <- validate_retain(Keyword.get(opts, :retain, false)),
         {:ok, max_bytes} <- max_payload_bytes(opts),
         {:ok, content_type} <- normalize_content_type(opts),
         {:ok, payload} <- JSON.encode(value, max_bytes) do
      {:ok,
       build(
         broker,
         :publish,
         operation,
         topic,
         [],
         qos,
         retain,
         payload,
         content_type
       )}
    end
  end

  def publish(_broker, _operation, _topic, _value, _opts),
    do: invalid_command("publish command input is invalid")

  @doc "Builds a SUBSCRIBE command for one or more Topic Filters."
  @spec subscribe(Broker.t(), atom(), String.t() | [String.t()], keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def subscribe(broker, operation, filters, opts \\ [])

  def subscribe(%Broker{} = broker, operation, filters, opts)
      when operation in @subscribe_operations and is_list(opts) do
    with {:ok, normalized_filters} <- Topic.normalize_filters(filters),
         {:ok, qos} <- QoS.normalize(Keyword.get(opts, :qos, 0)),
         {:ok, retain} <- validate_retain(Keyword.get(opts, :retain, false)),
         {:ok, content_type} <- normalize_content_type(opts) do
      {:ok,
       build(
         broker,
         :subscribe,
         operation,
         nil,
         normalized_filters,
         qos,
         retain,
         nil,
         content_type
       )}
    end
  end

  def subscribe(_broker, _operation, _filters, _opts),
    do: invalid_command("subscribe command input is invalid")

  @doc "Builds an UNSUBSCRIBE command for one or more Topic Filters."
  @spec unsubscribe(Broker.t(), atom(), String.t() | [String.t()], keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def unsubscribe(broker, operation, filters, opts \\ [])

  def unsubscribe(%Broker{} = broker, operation, filters, opts)
      when operation in @unsubscribe_operations and is_list(opts) do
    with {:ok, normalized_filters} <- Topic.normalize_filters(filters),
         {:ok, retain} <- validate_retain(Keyword.get(opts, :retain, false)),
         {:ok, content_type} <- normalize_content_type(opts) do
      {:ok,
       build(
         broker,
         :unsubscribe,
         operation,
         nil,
         normalized_filters,
         nil,
         retain,
         nil,
         content_type
       )}
    end
  end

  def unsubscribe(_broker, _operation, _filters, _opts),
    do: invalid_command("unsubscribe command input is invalid")

  @doc "Returns the broker endpoint."
  @spec broker(t()) :: Broker.t()
  def broker(%__MODULE__{broker: broker}), do: broker

  @doc "Returns the MQTT Control Packet kind."
  @spec packet(t()) :: :publish | :subscribe | :unsubscribe
  def packet(%__MODULE__{packet: packet}), do: packet

  @doc "Returns the WoT operation mapped by this command."
  @spec operation(t()) :: atom()
  def operation(%__MODULE__{operation: operation}), do: operation

  @doc "Returns the PUBLISH Topic Name, or `nil` for another packet."
  @spec topic(t()) :: String.t() | nil
  def topic(%__MODULE__{topic: topic}), do: topic

  @doc "Returns the SUBSCRIBE or UNSUBSCRIBE Topic Filters."
  @spec filters(t()) :: [String.t()]
  def filters(%__MODULE__{filters: filters}), do: filters

  @doc "Returns the normalized QoS, or `nil` when the packet does not use it."
  @spec qos(t()) :: QoS.t() | nil
  def qos(%__MODULE__{qos: qos}), do: qos

  @doc "Returns the Form's retain semantics."
  @spec retain?(t()) :: boolean()
  def retain?(%__MODULE__{retain: retain}), do: retain

  @doc "Returns the encoded JSON payload, or `nil` when absent."
  @spec payload(t()) :: binary() | nil
  def payload(%__MODULE__{payload: payload}), do: payload

  @doc "Returns the normalized JSON content type."
  @spec content_type(t()) :: String.t()
  def content_type(%__MODULE__{content_type: content_type}), do: content_type

  defp build(
         broker,
         packet,
         operation,
         topic,
         filters,
         qos,
         retain,
         payload,
         content_type
       ) do
    %__MODULE__{
      broker: broker,
      packet: packet,
      operation: operation,
      topic: topic,
      filters: filters,
      qos: qos,
      retain: retain,
      payload: payload,
      content_type: content_type
    }
  end

  defp validate_retain(value) when is_boolean(value), do: {:ok, value}

  defp validate_retain(_value),
    do: {:error, Error.new(:invalid_retain, :command, :protocol, "mqv:retain must be boolean")}

  defp max_payload_bytes(opts) do
    case Keyword.get(opts, :max_payload_bytes, @default_max_payload_bytes) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _invalid ->
        {:error,
         Error.new(:invalid_payload_limit, :command, :permanent, "payload limit is invalid")}
    end
  end

  defp normalize_content_type(opts) do
    value = Keyword.get(opts, :content_type, "application/json")

    if json_content_type?(value) do
      {:ok, "application/json"}
    else
      {:error,
       Error.new(
         :unsupported_content_type,
         :command,
         :protocol,
         "contentType must be application/json"
       )}
    end
  end

  defp json_content_type?(value) when is_binary(value) do
    value
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
    |> Kernel.==("application/json")
  end

  defp json_content_type?(_value), do: false

  defp invalid_command(message),
    do: {:error, Error.new(:invalid_command, :command, :protocol, message)}
end
