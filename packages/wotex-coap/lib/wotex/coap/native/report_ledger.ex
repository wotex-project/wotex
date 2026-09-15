defmodule Wotex.CoAP.Native.ReportLedger do
  @moduledoc """
  Tracks validated native OSCORE report frames until cumulative credit succeeds.

  One ledger belongs to one established subscription generation. It accepts only
  the next report sequence and retains at most eight newline-terminated frames
  totaling 1 MiB. Body frames may be accounted immediately after bounded
  assembly accepts them. Complete reports remain unconsumed until the owner has
  admitted their public delivery.

  `next_credit/1` proposes only the contiguous consumed prefix. The proposal
  remains in flight until `credit_accepted/2` records the successful native
  response, so an owner cannot issue two credit commands concurrently. This
  module reads no clock and starts no process.
  """

  @maximum_counter 0xFFFFFFFFFFFFFFFF
  @maximum_frames 8
  @maximum_line_bytes 131_072
  @maximum_outstanding_bytes 1_048_576

  @derive {
    Inspect,
    only: [
      :generation,
      :started,
      :last_sequence,
      :acknowledged_sequence,
      :outstanding_bytes,
      :credit_in_flight
    ]
  }
  @enforce_keys [:subscription_id, :generation]
  defstruct subscription_id: nil,
            generation: nil,
            started: false,
            last_sequence: 0,
            acknowledged_sequence: 0,
            outstanding_bytes: 0,
            records: %{},
            credit_in_flight: nil

  @opaque t :: %__MODULE__{
            subscription_id: String.t(),
            generation: pos_integer(),
            started: boolean(),
            last_sequence: non_neg_integer(),
            acknowledged_sequence: non_neg_integer(),
            outstanding_bytes: non_neg_integer(),
            records: map(),
            credit_in_flight: nil | {non_neg_integer(), non_neg_integer()}
          }

  @typedoc "The exact parameters for one native `credit` command."
  @type credit :: %{generation: pos_integer(), ack_seq: non_neg_integer()}

  @doc "Creates a ledger for one established subscription generation."
  @spec new(term(), term()) :: {:ok, t()} | :error
  def new(subscription_id, generation)
      when is_integer(generation) and generation in 1..@maximum_counter do
    if identifier?(subscription_id),
      do: {:ok, %__MODULE__{subscription_id: subscription_id, generation: generation}},
      else: :error
  end

  def new(_, _), do: :error

  @doc "Accounts a validated body frame inside the owner's bounded assembly state."
  @spec account_frame(t(), term(), term(), term(), term()) :: {:ok, t()} | :error
  def account_frame(ledger, subscription_id, generation, sequence, encoded_bytes) do
    register(
      ledger,
      subscription_id,
      generation,
      sequence,
      encoded_bytes,
      %{kind: :body, token: nil, consumed: true}
    )
  end

  @doc "Retains one complete report until its exact delivery token is consumed."
  @spec retain_report(t(), term(), term(), term(), term(), term()) :: {:ok, t()} | :error
  def retain_report(
        %__MODULE__{} = ledger,
        subscription_id,
        generation,
        sequence,
        encoded_bytes,
        token
      )
      when is_reference(token) do
    if queued_report?(ledger) do
      :error
    else
      register(
        ledger,
        subscription_id,
        generation,
        sequence,
        encoded_bytes,
        %{kind: :report, token: token, consumed: false}
      )
    end
  end

  def retain_report(_, _, _, _, _, _), do: :error

  @doc "Marks an exact retained report consumed after public delivery admission."
  @spec consume_report(t(), term(), term(), term(), term()) :: {:ok, t()} | :ignore | :error
  def consume_report(
        %__MODULE__{subscription_id: subscription_id, generation: generation} = ledger,
        subscription_id,
        generation,
        sequence,
        token
      )
      when is_integer(sequence) and is_reference(token) do
    case ledger.records[sequence] do
      %{kind: :report, token: ^token, consumed: false} = record ->
        {:ok, %{ledger | records: Map.put(ledger.records, sequence, %{record | consumed: true})}}

      _ ->
        :ignore
    end
  end

  def consume_report(%__MODULE__{}, _, _, _, _), do: :ignore
  def consume_report(_, _, _, _, _), do: :error

  @doc "Proposes the initial window or the next contiguous cumulative acknowledgment."
  @spec next_credit(t()) :: {:ok, credit() | nil, t()} | :error
  def next_credit(
        %__MODULE__{
          started: false,
          last_sequence: 0,
          acknowledged_sequence: 0,
          outstanding_bytes: 0,
          records: records,
          credit_in_flight: nil
        } = ledger
      )
      when map_size(records) == 0 do
    credit = %{generation: ledger.generation, ack_seq: 0}
    {:ok, credit, %{ledger | credit_in_flight: {0, 0}}}
  end

  def next_credit(%__MODULE__{started: true, credit_in_flight: nil} = ledger) do
    {sequence, bytes} = consumed_prefix(ledger, ledger.acknowledged_sequence + 1, 0)

    if sequence == ledger.acknowledged_sequence do
      {:ok, nil, ledger}
    else
      credit = %{generation: ledger.generation, ack_seq: sequence}
      {:ok, credit, %{ledger | credit_in_flight: {sequence, bytes}}}
    end
  end

  def next_credit(%__MODULE__{credit_in_flight: {_, _}} = ledger),
    do: {:ok, nil, ledger}

  def next_credit(%__MODULE__{}), do: :error
  def next_credit(_), do: :error

  @doc "Commits the exact cumulative acknowledgment after its native success response."
  @spec credit_accepted(t(), term()) :: {:ok, t()} | :error
  def credit_accepted(
        %__MODULE__{
          started: false,
          last_sequence: 0,
          acknowledged_sequence: 0,
          outstanding_bytes: 0,
          records: records,
          credit_in_flight: {0, 0}
        } = ledger,
        0
      )
      when map_size(records) == 0,
      do: {:ok, %{ledger | started: true, credit_in_flight: nil}}

  def credit_accepted(
        %__MODULE__{
          started: true,
          acknowledged_sequence: acknowledged,
          outstanding_bytes: outstanding,
          credit_in_flight: {sequence, bytes}
        } = ledger,
        sequence
      )
      when sequence > acknowledged and bytes >= 1 and bytes <= outstanding do
    records = Map.reject(ledger.records, fn {number, _} -> number <= sequence end)

    {:ok,
     %{
       ledger
       | acknowledged_sequence: sequence,
         outstanding_bytes: outstanding - bytes,
         records: records,
         credit_in_flight: nil
     }}
  end

  def credit_accepted(_, _), do: :error

  defp register(
         %__MODULE__{subscription_id: subscription_id, generation: generation} = ledger,
         subscription_id,
         generation,
         sequence,
         encoded_bytes,
         record
       )
       when is_integer(sequence) and is_integer(encoded_bytes) and
              encoded_bytes in 1..@maximum_line_bytes do
    if ledger.started and ledger.last_sequence < @maximum_counter and
         sequence == ledger.last_sequence + 1 and map_size(ledger.records) < @maximum_frames and
         encoded_bytes <= @maximum_outstanding_bytes - ledger.outstanding_bytes do
      record = Map.put(record, :bytes, encoded_bytes)

      {:ok,
       %{
         ledger
         | last_sequence: sequence,
           outstanding_bytes: ledger.outstanding_bytes + encoded_bytes,
           records: Map.put(ledger.records, sequence, record)
       }}
    else
      :error
    end
  end

  defp register(_, _, _, _, _, _), do: :error

  defp consumed_prefix(ledger, sequence, bytes) do
    case ledger.records[sequence] do
      %{bytes: frame_bytes, consumed: true} ->
        consumed_prefix(ledger, sequence + 1, bytes + frame_bytes)

      _ ->
        {sequence - 1, bytes}
    end
  end

  defp queued_report?(ledger) do
    Enum.any?(ledger.records, fn
      {_, %{kind: :report, consumed: false}} -> true
      _ -> false
    end)
  end

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..64,
    do: Enum.all?(:binary.bin_to_list(value), &(&1 in 0x20..0x7E))

  defp identifier?(_), do: false
end
