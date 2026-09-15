defmodule Wotex.Matter.Native.ReportLedger do
  @moduledoc """
  Tracks validated native reports until consumption or stream retirement.

  This internal immutable ledger bounds outstanding reports to 64 frames and
  1048576 encoded bytes. Stream identities include their delivery generation.
  An exact retirement barrier consumes only that stream's validated reports;
  reports for other streams continue to hold credit. Consumption tokens are
  supplied by the owning connection, so this module reads no clock or random
  source and starts no process.

  `advance/1` proposes the contiguous cumulative acknowledgement and a replacement
  ledger. The connection installs that ledger only after transmitting the ACK.
  Retained identities are bounded by active streams and outstanding reports.
  """

  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @derive {Inspect, only: [:next_sequence, :acknowledged_sequence, :acknowledged_bytes]}
  defstruct next_sequence: 1,
            acknowledged_sequence: 0,
            acknowledged_bytes: 0,
            pending: %{},
            streams: %{}

  @opaque t :: %__MODULE__{
            next_sequence: pos_integer(),
            acknowledged_sequence: non_neg_integer(),
            acknowledged_bytes: non_neg_integer(),
            pending: map(),
            streams: map()
          }

  @doc false
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc false
  @spec open(t(), term()) :: {:ok, t()} | :error
  def open(%__MODULE__{streams: streams} = ledger, stream) do
    if map_size(streams) < 128 and not Map.has_key?(streams, stream),
      do: {:ok, %{ledger | streams: Map.put(streams, stream, 0)}},
      else: :error
  end

  @doc false
  @spec register(t(), term(), pos_integer(), pos_integer(), reference()) :: {:ok, t()} | :error
  def register(%__MODULE__{} = ledger, stream, sequence, bytes, token)
      when is_integer(sequence) and sequence > 0 and sequence < @maximum_counter and
             is_integer(bytes) and bytes in 1..131_072 and is_reference(token) do
    retained_bytes = Enum.reduce(ledger.pending, 0, fn {_, report}, sum -> sum + report.bytes end)

    if sequence == ledger.next_sequence and Map.has_key?(ledger.streams, stream) and
         map_size(ledger.pending) < 64 and retained_bytes + bytes <= 1_048_576 and
         ledger.acknowledged_bytes + retained_bytes + bytes <= @maximum_counter do
      report = %{stream: stream, bytes: bytes, token: token, consumed: false}

      {:ok,
       %{
         ledger
         | next_sequence: sequence + 1,
           pending: Map.put(ledger.pending, sequence, report),
           streams: Map.put(ledger.streams, stream, sequence)
       }}
    else
      :error
    end
  end

  def register(_, _, _, _, _), do: :error

  @doc false
  @spec consume(t(), term(), pos_integer(), reference()) :: {:ok, t()} | :ignore
  def consume(%__MODULE__{} = ledger, stream, sequence, token) do
    case Map.fetch(ledger.pending, sequence) do
      {:ok, %{stream: ^stream, token: ^token, consumed: false}} ->
        {:ok, put_in(ledger.pending[sequence].consumed, true)}

      _ ->
        :ignore
    end
  end

  @doc false
  @spec retire(t(), term(), non_neg_integer()) :: {:ok, t()} | :error
  def retire(%__MODULE__{} = ledger, stream, last_sequence) do
    case Map.fetch(ledger.streams, stream) do
      {:ok, ^last_sequence} ->
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

  @doc false
  @spec advance(t()) ::
          {nil | %{report_sequence: pos_integer(), acknowledged_bytes: pos_integer()}, t()}
  def advance(%__MODULE__{} = ledger) do
    {sequence, bytes, pending} =
      consume_prefix(ledger.acknowledged_sequence + 1, ledger.acknowledged_bytes, ledger.pending)

    if sequence == ledger.acknowledged_sequence do
      {nil, ledger}
    else
      {%{report_sequence: sequence, acknowledged_bytes: bytes},
       %{ledger | acknowledged_sequence: sequence, acknowledged_bytes: bytes, pending: pending}}
    end
  end

  defp consume_prefix(sequence, bytes, pending) do
    case Map.fetch(pending, sequence) do
      {:ok, %{bytes: report_bytes, consumed: true}} ->
        consume_prefix(sequence + 1, bytes + report_bytes, Map.delete(pending, sequence))

      _ ->
        {sequence - 1, bytes, pending}
    end
  end
end
