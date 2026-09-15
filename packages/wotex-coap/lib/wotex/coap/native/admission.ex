defmodule Wotex.CoAP.Native.Admission do
  @moduledoc """
  Reserves bounded call slots before a native connection receives work.

  Each native generation owns one unnamed ETS table with 64 ordinary slots.
  Atomic insertion bounds concurrent callers before their GenServer messages
  enter the connection mailbox. A reservation records its caller and absolute
  deadline. Once submitted, the slot remains occupied until the connection
  consumes the message, even when the caller has already timed out.

  A separate closing record reserves control capacity and prevents new ordinary
  admission. Each ordinary lease also owns an atomic submission marker. The
  marker lets a caller distinguish cancellation before Port submission from a
  request that may already have reached native code. Table ownership and the
  positive uint64 generation bind every capability to one connection process;
  process termination removes the complete table.
  """

  @maximum_generation 0xFFFFFFFFFFFFFFFF
  @maximum_slots 64
  @first_unavailable_slot @maximum_slots + 1

  @typedoc "One ordinary native-call reservation."
  @type lease :: {1..64, :atomics.atomics_ref()}

  @doc false
  @spec new(1..0xFFFFFFFFFFFFFFFF) :: atom() | :ets.tid()
  def new(generation) when is_integer(generation) and generation in 1..@maximum_generation do
    table = :ets.new(__MODULE__, [:set, :public, read_concurrency: true, write_concurrency: true])
    true = :ets.insert(table, {:identity, self(), generation})
    table
  end

  @doc false
  @spec acquire(term(), pid(), pos_integer(), integer()) ::
          {:ok, lease()} | {:error, :busy | :invalid_handle | :transport_closed}
  def acquire(table, owner, generation, deadline) do
    with :ok <- validate_identity(table, owner, generation) do
      if closing?(table),
        do: {:error, :transport_closed},
        else: reserve(table, deadline, 1)
    end
  rescue
    ArgumentError -> {:error, :transport_closed}
  end

  @doc false
  @spec begin_close(term(), pid(), pos_integer(), integer()) ::
          {:first, reference()} | :waiting | {:error, :invalid_handle | :transport_closed}
  def begin_close(table, owner, generation, deadline) do
    with :ok <- validate_identity(table, owner, generation) do
      token = make_ref()

      if :ets.insert_new(table, {:closing, token, self(), deadline}),
        do: {:first, token},
        else: :waiting
    end
  rescue
    ArgumentError -> {:error, :transport_closed}
  end

  @doc false
  @spec closing?(:ets.tid()) :: boolean()
  def closing?(table), do: :ets.member(table, :closing)

  @doc false
  @spec close_owned?(:ets.tid(), reference(), pid(), integer()) :: boolean()
  def close_owned?(table, token, caller, deadline),
    do: :ets.lookup(table, :closing) == [{:closing, token, caller, deadline}]

  @doc false
  @spec close_failure(:ets.tid(), integer()) :: :owner_closed | :timeout | nil
  def close_failure(table, now) do
    case :ets.lookup(table, :closing) do
      [{:closing, _, caller, deadline}] ->
        cond do
          not Process.alive?(caller) -> :owner_closed
          deadline <= now -> :timeout
          true -> nil
        end

      [] ->
        nil
    end
  end

  @doc false
  @spec reservations(:ets.tid()) :: [{lease(), pid(), integer()}]
  def reservations(table) do
    for {slot, token, caller, deadline} <- :ets.tab2list(table),
        slot in 1..@maximum_slots,
        do: {{slot, token}, caller, deadline}
  end

  @doc false
  @spec owned?(term(), lease(), pid(), integer()) :: boolean()
  def owned?(table, {slot, token}, caller, deadline),
    do: :ets.lookup(table, slot) == [{slot, token, caller, deadline}]

  @doc false
  @spec release(term(), lease()) :: :ok
  def release(table, {slot, token}) do
    :ets.select_delete(table, [{{slot, token, :_, :_}, [], [true]}])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  @spec mark_submission(lease() | nil) :: :ok | :cancelled
  def mark_submission(nil), do: :ok

  def mark_submission({_, token}) do
    case :atomics.compare_exchange(token, 1, 0, 1) do
      :ok -> :ok
      _ -> :cancelled
    end
  end

  @doc false
  @spec clear_submission(lease() | nil) :: :ok
  def clear_submission(nil), do: :ok

  def clear_submission({_, token}) do
    :atomics.put(token, 1, 2)
  rescue
    ArgumentError -> :ok
  end

  @doc false
  @spec cancel_unsubmitted(lease()) :: :submitted | :cancelled
  def cancel_unsubmitted({_, token}) do
    case :atomics.compare_exchange(token, 1, 0, 2) do
      1 -> :submitted
      _ -> :cancelled
    end
  rescue
    ArgumentError -> :cancelled
  end

  defp reserve(_, _, @first_unavailable_slot), do: {:error, :busy}

  defp reserve(table, deadline, slot) do
    if :ets.member(table, slot),
      do: reserve(table, deadline, slot + 1),
      else: reserve_empty(table, deadline, slot)
  end

  defp reserve_empty(table, deadline, slot) do
    token = :atomics.new(1, signed: false)

    if :ets.insert_new(table, {slot, token, self(), deadline}) do
      if closing?(table) do
        release(table, {slot, token})
        {:error, :transport_closed}
      else
        {:ok, {slot, token}}
      end
    else
      reserve(table, deadline, slot + 1)
    end
  end

  defp validate_identity(table, owner, generation) do
    case :ets.info(table, :owner) do
      ^owner ->
        if :ets.lookup(table, :identity) == [{:identity, owner, generation}],
          do: :ok,
          else: {:error, :invalid_handle}

      :undefined ->
        if is_reference(table),
          do: {:error, :transport_closed},
          else: {:error, :invalid_handle}

      _ ->
        {:error, :invalid_handle}
    end
  end
end
