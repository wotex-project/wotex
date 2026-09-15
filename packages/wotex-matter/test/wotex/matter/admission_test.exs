defmodule Wotex.Matter.AdmissionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.Native.Admission

  test "WMA-C03 admission and close capabilities retain exact identity and terminal state" do
    generation = "admission-generation"
    table = Admission.new(generation)
    deadline = System.monotonic_time(:millisecond) + 5_000

    try do
      assert {:error, :invalid_handle} = Admission.acquire(table, self(), "foreign", deadline)

      assert {:error, :invalid_handle} =
               Admission.acquire(table, spawn(fn -> :ok end), generation, deadline)

      non_table = :atomics.new(1, signed: false)

      assert {:error, :transport_closed} =
               Admission.acquire(non_table, self(), generation, deadline)

      assert {:error, :transport_closed} =
               Admission.begin_close(non_table, self(), generation, deadline)

      assert {:first, close_token} =
               Admission.begin_close(table, self(), generation, deadline)

      assert Admission.close_failure(table, deadline - 1) == nil
      assert Admission.close_owned?(table, close_token, self(), deadline)
      refute Admission.close_owned?(table, close_token, self(), deadline + 1)
      refute Admission.close_owned?(table, make_ref(), self(), deadline)
      assert Admission.begin_close(table, self(), generation, deadline) == :waiting
      assert {:error, :transport_closed} = Admission.acquire(table, self(), generation, deadline)

      :ets.delete(table, :closing)
      assert {:ok, lease} = Admission.acquire(table, self(), generation, deadline)
      assert Admission.owned?(table, lease, self(), deadline)
      assert [{^lease, owner, ^deadline}] = Admission.reservations(table)
      assert owner == self()

      assert Admission.mark_submission(nil) == :ok
      assert Admission.clear_submission(nil) == :ok
      assert Admission.mark_submission(lease) == :ok
      assert Admission.cancel_unsubmitted(lease) == :submitted
      assert Admission.clear_submission(lease) == :ok
      assert Admission.mark_submission(lease) == :cancelled
      assert Admission.cancel_unsubmitted(lease) == :cancelled

      assert Admission.clear_submission({1, make_ref()}) == :ok
      assert Admission.cancel_unsubmitted({1, make_ref()}) == :cancelled
      assert Admission.release(non_table, {1, make_ref()}) == :ok

      Admission.release(table, lease)
      refute Admission.owned?(table, lease, self(), deadline)

      parent = self()

      caller =
        spawn(fn ->
          send(parent, {:close, self(), Admission.begin_close(table, parent, generation, deadline)})
          Process.sleep(:infinity)
        end)

      assert_receive {:close, ^caller, {:first, _}}
      Process.exit(caller, :kill)
      assert eventually(fn -> Admission.close_failure(table, deadline - 1) == :owner_closed end)

      :ets.delete(table, :closing)

      assert {:first, _} =
               Admission.begin_close(
                 table,
                 self(),
                 generation,
                 System.monotonic_time(:millisecond) - 1
               )

      assert Admission.close_failure(table, System.monotonic_time(:millisecond)) == :timeout
    after
      :ets.delete(table)
    end

    assert {:error, :transport_closed} = Admission.acquire(table, self(), generation, deadline)
    assert {:error, :transport_closed} = Admission.begin_close(table, self(), generation, deadline)
    assert Admission.release(table, {1, make_ref()}) == :ok
  end

  defp eventually(function, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(5)
      eventually(function, attempts - 1)
    end
  end
end
