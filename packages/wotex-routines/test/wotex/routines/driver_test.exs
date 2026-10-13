defmodule Wotex.Routines.DriverTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Wotex.Routines.{Driver, DriverHandle, Error, TestDriverHost}

  setup do
    tag = make_ref()

    %{
      tag: tag,
      options: %{
        id: "owned-wakeup",
        host: TestDriverHost,
        context: {self(), tag},
        capacity: 2,
        poll_ms: nil,
        work_timeout_ms: 1000
      }
    }
  end

  test "specification is inert, closed and creates a transient unnamed child", c do
    assert {:ok, spec} = Driver.specification(c.options)
    assert spec.start == {Driver, :start_link, [c.options]}
    assert spec.restart == :transient

    for options <- [
          Map.delete(c.options, :context),
          Map.put(c.options, :name, :global),
          %{c.options | capacity: 0},
          %{c.options | capacity: 65},
          %{c.options | poll_ms: 0},
          %{c.options | host: "module-name"},
          %{c.options | work_timeout_ms: 60_001}
        ] do
      assert {:error, %Error{code: :invalid_driver_options}} = Driver.specification(options)
    end

    refute_received {_, :entered, _, _, _}
  end

  test "capacity admission precedes mailbox delivery and queued causes retain FIFO", c do
    {_, handle} = start(c.options)
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {tag, :entered, first, :manual, %{work_timeout_ms: 1000}}
    assert tag == c.tag
    assert :ok = Driver.notify(handle, :basis_changed)
    assert {:error, %Error{code: :wakeup_saturated}} = Driver.notify(handle, :manual)
    assert {:ok, %{active: true, pending: 1}} = Driver.status(handle, 1000)
    send(first, :finish)
    assert_receive {^tag, :entered, second, :basis_changed, _}
    send(second, :finish)
    assert %{completed: 2, pending: 0} = await(handle, &(&1.completed == 2))
    assert :atomics.get(handle.counter, 1) == 0
    assert :ok = Driver.retire(handle, 1000)
    assert {:error, %Error{code: :retired_driver}} = Driver.notify(handle, :manual)
  end

  test "concurrent admission cannot overfill accepted work", c do
    {_, handle} = start(c.options)

    tasks = Enum.map(1..20, fn _ -> Task.async(fn -> Driver.notify(handle, :manual) end) end)
    results = Enum.map(tasks, &Task.await(&1, 1000))

    assert Enum.count(results, &(&1 == :ok)) == 2
    assert Enum.count(results, &match?({:error, %Error{code: :wakeup_saturated}}, &1)) == 18
    assert_receive {_, :entered, worker, :manual, _}
    send(worker, :finish)
    assert_receive {_, :entered, worker, :manual, _}
    send(worker, :finish)
    await(handle, &(&1.completed == 2))
  end

  test "timeout waits for retirement, drops pending work and never replays old notifications", c do
    {_, handle} = start(%{c.options | capacity: 3, work_timeout_ms: 40})
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {_, :entered, worker, :manual, _}
    monitor = Process.monitor(worker)
    assert :ok = Driver.notify(handle, :basis_changed)
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1000

    assert %{timed_out: 1, failed: 1, dropped: 2, active: false, closed: false} =
             await(handle, &(&1.timed_out == 1 and not &1.active))

    refute_received {_, :entered, _, _, _}
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {_, :entered, fresh, :manual, _}
    send(fresh, :finish)
    await(handle, &(&1.completed == 1))
  end

  test "host failure or exit drops pending causes and hides exception context", c do
    for signal <- [:fail, :raise, :throw, :crash] do
      {_, handle} = start(c.options)

      log =
        capture_log(fn ->
          assert :ok = Driver.notify(handle, :manual)
          assert_receive {_, :entered, worker, _, _}
          assert :ok = Driver.notify(handle, :basis_changed)
          send(worker, signal)
          assert %{failed: 1, dropped: 1, active: false} = await(handle, &(&1.failed == 1))
        end)

      refute log =~ "synthetic-private-context"
      refute log =~ "synthetic_private_context"
      refute_received {_, :entered, _, _, _}
      assert :ok = Driver.retire(handle, 1000)
    end
  end

  test "poll ticks coalesce while work is active and retirement closes the callback lifecycle", c do
    {pid, handle} = start(%{c.options | poll_ms: 10})
    assert_receive {_, :entered, worker, :poll, _}, 1000
    assert {:ok, %{active: true, pending: 0}} = Driver.status(handle, 1000)
    Process.sleep(40)
    assert {:ok, %{active: true, pending: 0}} = Driver.status(handle, 1000)
    worker_monitor = Process.monitor(worker)
    driver_monitor = Process.monitor(pid)
    assert :ok = Driver.retire(handle, 1000)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}
    assert_receive {:DOWN, ^driver_monitor, :process, ^pid, :normal}
    refute_received {_, :entered, _, _, _}
  end

  test "owner death retires the linked worker and status never reveals private context", c do
    {pid, handle} = start(%{c.options | context: {self(), "synthetic-private-context"}})
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {"synthetic-private-context", :entered, worker, _, _}
    refute inspect(:sys.get_status(pid)) =~ "synthetic-private-context"
    Process.unlink(pid)
    monitor = Process.monitor(worker)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert {:error, %Error{code: :retired_driver}} = Driver.status(handle, 1000)
  end

  test "a result queued before retirement cannot start another callback after admission closes",
       c do
    {pid, handle} = start(c.options)
    assert :ok = Driver.notify(handle, :manual)
    assert_receive {_, :entered, worker, :manual, _}
    assert :ok = Driver.notify(handle, :basis_changed)
    assert {:ok, %{pending: 1}} = Driver.status(handle, 1000)
    :sys.suspend(pid)
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    retiring = Task.async(fn -> Driver.retire(handle, 1000) end)
    await_closed(handle.counter, 100)
    :sys.resume(pid)
    assert Task.await(retiring, 1000) == :ok
    refute_received {_, :entered, _, :basis_changed, _}
  end

  test "malformed handles, unknown causes and invalid call bounds refuse", c do
    {pid, handle} = start(c.options)

    for handle <- [
          nil,
          %{},
          struct!(DriverHandle, pid: nil, token: nil, counter: nil, capacity: 1),
          %{handle | capacity: 65},
          %{handle | counter: make_ref()}
        ] do
      assert {:error, %Error{code: :invalid_driver_handle}} = Driver.notify(handle, :manual)
    end

    assert {:error, %Error{code: :invalid_wakeup}} = Driver.notify(handle, "manual")
    assert {:error, %Error{code: :invalid_call_timeout}} = Driver.status(handle, 0)
    assert {:error, %Error{code: :invalid_call_timeout}} = Driver.retire(handle, 0)
    assert :atomics.get(handle.counter, 2) == 0
    assert {:error, %Error{code: :invalid_driver_handle}} = Driver.handle(nil, 1000)
    assert {:error, %Error{code: :invalid_driver_request}} = GenServer.call(pid, :unrecognized)
    send(pid, :unrecognized)
    assert {:ok, %{active: false}} = Driver.status(handle, 1000)
  end

  defp start(options) do
    assert {:ok, pid} = Driver.start_link(options)
    assert {:ok, handle} = Driver.handle(pid, 1000)
    on_exit(fn -> if Process.alive?(pid), do: Driver.retire(handle, 1000) end)
    {pid, handle}
  end

  defp await(handle, predicate, attempts \\ 200)

  defp await(handle, predicate, attempts) when attempts > 0 do
    assert {:ok, status} = Driver.status(handle, 1000)

    if predicate.(status) do
      status
    else
      Process.sleep(5)
      await(handle, predicate, attempts - 1)
    end
  end

  defp await(_, _, _), do: flunk("driver lifecycle did not reach its expected state")

  defp await_closed(counter, attempts) when attempts > 0 do
    if :atomics.get(counter, 2) == 1 do
      :ok
    else
      Process.sleep(1)
      await_closed(counter, attempts - 1)
    end
  end

  defp await_closed(_, _), do: flunk("retirement did not close admission")
end
