defmodule Wotex.BLE.BlueZ.ReportFlow do
  @moduledoc """
  Tracks the bounded native report window at the BEAM Port boundary.

  A flow accepts only the next report sequence for its exact session and
  subscription owner. Reports release credit after that owner confirms final
  receiver admission, or after the native retirement barrier discards the
  retired stream's remaining deliveries. Only the contiguous consumed prefix
  produces a cumulative acknowledgement.

  State is bounded by 64 live streams, 64 outstanding reports and 1 MiB of
  encoded report data. Retired streams are deleted immediately; the greatest
  numeric stream identifier and cumulative counters are scalar generation
  state, not lifetime tombstones.
  """

  alias Wotex.BLE.BlueZ.Stream

  @uint64 0xFFFF_FFFF_FFFF_FFFF
  @frame_limit 64
  @byte_limit 1_048_576
  @line_limit 131_072

  @enforce_keys [:generation]
  defstruct generation: nil,
            greatest_stream: 0,
            last_sequence: 0,
            acknowledged_sequence: 0,
            acknowledged_bytes: 0,
            outstanding_bytes: 0,
            streams: %{},
            records: %{}

  @type t :: %__MODULE__{
          generation: String.t(),
          greatest_stream: non_neg_integer(),
          last_sequence: non_neg_integer(),
          acknowledged_sequence: non_neg_integer(),
          acknowledged_bytes: non_neg_integer(),
          outstanding_bytes: non_neg_integer(),
          streams: map(),
          records: map()
        }

  @doc false
  @spec new(String.t()) :: %__MODULE__{
          generation: String.t(),
          greatest_stream: 0,
          last_sequence: 0,
          acknowledged_sequence: 0,
          acknowledged_bytes: 0,
          outstanding_bytes: 0,
          streams: %{},
          records: %{}
        }
  def new(generation) when is_binary(generation), do: %__MODULE__{generation: generation}

  @doc false
  @spec open(t(), String.t(), pid(), pos_integer()) :: {:ok, t()} | :invalid
  def open(%__MODULE__{} = flow, id, owner, queue_limit)
      when is_pid(owner) and is_integer(queue_limit) and queue_limit in 1..10_000 do
    with {:ok, number} <- identifier(id),
         true <- number > flow.greatest_stream,
         true <- map_size(flow.streams) < @frame_limit do
      stream = %{owner: owner, last_sequence: 0, outstanding: 0, window: min(16, queue_limit)}

      {:ok,
       %{
         flow
         | greatest_stream: number,
           streams: Map.put(flow.streams, id, stream)
       }}
    else
      _ -> :invalid
    end
  end

  def open(_, _, _, _), do: :invalid

  @doc false
  @spec report(t(), map(), map(), pos_integer(), pid()) ::
          {:ok, term(), reference(), t()} | :invalid
  def report(%__MODULE__{} = flow, frame, binding, encoded_bytes, owner)
      when is_map(frame) and is_integer(encoded_bytes) and encoded_bytes in 1..@line_limit and
             is_pid(owner) do
    with %{
           "version" => 1,
           "session_generation" => generation,
           "report_sequence" => sequence,
           "subscription_id" => id,
           "generation" => 1,
           "event" => "value"
         } <- frame,
         true <- map_size(frame) == 8,
         true <- generation == flow.generation,
         true <- uint64(sequence) and sequence == flow.last_sequence + 1,
         true <- map_size(flow.records) < @frame_limit,
         true <- encoded_bytes <= @byte_limit - flow.outstanding_bytes,
         %{owner: ^owner, outstanding: outstanding, window: window} = stream <- flow.streams[id],
         true <- outstanding < window,
         {:ok, _, _} = event <-
           frame
           |> Map.drop(["session_generation", "report_sequence"])
           |> Stream.report(binding) do
      token = make_ref()

      record = %{
        bytes: encoded_bytes,
        consumed: false,
        owner: owner,
        stream: id,
        token: token
      }

      stream = %{stream | last_sequence: sequence, outstanding: outstanding + 1}

      {:ok, event, token,
       %{
         flow
         | last_sequence: sequence,
           outstanding_bytes: flow.outstanding_bytes + encoded_bytes,
           streams: Map.put(flow.streams, id, stream),
           records: Map.put(flow.records, sequence, record)
       }}
    else
      _ -> :invalid
    end
  end

  def report(_, _, _, _, _), do: :invalid

  @doc false
  @spec terminal(t(), map(), map(), pid()) :: {:ok, term()} | :invalid
  def terminal(%__MODULE__{} = flow, frame, binding, owner)
      when is_map(frame) and is_pid(owner) do
    with %{
           "version" => 1,
           "session_generation" => generation,
           "subscription_id" => id,
           "generation" => 1,
           "event" => "error"
         } <- frame,
         true <- map_size(frame) == 7,
         true <- generation == flow.generation,
         %{owner: ^owner} <- flow.streams[id],
         {:error, _} = event <- Map.delete(frame, "session_generation") |> Stream.report(binding) do
      {:ok, event}
    else
      _ -> :invalid
    end
  end

  def terminal(_, _, _, _), do: :invalid

  @doc false
  @spec consume(t(), pid(), pos_integer(), reference()) ::
          {:ok, map() | nil, t()} | :invalid
  def consume(%__MODULE__{} = flow, owner, sequence, token)
      when is_pid(owner) and is_integer(sequence) and is_reference(token) do
    case flow.records[sequence] do
      %{owner: ^owner, token: ^token} = record ->
        advance(%{flow | records: Map.put(flow.records, sequence, %{record | consumed: true})})

      _ ->
        {:ok, nil, flow}
    end
  end

  def consume(%__MODULE__{} = flow, _, _, _), do: {:ok, nil, flow}
  def consume(_, _, _, _), do: :invalid

  @doc false
  @spec retire(t(), map()) :: {:ok, String.t(), pid(), map() | nil, t()} | :invalid
  def retire(%__MODULE__{} = flow, frame) when is_map(frame) do
    with %{
           "version" => 1,
           "event" => "stream_retired",
           "session_generation" => generation,
           "subscription_id" => id,
           "generation" => 1,
           "last_report_sequence" => last_sequence
         } <- frame,
         true <- map_size(frame) == 6,
         true <- generation == flow.generation,
         true <- uint64(last_sequence),
         {:ok, _} <- identifier(id),
         {%{owner: owner, last_sequence: ^last_sequence}, streams} <- Map.pop(flow.streams, id) do
      records =
        Map.new(flow.records, fn
          {sequence, %{stream: ^id} = record} -> {sequence, %{record | consumed: true}}
          entry -> entry
        end)

      case advance(%{flow | streams: streams, records: records}) do
        {:ok, acknowledgement, updated} -> {:ok, id, owner, acknowledgement, updated}
        :invalid -> :invalid
      end
    else
      _ -> :invalid
    end
  end

  def retire(_, _), do: :invalid

  @doc false
  @spec active?(t(), String.t()) :: boolean()
  def active?(%__MODULE__{} = flow, id), do: Map.has_key?(flow.streams, id)

  defp advance(flow), do: advance(flow, false)

  defp advance(flow, changed) do
    sequence = flow.acknowledged_sequence + 1

    case flow.records[sequence] do
      %{consumed: true, bytes: bytes, stream: stream} ->
        if bytes > @uint64 - flow.acknowledged_bytes do
          :invalid
        else
          streams = decrement(flow.streams, stream)

          advance(
            %{
              flow
              | acknowledged_sequence: sequence,
                acknowledged_bytes: flow.acknowledged_bytes + bytes,
                outstanding_bytes: flow.outstanding_bytes - bytes,
                streams: streams,
                records: Map.delete(flow.records, sequence)
            },
            true
          )
        end

      _ when changed ->
        {:ok,
         %{
           "version" => 1,
           "event" => "report_ack",
           "session_generation" => flow.generation,
           "report_sequence" => flow.acknowledged_sequence,
           "acknowledged_bytes" => flow.acknowledged_bytes
         }, flow}

      _ ->
        {:ok, nil, flow}
    end
  end

  defp decrement(streams, id) do
    case streams[id] do
      %{outstanding: outstanding} = stream when outstanding > 0 ->
        Map.put(streams, id, %{stream | outstanding: outstanding - 1})

      _ ->
        streams
    end
  end

  defp identifier(id) when is_binary(id) and byte_size(id) in 1..20 do
    bytes = :binary.bin_to_list(id)

    with true <- Enum.all?(bytes, &(&1 in ?0..?9)),
         true <- not String.starts_with?(id, "0"),
         {number, ""} <- Integer.parse(id),
         true <- number in 1..@uint64 do
      {:ok, number}
    else
      _ -> :invalid
    end
  end

  defp identifier(_), do: :invalid
  defp uint64(value), do: is_integer(value) and value in 0..@uint64
end
