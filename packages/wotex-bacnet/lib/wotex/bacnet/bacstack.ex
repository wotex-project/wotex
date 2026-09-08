defmodule Wotex.BACnet.BACstack do
  @moduledoc "BACstack 0.0.1 adapter over a borrowed, explicitly configured Client process."
  @behaviour Wotex.BACnet.Client
  alias BACnet.Protocol.{APDU, Constants, ObjectIdentifier, Services}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{Address, Error}

  @impl Wotex.BACnet.Client
  def connect(opts) do
    client = Keyword.get(opts, :stack_client)
    destination = Keyword.get(opts, :destination)

    if is_pid(client) and Process.alive?(client) and valid_destination?(destination),
      do:
        {:ok,
         %{client: client, destination: destination, writes: Keyword.get(opts, :writes, false)}},
      else: {:error, Error.new(:invalid_options)}
  end

  @impl Wotex.BACnet.Client
  def request(handle, message, timeout) do
    with {:ok, address} <- Address.new(message),
         {:ok, service} <- service(address, message, handle.writes),
         {:ok, apdu} <- Services.Protocol.to_apdu(service, []) do
      task =
        Task.async(fn ->
          try do
            BACnet.Stack.Client.send(handle.client, handle.destination, apdu, [])
          catch
            :exit, _ -> {:error, :connection_closed}
          end
        end)

      result =
        try do
          case Task.yield(task, timeout) do
            {:ok, result} -> result
            _ -> {:error, :timeout}
          end
        after
          Task.shutdown(task, :brutal_kill)
        end

      response(result, address, message.type)
    end
  end

  @impl Wotex.BACnet.Client
  def disconnect(_handle), do: :ok

  @doc "Accepts only an exact service acknowledgment; missing/negative responses fail."
  @spec response(term(), Address.t(), atom()) :: {:ok, term()} | {:error, Error.t()}
  def response({:ok, %APDU.ComplexACK{} = apdu}, address, :read_property) do
    with {:ok, ack} <- Services.Ack.ReadPropertyAck.from_apdu(apdu),
         true <-
           Constants.by_name_atom(:object_type, ack.object_identifier.type) == address.object_type,
         true <- ack.object_identifier.instance == address.instance,
         true <-
           property_id(ack.property_identifier) == address.property,
         true <- ack.property_array_index == address.array_index do
      {:ok, ack.property_value}
    else
      _ -> {:error, Error.new(:response_mismatch)}
    end
  end

  def response({:ok, %APDU.SimpleACK{service: :write_property}}, _, :write_property),
    do: {:ok, :written}

  def response({:ok, %APDU.Error{class: class, code: code}}, _, _),
    do: {:error, Error.new(:remote_error, nil, %{class: class, code: code})}

  def response({:ok, %APDU.Abort{reason: reason}}, _, _),
    do: {:error, Error.new(:remote_abort, nil, %{reason: reason})}

  def response({:ok, %APDU.Reject{reason: reason}}, _, _),
    do: {:error, Error.new(:remote_reject, nil, %{reason: reason})}

  def response({:error, _}, _, _), do: {:error, Error.new(:transport_error)}
  def response(_, _, _), do: {:error, Error.new(:missing_acknowledgment)}

  defp property_id(value), do: Constants.by_name_atom(:property_identifier, value)

  defp service(address, %{type: :read_property}, _) do
    {:ok,
     %Services.ReadProperty{
       object_identifier: object(address),
       property_identifier: address.property,
       property_array_index: address.array_index
     }}
  end

  defp service(address, %{type: :write_property, value: %Encoding{} = value}, true) do
    {:ok,
     %Services.WriteProperty{
       object_identifier: object(address),
       property_identifier: address.property,
       property_array_index: address.array_index,
       property_value: value,
       priority: address.priority
     }}
  end

  defp service(_, _, _), do: {:error, Error.new(:write_configuration_required)}

  defp object(address),
    do: %ObjectIdentifier{
      type: Constants.by_value(:object_type, address.object_type, address.object_type),
      instance: address.instance
    }

  defp valid_destination?({{a, b, c, d}, port}) when port in 1..65_535,
    do: Enum.all?([a, b, c, d], &(is_integer(&1) and &1 in 0..255))

  defp valid_destination?(_), do: false
end
