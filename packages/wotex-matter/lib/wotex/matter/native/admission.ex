defmodule Wotex.Matter.Native.Admission do
  @moduledoc """
  Reserves bounded request slots before a native connection receives a call.

  Each explicitly started connection owns one unnamed ETS table with 64 slots.
  Atomic insertion bounds concurrent callers without starting another process.
  Once submitted, a call keeps its slot until the connection consumes it, so a
  caller timeout cannot free capacity while its message remains queued.
  Table ownership and session generation bind this internal capability to one
  connection; process termination deletes the table and every reservation.

  A separate atomic closing record reserves one control message and prevents new
  ordinary requests. Concurrent close callers wait on the connection's lifetime
  instead of sending more close messages or retaining another owner-side queue.
  A reservation racing with closing is released before it submits its call.
  Reservations retain their caller and deadline before message submission so the
  connection can reclaim an abandoned slot or terminate an abandoned close.
  Each token also holds an atomic submission marker. The caller retains that
  marker after connection and table death, so it can distinguish queued work
  from a mutation whose Port submission may already have reached native code.
  Cancellation atomically prevents an unsubmitted token from being submitted
  after its caller has returned a failure with no effect.
  """

  @type lease :: {1..64, :atomics.atomics_ref()}

  @doc false
  @spec new(String.t()) :: :ets.tid() | atom()
  def new(generation) do
    table = :ets.new(__MODULE__, [:set, :public, read_concurrency: true, write_concurrency: true])
    true = :ets.insert(table, {:identity, self(), generation})
    table
  end

  @doc false
  @spec acquire(term(), pid(), String.t(), integer()) :: {:ok, lease()} | {:error, atom()}
  def acquire(table, owner, generation, deadline) do
    with :ok <- validate_identity(table, owner, generation) do
      if closing?(table), do: {:error, :transport_closed}, else: reserve(table, deadline, 1)
    end
  rescue
    ArgumentError -> {:error, :transport_closed}
  end

  @doc false
  @spec begin_close(term(), pid(), String.t(), integer()) ::
          {:first, reference()} | :waiting | {:error, atom()}
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
        slot in 1..64,
        do: {{slot, token}, caller, deadline}
  end

  @doc false
  @spec owned?(term(), lease(), pid(), integer()) :: boolean()
  def owned?(table, {slot, token}, caller, deadline),
    do: :ets.lookup(table, slot) == [{slot, token, caller, deadline}]

  @doc false
  @spec release(:ets.tid(), lease()) :: :ok
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

  defp reserve(_, _, 65), do: {:error, :busy}

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
    if is_reference(table),
      do: validate_table_identity(table, owner, generation),
      else: {:error, :invalid_handle}
  end

  defp validate_table_identity(table, owner, generation) do
    case :ets.info(table, :owner) do
      ^owner ->
        if :ets.lookup(table, :identity) == [{:identity, owner, generation}],
          do: :ok,
          else: {:error, :invalid_handle}

      :undefined ->
        {:error, :transport_closed}

      _ ->
        {:error, :invalid_handle}
    end
  end
end
