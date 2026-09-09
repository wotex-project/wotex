defmodule Wotex.BACnet.StackLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.APDU
  alias Wotex.BACnet.{BACstack, IPv4, OperationOwner, StackOwner}
  alias Wotex.BACnet.Test.BlockingClient
  @moduletag :capture_log
  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/stack_lifecycle_v1.json", __DIR__)))
  @message %{type: :read_property, object_type: 1, instance: 0, property: 85}

  setup do
    client = start_supervised!({BlockingClient, self()})

    {:ok, handle} =
      BACstack.connect(stack_client: client, destination: {{127, 0, 0, 1}, 47_808}, writes: true)

    on_exit(fn -> BACstack.disconnect(handle) end)
    %{client: client, handle: handle}
  end

  test "WBA-S03 WBA-V14 64 admitted callers bound work and reject65 without a worker", %{
    handle: handle,
    client: client
  } do
    case_data = Enum.find(@fixture["cases"], &(&1["id"] == "WBA-L02"))
    count = case_data["input"]["admitted_callers"]
    expected = case_data["expected"]
    callers = for _ <- 1..count, do: Task.async(fn -> BACstack.request(handle, @message, 5000) end)
    for _ <- callers, do: assert_receive({:pending_apdu, _, _, _, _}, 1000)
    state = :sys.get_state(handle.owner)
    assert map_size(state.pending) == count
    assert {:error, error} = BACstack.request(handle, @message, 5000)
    assert Atom.to_string(error.code) == expected["error"]
    assert Atom.to_string(error.effect) == expected["effect"]
    assert :sys.get_state(handle.owner).pending == state.pending
    workers = for {_, op} <- state.pending, do: Process.monitor(op.worker)
    assert :ok = BACstack.disconnect(handle)
    for caller <- callers, do: assert({:error, %{code: :connection_closed}} = Task.await(caller))
    for reference <- workers, do: assert_receive({:DOWN, ^reference, :process, _, _}, 1000)
    assert Process.alive?(client) == expected["borrowed_client_alive"]
    assert :ok = BACstack.disconnect(handle)
  end

  test "WBA-S03 WBA-V05 dead caller cancels only owned work and late reply cannot reopen it", %{
    handle: handle,
    client: client
  } do
    caller = spawn(fn -> BACstack.request(handle, @message, 60_000) end)
    assert_receive {:pending_apdu, from, _, _, _}
    [operation] = Map.values(:sys.get_state(handle.owner).pending)
    reference = Process.monitor(operation.worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^reference, :process, _, _}, 100
    assert :sys.get_state(handle.owner).pending == %{}
    GenServer.reply(from, {:ok, %APDU.SimpleACK{invoke_id: 0, service: :write_property}})
    send(handle.owner, {:timeout, make_ref()})
    send(handle.owner, {:result, make_ref(), {:ok, :stale}})
    send(handle.owner, {:DOWN, make_ref(), :process, self(), :normal})
    send(handle.owner, :unrelated)
    assert :sys.get_state(handle.owner).pending == %{}
    assert Process.alive?(client)
  end

  test "WBA-S03 WBA-V05 client death rejects a blocked call promptly", %{
    handle: handle,
    client: client
  } do
    task = Task.async(fn -> BACstack.request(handle, @message, 60_000) end)
    assert_receive {:pending_apdu, _, _, _, _}
    stop_supervised!(BlockingClient)
    refute Process.alive?(client)
    assert {:error, %{code: :connection_closed}} = Task.await(task, 100)
    assert {:error, %{code: :connection_closed}} = BACstack.request(handle, @message, 100)
  end

  test "WBA-S03 WBA-V05 borrower death stops owner and worker but retains Client", %{client: client} do
    receiver = self()

    borrower =
      spawn(fn ->
        {:ok, handle} =
          BACstack.connect(stack_client: client, destination: {{127, 0, 0, 1}, 47_808})

        send(receiver, {:borrowed, handle})
        BACstack.request(handle, @message, 60_000)
      end)

    assert_receive {:borrowed, handle}
    assert_receive {:pending_apdu, _, _, _, _}
    reference = Process.monitor(handle.owner)
    Process.exit(borrower, :kill)
    assert_receive {:DOWN, ^reference, :process, _, :normal}, 100
    assert Process.alive?(client)
  end

  test "WBA-S03 WBA-V14 expired admission and foreign generation send no APDU", %{handle: handle} do
    assert {:error, %{code: :deadline_exceeded, effect: :none}} =
             OperationOwner.request(
               handle.owner,
               handle.generation,
               @message,
               System.monotonic_time(:millisecond)
             )

    assert {:error, %{code: :connection_closed}} =
             OperationOwner.request(
               handle.owner,
               make_ref(),
               @message,
               System.monotonic_time(:millisecond) + 1000
             )

    refute_receive {:pending_apdu, _, _, _, _}
  end

  test "WBA-S03 WBA-V05 worker failure and write timeout retain conservative effects", %{
    handle: handle,
    client: client
  } do
    task = Task.async(fn -> BACstack.request(handle, @message, 60_000) end)
    assert_receive {:pending_apdu, _, _, _, _}
    [operation] = Map.values(:sys.get_state(handle.owner).pending)
    Process.exit(operation.worker, :kill)
    assert {:error, %{code: :connection_closed, effect: :none}} = Task.await(task, 100)

    message =
      Map.merge(@message, %{
        type: :write_property,
        value: BACnet.Protocol.ApplicationTags.Encoding.create!({:null, nil})
      })

    assert {:error, %{code: :deadline_exceeded, effect: :unknown}} =
             BACstack.request(handle, message, 10)

    assert :sys.get_state(handle.owner).pending == %{}
    assert Process.alive?(client)
  end

  test "WBA-S03 WBA-V05 every acquisition failure unwinds real resources in reverse order" do
    phases = [:transport, :segmentator, :segments_store, :client]
    receiver = self()

    for {failed, index} <- Enum.with_index(phases), mode <- [:error, :raise, :exit] do
      acquire = fn name, start ->
        if name == failed do
          case mode do
            :error -> {:error, :injected}
            :raise -> raise "injected"
            :exit -> exit(:injected)
          end
        else
          {:ok, pid} = start.()
          send(receiver, {:acquired, name, pid})
          {:ok, pid}
        end
      end

      assert {:error, %{code: :startup_failed}} =
               StackOwner.start_link(
                 [local_ip: :none, local_port: 55_816, timeout: 5000, owner: self()],
                 acquire
               )

      for name <- Enum.take(phases, index) do
        assert_receive {:acquired, ^name, pid}
        refute Process.alive?(pid)
      end

      {:ok, socket} = :gen_udp.open(55_816, [:binary])
      :gen_udp.close(socket)
    end
  end

  test "WBA-L01 WBA-S03 WBA-V05 real startup unwind follows corpus cleanup order" do
    row = Enum.find(@fixture["cases"], &(&1["id"] == "WBA-L01"))
    receiver = self()
    handler = "stack-unwind-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :bacnet, :resource, :stop],
        fn _, _, metadata, receiver ->
          send(receiver, {:released, Atom.to_string(metadata.resource), metadata.result})
        end,
        receiver
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    acquire = fn name, start ->
      if Atom.to_string(name) == row["input"]["fail"] do
        {:error, :injected}
      else
        {:ok, pid} = start.()
        send(receiver, {:suspended, Atom.to_string(name), pid})
        {:ok, pid}
      end
    end

    task =
      Task.async(fn ->
        StackOwner.start_link(
          [local_ip: :none, local_port: 55_820, timeout: 5000, owner: receiver],
          acquire
        )
      end)

    resources =
      Map.new(row["input"]["acquisitions"], fn name ->
        assert_receive {:suspended, ^name, pid}
        {name, pid}
      end)

    assert {:error, %{code: :startup_failed}} = Task.await(task)

    order =
      for _ <- row["expected"]["cleanup_order"] do
        assert_receive {:released, name, :ok}
        name
      end

    assert order == row["expected"]["cleanup_order"]

    assert Enum.count(resources, fn {_, pid} -> Process.alive?(pid) end) ==
             row["expected"]["active_owned_resources"]

    {:ok, socket} = :gen_udp.open(55_820, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S03 WBA-V14 late completion is rejected even before a queued timer message", %{
    handle: handle
  } do
    task = Task.async(fn -> BACstack.request(handle, @message, 60_000) end)
    assert_receive {:pending_apdu, _, _, _, _}
    [{reference, operation}] = Map.to_list(:sys.get_state(handle.owner).pending)

    :sys.replace_state(handle.owner, fn state ->
      put_in(state, [:pending, reference, :deadline], System.monotonic_time(:millisecond))
    end)

    send(handle.owner, {:result, reference, {:ok, :late}})
    assert {:error, %{code: :deadline_exceeded}} = Task.await(task)
    assert :sys.get_state(handle.owner).pending == %{}
    Process.exit(operation.worker, :kill)
  end

  test "WBA-S03 WBA-V05 cleanup kills an unresponsive child within one shared grace" do
    receiver = self()

    acquire = fn
      :client, _ ->
        pid =
          spawn_link(fn ->
            receive do
              :never -> :ok
            end
          end)

        send(receiver, {:unresponsive_child, pid})
        {:ok, pid}

      _, start ->
        start.()
    end

    {:ok, owner} =
      StackOwner.start_link(
        [local_ip: :none, local_port: 55_817, timeout: 5000, owner: self()],
        acquire
      )

    assert_receive {:unresponsive_child, pid}
    reference = Process.monitor(pid)
    group = :sys.get_state(owner)
    started = System.monotonic_time(:millisecond)
    assert :ok = StackOwner.close(owner)
    assert_receive {:DOWN, ^reference, :process, ^pid, :killed}, 100
    assert System.monotonic_time(:millisecond) - started < 1100

    for key <- [:transport, :segments_store, :segmentator],
        do: refute(Process.alive?(Map.fetch!(group, key)))

    {:ok, socket} = :gen_udp.open(55_817, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S03 WBA-V05 each owned child death interrupts blocked I/O and closes the group" do
    for child <- [:transport, :segments_store, :segmentator, :client] do
      {:ok, handle} =
        IPv4.connect(
          local_ip: :none,
          local_port: 55_818,
          destination: {{127, 0, 0, 1}, 55_815},
          timeout: 60_000
        )

      group = :sys.get_state(handle.owner)
      task = Task.async(fn -> IPv4.request(handle, @message, 60_000) end)
      # Observe the SDK's admitted request before injecting failure.
      await_pending(group.client, System.monotonic_time(:millisecond) + 1000)
      Process.exit(Map.fetch!(group, child), :kill)
      assert {:error, %{code: :connection_closed}} = Task.await(task, 100)
      assert :ok = IPv4.disconnect(handle)

      for key <- [:transport, :segments_store, :segmentator, :client],
          do: refute(Process.alive?(Map.fetch!(group, key)))

      {:ok, socket} = :gen_udp.open(55_818, [:binary])
      :gen_udp.close(socket)
    end
  end

  test "WBA-S03 WBA-V14 facade preserves first-party pre-I/O capacity effects", %{handle: handle} do
    callers = for _ <- 1..64, do: Task.async(fn -> BACstack.request(handle, @message, 5000) end)
    for _ <- callers, do: assert_receive({:pending_apdu, _, _, _, _}, 1000)
    session = %Wotex.BACnet.Session{client: BACstack, handle: handle, timeout: 5000}

    message =
      Map.merge(@message, %{
        type: :write_property,
        value: BACnet.Protocol.ApplicationTags.Encoding.create!({:null, nil})
      })

    assert {:error, %{code: :busy, effect: :none}} = Wotex.BACnet.send(session, message)
    assert :ok = BACstack.disconnect(handle)
    for caller <- callers, do: Task.await(caller)
  end

  test "WBA-S03 WBA-V05 deadline escalation cannot propagate a kill to the closing caller" do
    {:ok, owner} =
      StackOwner.start_link(local_ip: :none, local_port: 55_832, timeout: 1000, owner: self())

    group = :sys.get_state(owner)

    monitors =
      for key <- [:client, :segments_store, :segmentator, :transport],
          do: Process.monitor(group[key])

    monitor = Process.monitor(owner)
    :ok = :sys.suspend(owner)
    started = System.monotonic_time(:millisecond)
    assert :ok = StackOwner.close(owner, started + 1)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 100
    for ref <- monitors, do: assert_receive({:DOWN, ^ref, :process, _, _}, 100)
    assert System.monotonic_time(:millisecond) - started < 200
    {:ok, socket} = :gen_udp.open(55_832, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S03 WBA-V05 exhausted grace still lets the owner finish reverse cleanup normally" do
    receiver = self()

    acquire = fn
      :client, _ ->
        pid =
          spawn_link(fn ->
            receive do
              :never -> :ok
            end
          end)

        send(receiver, {:deadline_child, pid})
        {:ok, pid}

      _, start ->
        start.()
    end

    for _ <- 1..10 do
      {:ok, owner} =
        StackOwner.start_link(
          [local_ip: :none, local_port: 55_832, timeout: 1000, owner: self()],
          acquire
        )

      group = :sys.get_state(owner)
      monitor = Process.monitor(owner)
      assert_receive {:deadline_child, child}
      assert :ok = StackOwner.close(owner, System.monotonic_time(:millisecond) + 2)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 100
      refute Process.alive?(child)

      for key <- [:transport, :segmentator, :segments_store],
          do: refute(Process.alive?(group[key]))

      {:ok, socket} = :gen_udp.open(55_832, [:binary])
      :gen_udp.close(socket)
    end
  end

  defp await_pending(client, deadline) do
    if :sys.get_state(client).sdk.apdu_timers == %{} do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(1)
      await_pending(client, deadline)
    end
  end

  test "WBA-S03 WBA-V05 owned timeout releases socket and SDK timer state" do
    {:ok, handle} =
      IPv4.connect(
        local_ip: :none,
        local_port: 55_814,
        destination: {{127, 0, 0, 1}, 55_815},
        timeout: 60_000
      )

    state = :sys.get_state(handle.owner)

    children =
      Enum.map([:client, :segments_store, :segmentator, :transport], &Map.fetch!(state, &1))

    references = Enum.map(children, &Process.monitor/1)
    assert {:error, %{code: :deadline_exceeded}} = IPv4.request(handle, @message, 10)
    for reference <- references, do: assert_receive({:DOWN, ^reference, :process, _, _}, 1000)
    assert :ok = IPv4.disconnect(handle)
    {:ok, socket} = :gen_udp.open(55_814, [:binary])
    :gen_udp.close(socket)
  end
end
