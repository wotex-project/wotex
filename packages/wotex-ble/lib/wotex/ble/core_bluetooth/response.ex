defmodule Wotex.BLE.CoreBluetooth.Response do
  @moduledoc false

  alias Wotex.BLE.CoreBluetooth.Characteristic
  alias Wotex.BLE.{Error, Procedure}

  @codes ~w(ok invalid_options not_authorized disconnected stale_discovery not_permitted not_supported invalid_value_length timeout clock_regressed invalid_response resource_limit transport_error cleanup_timeout peer_not_found busy invalid_value)a
  @code_map Map.new(@codes, &{Atom.to_string(&1), &1})

  @doc "Validates the response envelope against the active connection generation."
  @spec decode(map(), non_neg_integer()) :: tuple() | :invalid
  def decode(%{"version" => 1, "generation" => generation} = frame, generation) do
    case frame do
      %{"event" => "write_submitted", "id" => id} when map_size(frame) == 4 and is_binary(id) ->
        {:submitted, id}

      %{"event" => "connection_lost", "code" => code} when map_size(frame) == 4 ->
        case Map.fetch(@code_map, code) do
          {:ok, code} when code != :ok -> {:lost, code}
          _ -> :invalid
        end

      %{"id" => id, "ok" => true, "result" => result} when map_size(frame) == 5 and is_binary(id) ->
        {:reply, id, {:ok, result}}

      %{"id" => id, "ok" => false, "error" => error} when map_size(frame) == 5 and is_binary(id) ->
        decode_error(id, error)

      _ ->
        :invalid
    end
  end

  def decode(_, _), do: :invalid

  defp decode_error(
         id,
         %{
           "code" => code,
           "cause" => cause,
           "submitted" => submitted,
           "cleanup_confirmed" => cleanup
         } = error
       )
       when map_size(error) == 4 do
    with {:ok, code} when code != :ok <- Map.fetch(@code_map, code),
         {:ok, _} <- Map.fetch(@code_map, cause),
         true <- is_boolean(submitted) and is_boolean(cleanup) do
      {:reply, id, {:error, Error.new(code), submitted, cleanup}}
    else
      _ -> :invalid
    end
  end

  defp decode_error(_, _), do: :invalid

  @doc "Validates and decodes the result of one supported native operation."
  @spec result(atom(), term(), pos_integer()) :: {:ok, term()} | :invalid
  def result(:open, %{"generation" => generation} = value, generation) when map_size(value) == 1,
    do: {:ok, :opened}

  def result(:discover, %{"characteristics" => records} = value, generation)
      when map_size(value) == 1 and is_list(records) and length(records) <= 256 do
    decoded =
      records
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {record, index}, {:ok, result} ->
        case characteristic(record, index, generation) do
          {:ok, characteristic} -> {:cont, {:ok, [characteristic | result]}}
          _ -> {:halt, :invalid}
        end
      end)

    case decoded do
      {:ok, records} -> {:ok, %{generation: generation, characteristics: Enum.reverse(records)}}
      _ -> :invalid
    end
  end

  def result(:read, value, _), do: Procedure.decode_bytes(value)
  def result(:write, nil, _), do: {:ok, :written}

  def result(
        :write_command,
        %{"write_mode" => "without_response", "evidence" => "native_queue_accepted"} = value,
        _
      )
      when map_size(value) == 2,
      do: {:ok, %{write_mode: :without_response, evidence: :native_queue_accepted}}

  def result(:health, %{"connected" => true, "services_resolved" => true} = value, _)
      when map_size(value) == 2, do: {:ok, %{connected: true, services_resolved: true}}

  def result(:close, nil, _), do: {:ok, :closed}
  def result(_, _, _), do: :invalid

  defp characteristic(
         %{
           "route" => index,
           "service_uuid" => service,
           "characteristic_uuid" => uuid,
           "read" => read,
           "write" => write,
           "write_without_response" => command,
           "notify" => notify,
           "indicate" => indicate
         } = record,
         index,
         generation
       )
       when map_size(record) == 8 do
    with {:ok, value} <-
           Characteristic.new(%{
             service: service,
             characteristic: uuid,
             generation: generation,
             route: index,
             read: read,
             write: write,
             write_without_response: command,
             notify: notify,
             indicate: indicate
           }),
         true <- value.service == service and value.characteristic == uuid do
      {:ok, value}
    else
      _ -> :invalid
    end
  end

  defp characteristic(_, _, _), do: :invalid
end
