defmodule Wotex.Binding.MQTT.Mapping do
  @moduledoc "Maps W3C WoT MQTT Form terms to immutable MQTT commands."

  alias Wotex.Binding.MQTT.{Broker, Command, Error, QoS}
  alias Wotex.Form
  alias Wotex.Runtime.Request

  @packets %{
    readproperty: :subscribe,
    writeproperty: :publish,
    observeproperty: :subscribe,
    unobserveproperty: :unsubscribe,
    invokeaction: :publish,
    subscribeevent: :subscribe,
    unsubscribeevent: :unsubscribe
  }

  @doc "Builds the command described by a Runtime request and MQTT Form."
  @spec command(Request.t(), pos_integer()) :: {:ok, Command.t()} | {:error, Error.t()}
  def command(%Request{} = request, max_payload_bytes)
      when is_integer(max_payload_bytes) and max_payload_bytes > 0 do
    form = Form.to_map(request.form)

    with {:ok, broker} <- Broker.new(request.resolved_href),
         {:ok, packet} <- control_packet(request.operation, form),
         :ok <- validate_target_terms(packet, form),
         :ok <- validate_read_retain(request.operation, form) do
      build_command(broker, packet, request, form, max_payload_bytes)
    end
  end

  def command(_request, _max_payload_bytes) do
    {:error,
     Error.new(:invalid_mapping_input, :mapping, "mapping requires a Runtime request and limit")}
  end

  @doc "Returns the default MQTT Control Packet for a supported WoT operation."
  @spec default_control_packet(atom()) ::
          {:ok, :publish | :subscribe | :unsubscribe} | {:error, Error.t()}
  def default_control_packet(operation) do
    case Map.fetch(@packets, operation) do
      {:ok, packet} ->
        {:ok, packet}

      :error ->
        {:error,
         Error.new(
           :unsupported_operation,
           :mapping,
           "WoT operation has no MQTT mapping in this package"
         )}
    end
  end

  defp control_packet(operation, form) do
    with {:ok, expected} <- default_control_packet(operation) do
      case Map.fetch(form, "mqv:controlPacket") do
        :error ->
          {:ok, expected}

        {:ok, value} when value in ["publish", "subscribe", "unsubscribe"] ->
          explicit = String.to_existing_atom(value)

          if explicit == expected do
            {:ok, explicit}
          else
            control_packet_mismatch()
          end

        {:ok, _invalid} ->
          control_packet_mismatch()
      end
    end
  end

  defp control_packet_mismatch do
    {:error,
     Error.new(
       :control_packet_mismatch,
       :mapping,
       "mqv:controlPacket does not match the WoT operation mapping"
     )}
  end

  defp validate_target_terms(:publish, form),
    do: require_only(form, "mqv:topic", "mqv:filter")

  defp validate_target_terms(packet, form) when packet in [:subscribe, :unsubscribe],
    do: require_only(form, "mqv:filter", "mqv:topic")

  defp require_only(form, required, forbidden) do
    cond do
      not Map.has_key?(form, required) ->
        {:error,
         Error.new(
           :missing_mqtt_target,
           :mapping,
           "Form is missing the packet's dedicated MQTT target term"
         )}

      Map.has_key?(form, forbidden) ->
        {:error,
         Error.new(
           :mixed_mqtt_targets,
           :mapping,
           "Form must not mix mqv:topic and mqv:filter"
         )}

      true ->
        :ok
    end
  end

  defp validate_read_retain(:readproperty, %{"mqv:retain" => true}), do: :ok

  defp validate_read_retain(:readproperty, _form) do
    {:error,
     Error.new(
       :retained_read_required,
       :mapping,
       "readproperty requires mqv:retain to be true"
     )}
  end

  defp validate_read_retain(_operation, _form), do: :ok

  defp build_command(broker, :publish, request, form, max_payload_bytes) do
    Command.publish(broker, request.operation, form["mqv:topic"], request.input,
      qos: Map.get(form, "mqv:qos", 0),
      retain: Map.get(form, "mqv:retain", false),
      content_type: content_type(form),
      max_payload_bytes: max_payload_bytes
    )
  end

  defp build_command(broker, :subscribe, request, form, _max_payload_bytes) do
    Command.subscribe(broker, request.operation, form["mqv:filter"],
      qos: Map.get(form, "mqv:qos", 0),
      retain: Map.get(form, "mqv:retain", false),
      content_type: content_type(form)
    )
  end

  defp build_command(broker, :unsubscribe, request, form, _max_payload_bytes) do
    with :ok <- validate_unsubscribe_qos(form) do
      Command.unsubscribe(broker, request.operation, form["mqv:filter"],
        retain: Map.get(form, "mqv:retain", false),
        content_type: content_type(form)
      )
    end
  end

  defp validate_unsubscribe_qos(form) do
    case Map.fetch(form, "mqv:qos") do
      :error -> :ok
      {:ok, qos} -> normalize_qos_validation(QoS.normalize(qos))
    end
  end

  defp normalize_qos_validation({:ok, _qos}), do: :ok
  defp normalize_qos_validation({:error, %Error{} = error}), do: {:error, error}

  defp content_type(form), do: Map.get(form, "contentType") || "application/json"
end
