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
  """

  @type lease :: {1..64, reference()}

  @doc false
  @spec new(String.t()) :: :ets.tid()
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
  @spec begin_close(term(), pid(), String.t()) ::
          {:first, reference()} | :waiting | {:error, atom()}
  def begin_close(table, owner, generation) do
    with :ok <- validate_identity(table, owner, generation) do
      token = make_ref()
      if :ets.insert_new(table, {:closing, token}), do: {:first, token}, else: :waiting
    end
  rescue
    ArgumentError -> {:error, :transport_closed}
  end

  @doc false
  @spec closing?(:ets.tid()) :: boolean()
  def closing?(table), do: :ets.member(table, :closing)

  @doc false
  @spec close_owned?(:ets.tid(), reference()) :: boolean()
  def close_owned?(table, token), do: :ets.lookup(table, :closing) == [{:closing, token}]

  @doc false
  @spec owned?(term(), lease(), pid(), integer()) :: boolean()
  def owned?(table, {slot, token}, caller, deadline),
    do: :ets.lookup(table, slot) == [{slot, token, caller, deadline}]

  @doc false
  @spec release(:ets.tid(), lease()) :: :ok
  def release(table, {slot, token}) do
    :ets.select_delete(table, [{{slot, token, :_, :_}, [], [true]}])
    :ok
  end

  defp reserve(_, _, 65), do: {:error, :busy}

  defp reserve(table, deadline, slot) do
    token = make_ref()

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

  defp validate_identity(table, owner, generation) when is_reference(table) do
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

  defp validate_identity(_, _, _), do: {:error, :invalid_handle}
end
