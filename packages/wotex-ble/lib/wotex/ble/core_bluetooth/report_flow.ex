defmodule Wotex.BLE.CoreBluetooth.ReportFlow do
  @moduledoc false

  alias Wotex.BLE.CoreBluetooth.Stream
  alias Wotex.BLE.Procedure

  @uint64 0xFFFF_FFFF_FFFF_FFFF
  defstruct [:generation, greatest: 0, streams: %{}, routes: MapSet.new()]

  @type t :: %__MODULE__{
          generation: pos_integer(),
          greatest: non_neg_integer(),
          streams: map(),
          routes: MapSet.t()
        }

  @spec new(pos_integer()) :: t()
  def new(generation), do: %__MODULE__{generation: generation}

  @spec used?(t(), pos_integer()) :: boolean()
  def used?(flow, route), do: MapSet.member?(flow.routes, route)

  @spec open(t(), pid(), map()) :: {:ok, t()} | :invalid
  def open(flow, owner, binding) do
    with {:ok, number} <- Stream.identifier(binding.subscription_id),
         true <- number > flow.greatest,
         true <- is_pid(owner) and map_size(flow.streams) < 16,
         true <- binding.credit in 1..64,
         true <- reserved(flow) + binding.credit <= 64,
         true <- binding.characteristic.generation === flow.generation,
         true <- not used?(flow, binding.characteristic.route) do
      stream = %{owner: owner, binding: binding, sequence: 0, acknowledged: 0, records: %{}}

      {:ok,
       %{
         flow
         | greatest: number,
           routes: MapSet.put(flow.routes, binding.characteristic.route),
           streams: Map.put(flow.streams, binding.subscription_id, stream)
       }}
    else
      _ -> :invalid
    end
  end

  @spec report(t(), term()) ::
          {:ok, pid(), String.t(), {pos_integer(), reference()}, tuple(), t()} | :invalid
  def report(
        flow,
        %{
          "version" => 1,
          "generation" => generation,
          "stream_version" => 1,
          "event" => "notification",
          "subscription_id" => id,
          "route" => route,
          "sequence" => sequence,
          "value" => value
        } = frame
      )
      when map_size(frame) == 8 do
    with true <- generation === flow.generation,
         %{binding: binding} = stream <- flow.streams[id],
         true <- is_integer(route) and route === binding.characteristic.route,
         true <- is_integer(sequence) and sequence in 1..@uint64,
         true <- sequence == stream.sequence + 1,
         true <- map_size(stream.records) < binding.credit,
         {:ok, bytes} <- Procedure.decode_bytes(value) do
      token = make_ref()

      metadata = %{
        source: :corebluetooth_value_update,
        characteristic: Map.from_struct(binding.characteristic),
        requested_mode: binding.requested_mode,
        effective_mode: binding.effective_mode
      }

      record = %{token: token, consumed: false}
      updated = %{stream | sequence: sequence, records: Map.put(stream.records, sequence, record)}

      {:ok, stream.owner, id, {sequence, token}, {:ok, bytes, metadata},
       %{flow | streams: Map.put(flow.streams, id, updated)}}
    else
      _ -> :invalid
    end
  end

  def report(_, _), do: :invalid

  @spec consume(t(), pid(), String.t(), term(), term()) :: {map() | nil, t()}
  def consume(flow, owner, id, sequence, token) do
    with %{owner: ^owner} = stream <- flow.streams[id],
         %{token: ^token} = record <- stream.records[sequence] do
      stream =
        advance(%{stream | records: Map.put(stream.records, sequence, %{record | consumed: true})})

      ack =
        if stream.acknowledged > flow.streams[id].acknowledged,
          do: acknowledgement(flow, id, stream.acknowledged)

      {ack, %{flow | streams: Map.put(flow.streams, id, stream)}}
    else
      _ -> {nil, flow}
    end
  end

  @spec retire(t(), term()) :: {:ok, String.t(), pid(), map() | nil, t()} | :invalid
  def retire(
        flow,
        %{
          "version" => 1,
          "generation" => generation,
          "stream_version" => 1,
          "event" => "notification_retired",
          "subscription_id" => id,
          "route" => route,
          "last_sequence" => last
        } = frame
      )
      when map_size(frame) == 7 do
    with true <- generation === flow.generation,
         %{binding: binding, sequence: sequence} = stream <- flow.streams[id],
         true <- route === binding.characteristic.route and last === sequence do
      ack = if last > stream.acknowledged, do: acknowledgement(flow, id, last)
      {:ok, id, stream.owner, ack, %{flow | streams: Map.delete(flow.streams, id)}}
    else
      _ -> :invalid
    end
  end

  def retire(_, _), do: :invalid

  defp reserved(flow),
    do: Enum.reduce(flow.streams, 0, fn {_, stream}, total -> total + stream.binding.credit end)

  defp advance(stream) do
    sequence = stream.acknowledged + 1

    case stream.records[sequence] do
      %{consumed: true} ->
        advance(%{stream | acknowledged: sequence, records: Map.delete(stream.records, sequence)})

      _ ->
        stream
    end
  end

  defp acknowledgement(flow, id, sequence),
    do: %{
      "version" => 1,
      "generation" => flow.generation,
      "stream_version" => 1,
      "event" => "notification_ack",
      "subscription_id" => id,
      "sequence" => sequence
    }
end
