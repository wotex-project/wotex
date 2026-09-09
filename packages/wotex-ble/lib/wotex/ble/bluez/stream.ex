defmodule Wotex.BLE.BlueZ.Stream do
  @moduledoc """
  Validates native subscription options, establishment and value-change frames.

  This implementation helper checks receiver and queue limits, reuses the
  GATT address and value-codec validators, and binds every report to the exact
  established characteristic and subscription identity. Wire data has closed
  field sets and bounded canonical byte envelopes. It creates no subscription
  or process; lifecycle belongs to the connection and SubscriptionOwner.

  With only notify or indicate available, auto selects that procedure. When
  both are advertised, BlueZ chooses and the effective mode is bluez_selected;
  explicitly forcing either procedure is rejected. Metadata states
  bluez_value_change because D-Bus Value changes do not identify ATT origin.

  ## Examples

      iex> Wotex.BLE.BlueZ.Stream.mode(["notify", "indicate"], :auto)
      {:ok, :bluez_selected}
  """

  alias Wotex.BLE.{Address, Characteristic, Error, Procedure, Subscription}
  alias Wotex.BLE.BlueZ.Response

  @fields [:address, :receiver, :mode, :max_queue_length, :value_type, :byte_order, :timeout]
  @modes [:auto, :notify, :indicate]
  @names %{
    "auto" => :auto,
    "notify" => :notify,
    "indicate" => :indicate,
    "bluez_selected" => :bluez_selected
  }
  @characteristic_fields ~w(service_uuid characteristic_uuid service_path object_path flags generation handle)a

  @doc false
  @spec options(term(), term(), pid()) :: {:ok, map()} | {:error, Error.t()}
  def options(%{address: address} = request, default, caller) do
    with true <- Map.keys(request) -- @fields == [],
         receiver = Map.get(request, :receiver, caller),
         true <- is_pid(receiver),
         requested = Map.get(request, :mode, :auto),
         true <- requested in @modes,
         queue = Map.get(request, :max_queue_length, 1000),
         true <- is_integer(queue) and queue in 1..10_000,
         {:ok, config} <-
           Procedure.options(
             Map.to_list(Map.take(request, [:timeout, :value_type, :byte_order])),
             default
           ),
         {:ok, address} <- Address.new(address),
         {:ok, "read", parameters} <-
           Procedure.parameters(Map.put(Map.from_struct(address), :type, :read)) do
      {:ok,
       %{
         receiver: receiver,
         requested_mode: requested,
         max_queue_length: queue,
         timeout: config.timeout,
         type: config.type,
         codec: config.codec,
         parameters: Map.put(parameters, "mode", Atom.to_string(requested))
       }}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  def options(_, _, _), do: {:error, Error.new(:invalid_options)}

  @doc false
  @spec mode(term(), term()) :: {:ok, :notify | :indicate | :bluez_selected} | {:error, Error.t()}
  def mode(flags, requested) when requested in @modes do
    if flags?(flags) do
      select("notify" in flags, "indicate" in flags, requested)
    else
      {:error, Error.new(:invalid_characteristic)}
    end
  end

  def mode(_, _), do: {:error, Error.new(:invalid_options)}

  @doc false
  @spec handle?(term()) :: boolean()
  def handle?(
        %Subscription{
          pid: pid,
          reference: reference,
          generation: generation,
          session_reference: session
        } = handle
      ),
      do:
        map_size(handle) == 5 and is_pid(pid) and is_reference(reference) and
          is_reference(session) and generation === 1

  def handle?(_), do: false

  @type binding :: %{
          subscription_id: String.t(),
          generation: 1,
          characteristic: Characteristic.t(),
          requested_mode: :auto | :notify | :indicate,
          effective_mode: :notify | :indicate | :bluez_selected
        }

  @doc false
  @spec establishment(term()) :: {:ok, binding()} | :invalid
  def establishment(
        %{
          "subscription_id" => id,
          "generation" => 1,
          "characteristic" => characteristic,
          "requested_mode" => requested,
          "effective_mode" => effective
        } = value
      )
      when map_size(value) == 5 do
    with true <- identifier?(id),
         {:ok, characteristic} <- characteristic(characteristic),
         {:ok, requested} <- Map.fetch(@names, requested),
         {:ok, effective} <- Map.fetch(@names, effective),
         {:ok, ^effective} <- mode(characteristic.flags, requested) do
      {:ok,
       %{
         subscription_id: id,
         generation: 1,
         characteristic: characteristic,
         requested_mode: requested,
         effective_mode: effective
       }}
    else
      _ -> :invalid
    end
  end

  def establishment(_), do: :invalid

  @doc false
  @spec matches?(map(), String.t(), map()) :: boolean()
  def matches?(binding, id, parameters) do
    target = parameters["address"]
    item = binding.characteristic

    binding.subscription_id == id and
      Atom.to_string(binding.requested_mode) == parameters["mode"] and
      item.service_uuid == target["service"] and
      item.characteristic_uuid == target["characteristic"] and
      Enum.all?([:object_path, :handle, :generation], fn field ->
        selected = target[Atom.to_string(field)]
        is_nil(selected) or selected == Map.fetch!(item, field)
      end)
  end

  @doc false
  @spec report(term(), map() | nil) ::
          {:ok, binary(), map()} | {:error, Error.t()} | :invalid
  def report(
        %{
          "version" => 1,
          "subscription_id" => id,
          "generation" => 1,
          "event" => event,
          "value" => value,
          "metadata" => metadata
        } = frame,
        binding
      )
      when map_size(frame) == 6 do
    if identifier?(id) and (is_nil(binding) or binding.subscription_id == id) do
      report_value(event, value, metadata, id, binding)
    else
      :invalid
    end
  end

  def report(_, _), do: :invalid

  defp report_value("value", value, %{"source" => "bluez_value_change"} = metadata, id, binding)
       when map_size(metadata) == 4 do
    encoded =
      metadata
      |> Map.delete("source")
      |> Map.merge(%{"subscription_id" => id, "generation" => 1})

    with {:ok, observed} <- establishment(encoded),
         true <- is_nil(binding) or observed == binding,
         {:ok, bytes} <- Procedure.decode_bytes(value) do
      {:ok, bytes,
       observed
       |> Map.take([:characteristic, :requested_mode, :effective_mode])
       |> Map.put(:source, :bluez_value_change)}
    else
      _ -> :invalid
    end
  end

  defp report_value("error", nil, %{"error" => error} = metadata, id, _)
       when map_size(metadata) == 1 do
    case Response.parse(%{"version" => 1, "id" => id, "ok" => false, "error" => error}, "subscribe") do
      {:error, %Error{}} = error -> error
      _ -> :invalid
    end
  end

  defp report_value(_, _, _, _, _), do: :invalid

  defp characteristic(value) when is_map(value) and map_size(value) == 7 do
    if Enum.sort(Map.keys(value)) == Enum.sort(Enum.map(@characteristic_fields, &Atom.to_string/1)) do
      Characteristic.new(
        Map.new(@characteristic_fields, &{&1, Map.fetch!(value, Atom.to_string(&1))})
      )
    else
      :invalid
    end
  end

  defp characteristic(_), do: :invalid
  defp identifier?(id), do: is_binary(id) and byte_size(id) in 1..64 and String.valid?(id)

  defp flags?(flags) when is_list(flags) and length(flags) <= 64 do
    length(Enum.uniq(flags)) == length(flags) and
      Enum.all?(
        flags,
        &(is_binary(&1) and byte_size(&1) >= 1 and byte_size(&1) <= 64 and String.valid?(&1))
      )
  end

  defp flags?(_), do: false
  defp select(true, true, :auto), do: {:ok, :bluez_selected}
  defp select(true, true, _), do: {:error, Error.new(:unsupported_procedure_selection)}
  defp select(true, false, mode) when mode in [:auto, :notify], do: {:ok, :notify}
  defp select(false, true, mode) when mode in [:auto, :indicate], do: {:ok, :indicate}
  defp select(_, _, _), do: {:error, Error.new(:not_supported)}
end
