defmodule Wotex.BLE.BlueZ.Stream do
  @moduledoc false

  alias Wotex.BLE.{Address, Error, Procedure, Subscription}

  @fields [:address, :receiver, :mode, :max_queue_length, :value_type, :byte_order, :timeout]
  @modes [:auto, :notify, :indicate]

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
