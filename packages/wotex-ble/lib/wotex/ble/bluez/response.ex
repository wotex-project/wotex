defmodule Wotex.BLE.BlueZ.Response do
  @moduledoc """
  Validates operation-specific replies from the persistent BlueZ bridge.

  This implementation helper admits exact versioned success or error envelopes
  and converts only a fixed set of error-code strings to existing atoms.
  Optional BlueZ error names must match the bounded org.bluez.Error namespace;
  public details retain that name without external error-message text. The
  connection separately correlates the reply ID with dispatched work.

  Result validation checks discovery ordering, unique characteristic paths,
  generation and cursor syntax, paired state, live health fields and bounded
  read bytes. Stream establishment is delegated to `Wotex.BLE.BlueZ.Stream`.
  Unknown fields, codes and response shapes return `:invalid`; no malformed
  reply can count as successful protocol completion.
  """

  alias Wotex.BLE.BlueZ.Stream
  alias Wotex.BLE.{Characteristic, Error, ObjectPath, Procedure}

  @codes ~w(invalid_options invalid_peer disconnected owner_changed not_permitted not_authorized not_supported busy invalid_value_length invalid_offset improperly_configured remote_error object_limit peer_not_found ambiguous_peer invalid_response invalid_characteristic peer_changed generation_exhausted snapshot_unstable timeout services_unresolved stale_discovery invalid_cursor cursor_limit transport_error pairing_rejected invalid_address invalid_value address_mismatch ambiguous_characteristic unsupported_procedure_selection already_subscribed invalid_subscription response_limit subscription_lost cleanup_timeout)a
  @errors Map.new(@codes, &{Atom.to_string(&1), &1})
  @fields ~w(service_uuid characteristic_uuid service_path object_path flags generation handle)

  @doc false
  @spec parse(term(), String.t()) :: {:ok, term()} | {:error, Error.t()} | :invalid
  def parse(%{"version" => 1, "id" => id, "ok" => true, "result" => result} = frame, operation)
      when is_binary(id) and map_size(frame) == 4 do
    result(operation, result)
  end

  def parse(%{"version" => 1, "id" => id, "ok" => false, "error" => error} = frame, _)
      when is_binary(id) and map_size(frame) == 4 and is_map(error) do
    case error do
      %{"code" => code} when map_size(error) == 1 ->
        failure(code)

      %{"code" => code, "status" => status} when map_size(error) == 2 and is_integer(status) ->
        failure(code)

      %{"code" => code, "name" => name} when map_size(error) == 2 ->
        named_failure(code, name)

      %{"code" => code, "status" => status, "name" => name}
      when map_size(error) == 3 and is_integer(status) ->
        named_failure(code, name)

      _ ->
        :invalid
    end
  end

  def parse(_, _), do: :invalid

  defp failure(code) do
    case Map.fetch(@errors, code) do
      {:ok, code} -> {:error, Error.new(code)}
      :error -> :invalid
    end
  end

  defp named_failure(code, name) when is_binary(name) and byte_size(name) <= 128 do
    with true <-
           Regex.match?(
             ~r/\Aorg\.bluez\.Error\.[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\z/,
             name
           ),
         {:error, error} <- failure(code) do
      {:error, %{error | details: %{dbus_name: name}}}
    else
      _ -> :invalid
    end
  end

  defp named_failure(_, _), do: :invalid

  defp result("health", %{"connected" => true, "services_resolved" => true} = value)
       when map_size(value) == 2,
       do: {:ok, %{connected: true, services_resolved: true}}

  defp result("subscribe", value), do: Stream.establishment(value)
  defp result("read", value), do: Procedure.decode_bytes(value)
  defp result("write", nil), do: {:ok, :written}

  defp result(
         "open",
         %{
           "generation" => generation,
           "device_path" => path,
           "link_owned" => owned,
           "sender" => sender
         } = result
       )
       when map_size(result) == 4 and is_boolean(owned) and is_binary(sender) do
    if generation?(generation) and ObjectPath.valid?(path) and byte_size(sender) <= 128 and
         Regex.match?(~r/\A:[0-9]+\.[0-9]+\z/, sender),
       do: {:ok, result},
       else: :invalid
  end

  defp result(
         "discover",
         %{"generation" => generation, "characteristics" => items, "cursor" => cursor} = result
       )
       when map_size(result) == 3 and is_list(items) and length(items) <= 64 do
    if generation?(generation) and cursor?(cursor),
      do: page(items, generation, cursor),
      else: :invalid
  end

  defp result("pair", %{"paired" => true} = result) when map_size(result) == 1,
    do: {:ok, %{paired: true}}

  defp result(operation, nil) when operation in ["close", "agent_reply", "unsubscribe"],
    do: {:ok, nil}

  defp result(_, _), do: :invalid

  defp page(items, generation, cursor) do
    reduced =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case characteristic(item, generation) do
          {:ok, characteristic} -> {:cont, {:ok, [characteristic | acc]}}
          _ -> {:halt, :invalid}
        end
      end)

    case reduced do
      {:ok, items} ->
        ordered = Enum.reverse(items)
        identities = Enum.map(ordered, &{&1.service_path, &1.object_path})

        if identities == Enum.sort(Enum.uniq(identities)),
          do: {:ok, %{generation: generation, characteristics: ordered, cursor: cursor}},
          else: :invalid

      :invalid ->
        :invalid
    end
  end

  defp characteristic(%{"generation" => generation} = item, generation) when map_size(item) == 7 do
    if Enum.sort(Map.keys(item)) == Enum.sort(@fields) do
      Characteristic.new(Map.new(@fields, &{String.to_existing_atom(&1), Map.fetch!(item, &1)}))
    else
      :invalid
    end
  end

  defp characteristic(_, _), do: :invalid
  defp generation?(value), do: is_integer(value) and value in 1..0xFFFF_FFFF_FFFF_FFFF
  defp cursor?(nil), do: true

  defp cursor?(value) when is_binary(value),
    do: byte_size(value) == 32 and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  defp cursor?(_), do: false
end
