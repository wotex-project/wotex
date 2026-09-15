defmodule Wotex.CoAP.NativeAdmissionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.Native.Admission

  @generation 17

  test "WCO-N02 leases retain exact connection identity and submission state" do
    table = Admission.new(@generation)
    deadline = System.monotonic_time(:millisecond) + 5_000

    try do
      assert {:error, :invalid_handle} = Admission.acquire(table, self(), 18, deadline)

      assert {:error, :invalid_handle} =
               Admission.acquire(table, spawn(fn -> :ok end), @generation, deadline)

      non_table = :atomics.new(1, signed: false)

      assert {:error, :transport_closed} =
               Admission.acquire(non_table, self(), @generation, deadline)

      assert {:error, :transport_closed} =
               Admission.begin_close(non_table, self(), @generation, deadline)

      assert {:ok, lease} = Admission.acquire(table, self(), @generation, deadline)
      assert Admission.owned?(table, lease, self(), deadline)
      assert [{^lease, owner, ^deadline}] = Admission.reservations(table)
      assert owner == self()

      assert :ok = Admission.mark_submission(nil)
      assert :ok = Admission.clear_submission(nil)
      assert :ok = Admission.mark_submission(lease)
      assert :submitted = Admission.cancel_unsubmitted(lease)
      assert :ok = Admission.clear_submission(lease)
      assert :cancelled = Admission.mark_submission(lease)
      assert :cancelled = Admission.cancel_unsubmitted(lease)

      assert :ok = Admission.clear_submission({1, make_ref()})
      assert :cancelled = Admission.cancel_unsubmitted({1, make_ref()})
      assert :ok = Admission.release(non_table, {1, make_ref()})

      assert :ok = Admission.release(table, lease)
      refute Admission.owned?(table, lease, self(), deadline)
    after
      :ets.delete(table)
    end

    assert {:error, :transport_closed} = Admission.acquire(table, self(), @generation, deadline)
    assert {:error, :transport_closed} = Admission.begin_close(table, self(), @generation, deadline)
  end

  test "WCO-N02 exactly 64 concurrent ordinary leases are admitted" do
    table = Admission.new(@generation)
    deadline = System.monotonic_time(:millisecond) + 5_000
    parent = self()

    callers =
      for _ <- 1..96 do
        spawn(fn ->
          result = Admission.acquire(table, parent, @generation, deadline)
          send(parent, {:admission, self(), result})
          Process.sleep(:infinity)
        end)
      end

    results =
      for caller <- callers do
        assert_receive {:admission, ^caller, result}
        result
      end

    leases = for {:ok, lease} <- results, do: lease
    assert length(leases) == 64
    assert Enum.count(results, &(&1 == {:error, :busy})) == 32
    assert length(Admission.reservations(table)) == 64

    Enum.each(leases, &Admission.release(table, &1))
    assert Admission.reservations(table) == []
    Enum.each(callers, &Process.exit(&1, :kill))
    :ets.delete(table)
  end

  test "WCO-N02 close control is separate, singular and terminal for ordinary admission" do
    table = Admission.new(@generation)
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert {:first, token} = Admission.begin_close(table, self(), @generation, deadline)
    assert Admission.close_owned?(table, token, self(), deadline)
    refute Admission.close_owned?(table, token, self(), deadline + 1)
    refute Admission.close_owned?(table, make_ref(), self(), deadline)
    assert :waiting = Admission.begin_close(table, self(), @generation, deadline)
    assert {:error, :transport_closed} = Admission.acquire(table, self(), @generation, deadline)
    assert Admission.close_failure(table, deadline - 1) == nil

    :ets.delete(table, :closing)
    parent = self()

    caller =
      spawn(fn ->
        send(parent, {:close, self(), Admission.begin_close(table, parent, @generation, deadline)})
        Process.sleep(:infinity)
      end)

    assert_receive {:close, ^caller, {:first, _}}
    Process.exit(caller, :kill)
    assert eventually(fn -> Admission.close_failure(table, deadline - 1) == :owner_closed end)

    :ets.delete(table, :closing)
    expired = System.monotonic_time(:millisecond) - 1
    assert {:first, _} = Admission.begin_close(table, self(), @generation, expired)
    assert Admission.close_failure(table, System.monotonic_time(:millisecond)) == :timeout
    :ets.delete(table)
  end

  test "WCO-N02 table ownership rejects foreign or malformed generation capabilities" do
    table = Admission.new(@generation)
    deadline = System.monotonic_time(:millisecond) + 5_000
    parent = self()

    caller =
      spawn(fn ->
        send(parent, {:foreign_acquire, Admission.acquire(table, self(), @generation, deadline)})
      end)

    assert_receive {:foreign_acquire, {:error, :invalid_handle}}
    refute Process.alive?(caller)
    assert {:error, :invalid_handle} = Admission.acquire(:invalid, self(), @generation, deadline)
    assert_raise FunctionClauseError, fn -> Admission.new(0) end
    assert_raise FunctionClauseError, fn -> Admission.new(0x1_0000_0000_0000_0000) end
    :ets.delete(table)
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
