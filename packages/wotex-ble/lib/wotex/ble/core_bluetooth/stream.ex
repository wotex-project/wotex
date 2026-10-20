defmodule Wotex.BLE.CoreBluetooth.Stream do
  @moduledoc false

  alias Wotex.BLE.{Address, Error, Procedure, Subscription}
  alias Wotex.BLE.CoreBluetooth.Characteristic

  @fields [:address, :receiver, :mode, :max_queue_length, :value_type, :byte_order, :timeout]
  @uint64 0xFFFF_FFFF_FFFF_FFFF

  @spec options(term(), term(), pid()) :: {:ok, map()} | {:error, Error.t()}
  def options(%{address: address} = request, default, caller) do
    with true <- Map.keys(request) -- @fields == [],
         receiver = Map.get(request, :receiver, caller),
         true <- is_pid(receiver) and node(receiver) == node(),
         mode = Map.get(request, :mode, :auto),
         true <- mode in [:auto, :notify, :indicate],
         limit = Map.get(request, :max_queue_length, 1000),
         true <- is_integer(limit) and limit in 1..10_000,
         {:ok, config} <-
           Procedure.options(
             Map.to_list(Map.take(request, [:timeout, :value_type, :byte_order])),
             default
           ),
         {:ok, address} <- Address.new(address) do
      {:ok,
       %{
         address: address,
         receiver: receiver,
         requested_mode: mode,
         max_queue_length: limit,
         credit: min(16, limit),
         timeout: config.timeout,
         type: config.type,
         codec: config.codec,
         cleanup_grace: 1600
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.new(:invalid_options)}
    end
  end

  def options(_, _, _), do: {:error, Error.new(:invalid_options)}

  @spec mode(Characteristic.t(), term()) :: {:ok, :notify | :indicate} | {:error, Error.t()}
  def mode(%Characteristic{notify: notify, indicate: indicate}, requested) do
    case {notify, indicate, requested} do
      {true, _, mode} when mode in [:auto, :notify] -> {:ok, :notify}
      {false, true, mode} when mode in [:auto, :indicate] -> {:ok, :indicate}
      _ -> {:error, Error.new(:not_supported)}
    end
  end

  def mode(_, _), do: {:error, Error.new(:invalid_options)}

  @spec handle?(term()) :: boolean()
  def handle?(
        %Subscription{
          pid: pid,
          reference: ref,
          session_reference: session,
          generation: generation
        } = handle
      ),
      do:
        map_size(handle) == 5 and is_pid(pid) and node(pid) == node() and
          is_reference(ref) and is_reference(session) and is_integer(generation) and
          generation in 1..@uint64

  def handle?(_), do: false

  @spec binding(term(), String.t(), map(), Characteristic.t()) :: {:ok, map()} | :invalid
  def binding(
        %{
          "stream_version" => 1,
          "subscription_id" => id,
          "route" => route,
          "requested_mode" => requested,
          "effective_mode" => effective,
          "credit" => credit
        } = value,
        id,
        config,
        characteristic
      )
      when map_size(value) == 6 do
    with true <- is_integer(route) and route === characteristic.route,
         true <- requested === Atom.to_string(config.requested_mode),
         true <- credit === config.credit,
         {:ok, selected} <- mode(characteristic, config.requested_mode),
         true <- effective === Atom.to_string(selected) do
      {:ok,
       %{
         subscription_id: id,
         characteristic: characteristic,
         requested_mode: config.requested_mode,
         effective_mode: selected,
         credit: credit
       }}
    else
      _ -> :invalid
    end
  end

  def binding(_, _, _, _), do: :invalid

  @spec identifier(term()) :: {:ok, pos_integer()} | :invalid
  def identifier(id) when is_binary(id) and byte_size(id) in 1..20 do
    with true <- not String.starts_with?(id, "0"),
         true <- Enum.all?(:binary.bin_to_list(id), &(&1 in ?0..?9)),
         {number, ""} when number in 1..@uint64 <- Integer.parse(id),
         do: {:ok, number},
         else: (_ -> :invalid)
  end

  def identifier(_), do: :invalid
end
