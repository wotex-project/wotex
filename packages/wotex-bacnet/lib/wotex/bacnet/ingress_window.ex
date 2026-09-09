defmodule Wotex.BACnet.IngressWindow do
  @moduledoc """
  Accounts for datagrams awaiting consumption in one owned transport generation.

  Eight receipt references cover the complete transport-to-client pipeline.
  Forwarding a receipt does not release its slot. Only consumption of an
  outstanding reference in the same generation does so; repeated and unrelated
  acknowledgments leave capacity unchanged. Filling the window starts a fixed
  100 millisecond starvation deadline, which consumption clears.

  The transport supplies references and monotonic times explicitly. This value
  neither receives packets nor starts timers. Its fixed reason counters saturate
  at the unsigned 64-bit maximum, so malformed traffic cannot grow diagnostic
  state or introduce peer-controlled keys. Operating-system packet loss is a
  separate measurement and is never inferred from these counters.
  """

  @limit 8
  @max_counter 18_446_744_073_709_551_615
  @reasons [:oversize, :malformed, :ignored_ack, :rejected, :self_packet, :socket_error]
  @enforce_keys [:generation]
  defstruct [:generation, :starved_at, outstanding: MapSet.new(), peak: 0, counters: %{}]

  @type reason :: :oversize | :malformed | :ignored_ack | :rejected | :self_packet | :socket_error
  @type t :: %__MODULE__{
          generation: reference(),
          outstanding: MapSet.t(reference()),
          starved_at: integer() | nil,
          peak: non_neg_integer(),
          counters: %{reason() => non_neg_integer()}
        }

  @doc "Creates a finite receipt window for the supplied transport generation."
  @spec new(reference()) :: t()
  def new(generation) when is_reference(generation),
    do: %__MODULE__{generation: generation, counters: Map.new(@reasons, &{&1, 0})}

  @doc "Returns the number of additional datagrams the pipeline may admit."
  @spec available(t()) :: 0..8
  def available(%__MODULE__{} = window), do: @limit - MapSet.size(window.outstanding)

  @doc "Reserves a fresh receipt, or rejects duplicate and full-window admission."
  @spec admit(t(), reference(), integer()) :: {:ok, t()} | {:error, :busy | :duplicate_receipt}
  def admit(%__MODULE__{} = window, receipt, now)
      when is_reference(receipt) and is_integer(now) do
    cond do
      MapSet.member?(window.outstanding, receipt) ->
        {:error, :duplicate_receipt}

      available(window) == 0 ->
        {:error, :busy}

      true ->
        outstanding = MapSet.put(window.outstanding, receipt)
        count = MapSet.size(outstanding)

        {:ok,
         %{
           window
           | outstanding: outstanding,
             peak: max(window.peak, count),
             starved_at: if(count == @limit, do: now, else: nil)
         }}
    end
  end

  @doc "Releases an outstanding receipt once; invalid acknowledgments consume no capacity."
  @spec consume(t(), term(), term()) :: t()
  def consume(%__MODULE__{generation: generation} = window, generation, receipt) do
    if MapSet.member?(window.outstanding, receipt),
      do: %{window | outstanding: MapSet.delete(window.outstanding, receipt), starved_at: nil},
      else: count(window, :ignored_ack)
  end

  def consume(%__MODULE__{} = window, _, _), do: count(window, :ignored_ack)

  @doc "Reports whether the uninterrupted full-window deadline has expired."
  @spec expired?(t(), integer()) :: boolean()
  def expired?(%__MODULE__{starved_at: nil}, _), do: false
  def expired?(%__MODULE__{starved_at: started}, now), do: now >= started + 100

  @doc "Increments one fixed diagnostic reason without overflowing its uint64 bound."
  @spec count(t(), reason()) :: t()
  def count(%__MODULE__{} = window, reason) when reason in @reasons do
    %{window | counters: Map.update!(window.counters, reason, &min(&1 + 1, @max_counter))}
  end
end
