defmodule Wotex.Binding.MQTT.Transport do
  @moduledoc """
  Process-free MQTT implementation of `Wotex.Runtime.Transport`.

  A consumer-supplied `Wotex.Binding.MQTT.Client` owns every connection and
  subscription. The delivery closure captures only the Runtime receiver, Topic
  Filters, and payload limit; it does not capture the execution context.
  """

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Binding.MQTT.{Command, Delivery, Error, JSON, Mapping, Topic, TransportConfig}
  alias Wotex.Runtime.{ExecutionContext, Request, Result}

  @impl Wotex.Runtime.Transport
  def request(
        %Request{} = request,
        %ExecutionContext{} = execution_context,
        %TransportConfig{} = config
      ) do
    with {:ok, command} <- Mapping.command(request, config.max_payload_bytes) do
      execute_request(command, request, execution_context, config)
    end
  end

  def request(_request, _execution_context, _config),
    do: invalid_transport_input(:request)

  @impl Wotex.Runtime.Transport
  def subscribe(
        %Request{} = request,
        receiver,
        %ExecutionContext{} = execution_context,
        %TransportConfig{} = config
      )
      when is_pid(receiver) do
    case Mapping.command(request, config.max_payload_bytes) do
      {:ok, command} ->
        if Command.packet(command) == :subscribe do
          delivery_callback = delivery_callback(receiver, command, config.max_payload_bytes)

          config.client
          |> safe_client_call(
            :subscribe,
            [command, delivery_callback, execution_context, config.client_config]
          )
          |> normalize_subscribe(request.operation)
        else
          {:error,
           Error.new(
             :invalid_subscription_packet,
             :mapping,
             "Runtime subscription requires an MQTT subscribe command"
           )}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def subscribe(_request, _receiver, _execution_context, _config),
    do: invalid_transport_input(:subscribe)

  @impl Wotex.Runtime.Transport
  def unsubscribe(
        handle,
        %Request{} = request,
        %ExecutionContext{} = execution_context,
        %TransportConfig{} = config
      ) do
    case Mapping.command(request, config.max_payload_bytes) do
      {:ok, command} ->
        if Command.packet(command) == :unsubscribe do
          config.client
          |> safe_client_call(
            :unsubscribe,
            [handle, command, execution_context, config.client_config]
          )
          |> normalize_unsubscribe(request.operation)
        else
          {:error,
           Error.new(
             :invalid_unsubscription_packet,
             :mapping,
             "Runtime unsubscription requires an MQTT unsubscribe command"
           )}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def unsubscribe(_handle, _request, _execution_context, _config),
    do: invalid_transport_input(:unsubscribe)

  defp execute_request(command, request, execution_context, config) do
    case {Command.packet(command), Command.operation(command)} do
      {:publish, _operation} ->
        config.client
        |> safe_client_call(:publish, [command, execution_context, config.client_config])
        |> normalize_publish(command, request)

      {:subscribe, :readproperty} ->
        config.client
        |> safe_client_call(:read, [
          command,
          config.read_timeout,
          execution_context,
          config.client_config
        ])
        |> normalize_read(command, request, config.max_payload_bytes)

      _unsupported ->
        {:error,
         Error.new(
           :unsupported_request_packet,
           :mapping,
           "Runtime request callback cannot execute this MQTT command"
         )}
    end
  end

  defp normalize_publish(:ok, command, request) do
    Result.new(request.request_id, request.operation, nil,
      status: :published,
      metadata: command_metadata(command)
    )
  end

  defp normalize_publish({:error, _external}, _command, request),
    do: client_failure(:client_publish_failed, :publish, request.operation)

  defp normalize_publish(_invalid, _command, request),
    do: invalid_client_return(:publish, request.operation)

  defp normalize_read({:ok, delivery_input}, command, request, max_payload_bytes) do
    with {:ok, delivery} <- Delivery.normalize(delivery_input),
         :ok <- validate_read_delivery(command, delivery),
         {:ok, payload} <- JSON.decode(Delivery.payload(delivery), max_payload_bytes) do
      Result.new(request.request_id, request.operation, payload,
        status: :received,
        metadata: delivery_metadata(command, delivery)
      )
    end
  end

  defp normalize_read({:error, _external}, _command, request, _max_payload_bytes),
    do: client_failure(:client_read_failed, :read, request.operation)

  defp normalize_read(_invalid, _command, request, _max_payload_bytes),
    do: invalid_client_return(:read, request.operation)

  defp normalize_subscribe({:ok, handle}, _operation), do: {:ok, handle}

  defp normalize_subscribe({:error, _external}, operation),
    do: client_failure(:client_subscribe_failed, :subscribe, operation)

  defp normalize_subscribe(_invalid, operation),
    do: invalid_client_return(:subscribe, operation)

  defp normalize_unsubscribe(:ok, _operation), do: :ok

  defp normalize_unsubscribe({:error, _external}, operation),
    do: client_failure(:client_unsubscribe_failed, :unsubscribe, operation)

  defp normalize_unsubscribe(_invalid, operation),
    do: invalid_client_return(:unsubscribe, operation)

  defp validate_read_delivery(command, delivery) do
    cond do
      not Command.retain?(command) or not Delivery.retained?(delivery) ->
        {:error,
         Error.new(
           :non_retained_property_read,
           :client,
           "Property read requires a retained MQTT delivery"
         )}

      not matching_delivery?(command, delivery) ->
        {:error,
         Error.new(
           :delivery_topic_mismatch,
           :client,
           "MQTT delivery Topic Name does not match the command Topic Filters"
         )}

      true ->
        :ok
    end
  end

  defp delivery_callback(receiver, command, max_payload_bytes) do
    fn delivery_input ->
      with {:ok, delivery} <- Delivery.normalize(delivery_input),
           true <- matching_delivery?(command, delivery),
           {:ok, payload} <- JSON.decode(Delivery.payload(delivery), max_payload_bytes) do
        send(receiver, {:wotex_transport, payload})
        :ok
      else
        false ->
          {:error,
           Error.new(
             :delivery_topic_mismatch,
             :client,
             "MQTT delivery Topic Name does not match the command Topic Filters"
           )}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  defp matching_delivery?(command, delivery) do
    Enum.any?(Command.filters(command), fn filter ->
      Topic.matches?(filter, Delivery.topic(delivery))
    end)
  end

  defp safe_client_call(client, function, arguments) do
    apply(client, function, arguments)
  rescue
    _external -> {:error, :client_exception}
  catch
    _kind, _external -> {:error, :client_failure}
  end

  defp client_failure(code, packet, operation) do
    {:error,
     Error.new(code, :client, "MQTT client port call failed", %{
       packet: packet,
       operation: operation
     })}
  end

  defp invalid_client_return(packet, operation) do
    {:error,
     Error.new(:invalid_client_return, :client, "MQTT client port returned an invalid value", %{
       packet: packet,
       operation: operation
     })}
  end

  defp command_metadata(command) do
    %{
      binding: :mqtt,
      control_packet: Command.packet(command),
      qos: Command.qos(command),
      retain: Command.retain?(command)
    }
  end

  defp delivery_metadata(command, delivery) do
    command_metadata(command)
    |> Map.put(:delivery_qos, Delivery.qos(delivery))
    |> Map.put(:delivery_retained, Delivery.retained?(delivery))
  end

  defp invalid_transport_input(callback) do
    {:error,
     Error.new(
       :invalid_transport_input,
       :configuration,
       "Runtime transport callback input is invalid",
       %{callback: callback}
     )}
  end
end
