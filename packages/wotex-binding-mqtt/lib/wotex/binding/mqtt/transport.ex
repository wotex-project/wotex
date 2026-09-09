defmodule Wotex.Binding.MQTT.Transport do
  @moduledoc """
  Process-free MQTT implementation of `Wotex.Runtime.Transport`.

  A consumer-supplied `Wotex.Binding.MQTT.Client` owns every connection and
  subscription. `subscribe/4` hands the client the subscription owner pid and
  keeps no state; the client sends raw deliveries to that owner, which decodes
  them with `decode_frame/3` in its own process. No MQTT delivery is decoded on
  the client's connection process, and no callback captures the execution
  context.

  A publish acknowledgement is an `:accepted` result: the broker accepted the
  Application Message, which is not proof that a subscriber received it. A
  retained read that yields a representation is an `:ok` result. Control packet,
  QoS, retain, and Topic Name detail stay in the result metadata.
  """

  @behaviour Wotex.Runtime.Transport

  alias Wotex.Binding.MQTT.{Command, Delivery, Error, JSON, Mapping, Topic, TransportConfig}
  alias Wotex.Runtime.{Context, ExecutionContext, Request, Result}

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

  def request(_, _, _),
    do: invalid_transport_input(:request)

  @impl Wotex.Runtime.Transport
  def subscribe(
        %Request{} = request,
        owner,
        %ExecutionContext{} = execution_context,
        %TransportConfig{} = config
      )
      when is_pid(owner) do
    with {:ok, command} <- subscribe_command(request, config) do
      config.client
      |> safe_client_call(
        :subscribe,
        [command, owner, execution_context, config.client_config]
      )
      |> normalize_subscribe(request.operation)
    end
  end

  def subscribe(_, _, _, _),
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
             :protocol,
             "Runtime unsubscription requires an MQTT unsubscribe command"
           )}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def unsubscribe(_, _, _, _),
    do: invalid_transport_input(:unsubscribe)

  @impl Wotex.Runtime.Transport
  def decode_frame(frame, %Request{} = request, %TransportConfig{} = config) do
    with {:ok, command} <- subscribe_command(request, config) do
      decode_delivery(frame, command, request)
    end
  end

  def decode_frame(_, _, _),
    do: invalid_transport_input(:decode_frame)

  defp decode_delivery(frame, command, request) do
    with {:ok, delivery} <- Delivery.normalize(frame),
         true <- matching_delivery?(command, delivery),
         {:ok, payload} <-
           JSON.decode(Delivery.payload(delivery), Command.max_payload_bytes(command)) do
      {:ok, payload, delivery_meta(command, delivery, request)}
    else
      false -> :ignore
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp subscribe_command(request, config) do
    case Mapping.command(request, config.max_payload_bytes) do
      {:ok, command} ->
        if Command.packet(command) == :subscribe do
          {:ok, command}
        else
          {:error,
           Error.new(
             :invalid_subscription_packet,
             :mapping,
             :protocol,
             "Runtime subscription requires an MQTT subscribe command"
           )}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp execute_request(command, request, execution_context, config) do
    case {Command.packet(command), Command.operation(command)} do
      {:publish, _} ->
        config.client
        |> safe_client_call(:publish, [command, execution_context, config.client_config])
        |> normalize_publish(command, request)

      {:subscribe, :readproperty} ->
        read(command, request, execution_context, config)

      _ ->
        {:error,
         Error.new(
           :unsupported_request_packet,
           :mapping,
           :protocol,
           "Runtime request callback cannot execute this MQTT command"
         )}
    end
  end

  defp read(command, request, execution_context, config) do
    with {:ok, timeout} <- read_timeout(request, config) do
      config.client
      |> safe_client_call(:read, [command, timeout, execution_context, config.client_config])
      |> normalize_read(command, request, config.max_payload_bytes)
    end
  end

  defp read_timeout(%Request{deadline: deadline}, config) do
    case Context.remaining_ms(deadline, clock_reading(deadline)) do
      :infinity ->
        {:ok, config.read_timeout}

      0 ->
        {:error,
         Error.new(
           :deadline_exceeded,
           :client,
           :timeout,
           "the request deadline leaves no time for a retained Property read"
         )}

      remaining when is_integer(remaining) ->
        {:ok, min(config.read_timeout, remaining)}

      {:error, :clock_mismatch} ->
        {:error,
         Error.new(
           :invalid_deadline_clock,
           :configuration,
           :permanent,
           "request deadline must be a monotonic millisecond integer, a DateTime, or nil"
         )}
    end
  end

  defp clock_reading(%DateTime{}), do: DateTime.utc_now()
  defp clock_reading(_), do: System.monotonic_time(:millisecond)

  defp normalize_publish(:ok, command, request) do
    Result.new(request.request_id, request.operation, nil,
      status: :accepted,
      metadata: command_metadata(command)
    )
  end

  defp normalize_publish({:error, _}, _, request),
    do: client_failure(:client_publish_failed, :publish, request.operation)

  defp normalize_publish(_, _, request),
    do: invalid_client_return(:publish, request.operation)

  defp normalize_read({:ok, delivery_input}, command, request, max_payload_bytes) do
    with {:ok, delivery} <- Delivery.normalize(delivery_input),
         :ok <- validate_read_delivery(command, delivery),
         {:ok, payload} <- JSON.decode(Delivery.payload(delivery), max_payload_bytes) do
      Result.new(request.request_id, request.operation, payload,
        status: :ok,
        metadata: delivery_metadata(command, delivery)
      )
    end
  end

  defp normalize_read({:error, _}, _, request, _),
    do: client_failure(:client_read_failed, :read, request.operation)

  defp normalize_read(_, _, request, _),
    do: invalid_client_return(:read, request.operation)

  defp normalize_subscribe({:ok, handle}, _), do: {:ok, handle}

  defp normalize_subscribe({:error, _}, operation),
    do: client_failure(:client_subscribe_failed, :subscribe, operation)

  defp normalize_subscribe(_, operation),
    do: invalid_client_return(:subscribe, operation)

  defp normalize_unsubscribe(:ok, _), do: :ok

  defp normalize_unsubscribe({:error, _}, operation),
    do: client_failure(:client_unsubscribe_failed, :unsubscribe, operation)

  defp normalize_unsubscribe(_, operation),
    do: invalid_client_return(:unsubscribe, operation)

  defp validate_read_delivery(command, delivery) do
    cond do
      not Command.retain?(command) or not Delivery.retained?(delivery) ->
        {:error,
         Error.new(
           :non_retained_property_read,
           :client,
           :protocol,
           "Property read requires a retained MQTT delivery"
         )}

      not matching_delivery?(command, delivery) ->
        {:error,
         Error.new(
           :delivery_topic_mismatch,
           :client,
           :protocol,
           "MQTT delivery Topic Name does not match the command Topic Filters"
         )}

      true ->
        :ok
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
    _ -> {:error, :client_exception}
  catch
    _, _ -> {:error, :client_failure}
  end

  defp client_failure(code, packet, operation) do
    {:error,
     Error.new(code, :client, :unavailable, "MQTT client port call failed", %{
       packet: packet,
       operation: operation
     })}
  end

  defp invalid_client_return(packet, operation) do
    {:error,
     Error.new(
       :invalid_client_return,
       :client,
       :protocol,
       "MQTT client port returned an invalid value",
       %{packet: packet, operation: operation}
     )}
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
    |> Map.put(:topic, Delivery.topic(delivery))
    |> Map.put(:delivery_qos, Delivery.qos(delivery))
    |> Map.put(:delivery_retained, Delivery.retained?(delivery))
  end

  defp delivery_meta(command, delivery, request) do
    %{
      binding: :mqtt,
      control_packet: Command.packet(command),
      topic: Delivery.topic(delivery),
      qos: Delivery.qos(delivery),
      retained: Delivery.retained?(delivery),
      request_id: request.request_id,
      operation: request.operation
    }
  end

  defp invalid_transport_input(callback) do
    {:error,
     Error.new(
       :invalid_transport_input,
       :configuration,
       :permanent,
       "Runtime transport callback input is invalid",
       %{callback: callback}
     )}
  end
end
