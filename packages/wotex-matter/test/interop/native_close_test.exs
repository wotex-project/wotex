defmodule Wotex.Matter.NativeCloseInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000

  test "WMA-C03 full admission cannot prevent closing a stopped SDK child" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_CLOSE_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = Map.fetch!(fixture, "controller")

    options =
      [lifecycle: :persistent, storage_mode: :open_existing, authority: :stored, timeout: 10_000] ++
        Enum.map(
          [
            :executable,
            :storage_path,
            :vendor_id,
            :fabric_id,
            :controller_node_id,
            :paa_trust_store
          ],
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    read = %{
      type: :read,
      fabric_id: options[:fabric_id],
      node_id: Map.fetch!(fixture, "node_id"),
      endpoint: Map.fetch!(fixture, "endpoint"),
      cluster: 6,
      member: 0
    }

    toggle =
      Map.merge(read, %{
        type: :invoke,
        member: 2,
        value: %{tag: :anonymous, type: :structure, value: []}
      })

    assert {:ok, handle} = Native.connect(options)
    assert {:ok, %{value: %{type: :boolean} = initial}} = Native.request(handle, read, 5_000)
    owner_monitor = Process.monitor(handle.pid)
    port = :sys.get_state(handle.pid).port
    {:os_pid, child} = Port.info(port, :os_pid)
    assert {_, 0} = Wotex.Matter.Native.ProcessCommand.run("/bin/kill", ["-STOP", to_string(child)])
    assert eventually(fn -> File.read!("/proc/#{child}/status") =~ ~r/State:\s+T/ end)
    active = Task.async(fn -> Native.health(handle, 10_000) end)
    assert eventually(fn -> :ets.info(handle.admission, :size) == 2 end)
    assert Task.yield(active, 20) == nil
    mutation = Task.async(fn -> Native.request(handle, toggle, 10_000) end)
    queued = for _ <- 1..62, do: Task.async(fn -> Native.health(handle, 10_000) end)

    try do
      assert eventually(fn -> :ets.info(handle.admission, :size) == 65 end)
      assert {:error, %Error{code: :busy}} = Native.health(handle, 25)
      started = System.monotonic_time(:millisecond)

      results =
        1..32
        |> Task.async_stream(fn _ -> Native.disconnect(handle) end, max_concurrency: 32)
        |> Enum.to_list()

      assert results == List.duplicate({:ok, :ok}, 32)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}, 1_000
      assert eventually(fn -> not File.exists?("/proc/#{child}") end)
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed <= 1_000
      assert Port.info(port) == nil
      assert :ets.info(handle.admission) == :undefined

      for caller <- [active, mutation | queued] do
        assert {:error, %Error{code: :transport_closed, effect: :none}} = Task.await(caller, 1_000)
      end

      assert {:ok, reopened} = Native.connect(options)

      try do
        assert {:ok, %{value: ^initial}} = Native.request(reopened, read, 5_000)
      after
        assert :ok = Native.disconnect(reopened)
      end

      File.write!(
        Map.fetch!(fixture, "result_path"),
        Jason.encode!(%{
          status: "passed",
          pending_requests: 64,
          concurrent_close_callers: 32,
          cleanup_ms: elapsed,
          queued_mutation_effect: "none",
          durable_reopen: "passed",
          owned_processes_after_grace: 0
        }),
        [:exclusive]
      )
    after
      if Port.info(port, :os_pid) == {:os_pid, child},
        do:
          Wotex.Matter.Native.ProcessCommand.run("/bin/kill", ["-CONT", to_string(child)],
            stderr_to_stdout: true
          )

      for caller <- [active, mutation | queued], do: Task.shutdown(caller, :brutal_kill)
      Native.disconnect(handle)
    end
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
