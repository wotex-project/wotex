defmodule Wotex.Matter.Native.Admission do
  @moduledoc """
  Reserves bounded request slots before a native connection receives a call.

  Each explicitly started connection owns one unnamed ETS table with 64 slots.
  Atomic insertion bounds concurrent callers without starting another process.
  The connection releases a slot only after it has consumed the corresponding
  call, so a caller timeout cannot free capacity while its message remains queued.
  Table ownership and session generation bind this internal capability to one
  connection; process termination deletes the table and every reservation.
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
  def acquire(table, owner, generation, deadline) when is_reference(table) do
    case :ets.info(table, :owner) do
      ^owner ->
        if :ets.lookup(table, :identity) == [{:identity, owner, generation}],
          do: reserve(table, deadline, 1),
          else: {:error, :invalid_handle}

      :undefined ->
        {:error, :transport_closed}

      _ ->
        {:error, :invalid_handle}
    end
  rescue
    ArgumentError -> {:error, :transport_closed}
  end

  def acquire(_, _, _, _), do: {:error, :invalid_handle}

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

    if :ets.insert_new(table, {slot, token, self(), deadline}),
      do: {:ok, {slot, token}},
      else: reserve(table, deadline, slot + 1)
  end
end
