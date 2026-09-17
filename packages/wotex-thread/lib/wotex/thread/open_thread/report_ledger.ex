defmodule Wotex.Thread.OpenThread.ReportLedger do
  @moduledoc """
  Tracks validated native reports until delivery admission or stream retirement.

  The native host transmits a report only while it holds session frame and byte
  credit. This immutable ledger is the BEAM side of that contract: it admits
  exactly the next report sequence for a live stream, bounds outstanding reports
  to 64 frames, 1048576 encoded bytes and `min(16, queue_limit)` per stream, and
  records each report's exact encoded length including its newline.

  A report counts toward the cumulative acknowledgement only after its stream
  owner admits delivery with the matching token, or after an exact retirement
  barrier discards that stream's validated reports. `advance/1` proposes the
  contiguous acknowledged prefix and the ledger to install once the
  `report_ack` frame has been written. A retired stream is deleted immediately,
  so a later report or second barrier for it is an invalid channel.

  Callers supply stream identities and consumption tokens. The module reads no
  clock or random source and starts no process.
  """

  @maximum_sequence 0xFFFFFFFFFFFFFFFE
  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @session_frames 64
  @session_bytes 1_048_576
  @stream_frames 16
  @maximum_line 131_072
  @live_streams 64

  @derive {Inspect, only: [:next_sequence, :acknowledged_sequence, :acknowledged_bytes]}
  defstruct next_sequence: 1,
            acknowledged_sequence: 0,
            acknowledged_bytes: 0,
            retained_bytes: 0,
            pending: %{},
            streams: %{}

  @typedoc "A subscription identity and its delivery generation."
  @type stream :: {String.t(), pos_integer()}

  @typedoc "A proposed cumulative acknowledgement."
  @type acknowledgement :: %{report_sequence: pos_integer(), acknowledged_bytes: pos_integer()}

  @opaque t :: %__MODULE__{
            next_sequence: pos_integer(),
            acknowledged_sequence: non_neg_integer(),
            acknowledged_bytes: non_neg_integer(),
            retained_bytes: non_neg_integer(),
            pending: map(),
            streams: map()
          }

  @doc "Returns an empty ledger for one IPC session generation."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Opens a live stream with its validated native queue limit."
  @spec open(t(), stream(), 1..10_000) :: {:ok, t()} | :error
  def open(%__MODULE__{streams: streams} = ledger, {id, generation} = stream, queue_limit)
      when is_binary(id) and byte_size(id) in 1..64 and is_integer(generation) and
             generation > 0 and is_integer(queue_limit) and queue_limit in 1..10_000 do
    if map_size(streams) < @live_streams and not Map.has_key?(streams, stream) do
      record = %{last: 0, outstanding: 0, limit: min(@stream_frames, queue_limit)}
      {:ok, %{ledger | streams: Map.put(streams, stream, record)}}
    else
      :error
    end
  end

  def open(_, _, _), do: :error

  @doc "Registers the next transmitted report for a live stream."
  @spec register(t(), stream(), pos_integer(), pos_integer(), reference()) :: {:ok, t()} | :error
  def register(%__MODULE__{} = ledger, stream, sequence, bytes, token)
      when is_integer(sequence) and sequence in 1..@maximum_sequence and is_integer(bytes) and
             bytes in 2..@maximum_line and is_reference(token) do
    with true <- sequence == ledger.next_sequence,
         {:ok, record} <- Map.fetch(ledger.streams, stream),
         true <- record.outstanding < record.limit,
         true <- map_size(ledger.pending) < @session_frames,
         true <- ledger.retained_bytes + bytes <= @session_bytes,
         true <- ledger.acknowledged_bytes + ledger.retained_bytes + bytes <= @maximum_counter do
      report = %{stream: stream, bytes: bytes, token: token, consumed: false}
      record = %{record | last: sequence, outstanding: record.outstanding + 1}

      {:ok,
       %{
         ledger
         | next_sequence: sequence + 1,
           retained_bytes: ledger.retained_bytes + bytes,
           pending: Map.put(ledger.pending, sequence, report),
           streams: Map.put(ledger.streams, stream, record)
       }}
    else
      _ -> :error
    end
  end

  def register(_, _, _, _, _), do: :error

  @doc "Marks one report consumed when its stream and token match an unconsumed record."
  @spec consume(t(), stream(), pos_integer(), reference()) :: {:ok, t()} | :ignore
  def consume(%__MODULE__{} = ledger, stream, sequence, token) do
    case Map.fetch(ledger.pending, sequence) do
      {:ok, %{stream: ^stream, token: ^token, consumed: false}} ->
        {:ok, put_in(ledger.pending[sequence].consumed, true)}

      _ ->
        :ignore
    end
  end

  @doc "Applies an exact retirement barrier, discarding that stream's validated reports."
  @spec retire(t(), stream(), non_neg_integer()) :: {:ok, t()} | :error
  def retire(%__MODULE__{} = ledger, stream, last_sequence) do
    case Map.fetch(ledger.streams, stream) do
      {:ok, %{last: ^last_sequence}} ->
        pending =
          Map.new(ledger.pending, fn
            {sequence, %{stream: ^stream} = report} -> {sequence, %{report | consumed: true}}
            entry -> entry
          end)

        {:ok, %{ledger | pending: pending, streams: Map.delete(ledger.streams, stream)}}

      _ ->
        :error
    end
  end

  @doc "Returns whether a stream is live in this ledger."
  @spec live?(t(), stream()) :: boolean()
  def live?(%__MODULE__{streams: streams}, stream), do: Map.has_key?(streams, stream)

  @doc "Proposes the contiguous cumulative acknowledgement and its replacement ledger."
  @spec advance(t()) :: {nil | acknowledgement(), t()}
  def advance(%__MODULE__{} = ledger) do
    case prefix(ledger, ledger.acknowledged_sequence + 1) do
      ^ledger ->
        {nil, ledger}

      advanced ->
        {%{
           report_sequence: advanced.acknowledged_sequence,
           acknowledged_bytes: advanced.acknowledged_bytes
         }, advanced}
    end
  end

  defp prefix(ledger, sequence) do
    case Map.fetch(ledger.pending, sequence) do
      {:ok, %{consumed: true} = report} ->
        # A retired stream has already been deleted with its discarded reports.
        stream = report.stream

        streams =
          case ledger.streams do
            %{^stream => record} ->
              Map.put(ledger.streams, stream, %{record | outstanding: record.outstanding - 1})

            streams ->
              streams
          end

        prefix(
          %{
            ledger
            | acknowledged_sequence: sequence,
              acknowledged_bytes: ledger.acknowledged_bytes + report.bytes,
              retained_bytes: ledger.retained_bytes - report.bytes,
              pending: Map.delete(ledger.pending, sequence),
              streams: streams
          },
          sequence + 1
        )

      _ ->
        ledger
    end
  end
end
