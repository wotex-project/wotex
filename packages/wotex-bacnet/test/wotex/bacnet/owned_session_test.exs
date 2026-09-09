defmodule Wotex.BACnet.OwnedSessionTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, Error, IPv4, StackOwner}

  test "WBA-S03 WBA-V05 abrupt native session-owner loss closes its owned stack" do
    {:ok, session} =
      BACnet.connect(
        client: IPv4,
        local_ip: :none,
        local_port: 55_838,
        destination: {{127, 0, 0, 1}, 55_839},
        timeout: 100
      )

    on_exit(fn -> BACnet.disconnect(session) end)
    stack = session.handle.owner
    client = session.handle.stack.client
    native_owner = session.handle.stack.owner
    monitor = Process.monitor(stack)
    Process.unlink(native_owner)
    Process.exit(native_owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^stack, _}, 1100
    refute Process.alive?(client)
    assert {:ok, socket} = :gen_udp.open(55_838, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S03 borrowed session-owner loss leaves the borrowed stack alive" do
    {:ok, stack} =
      StackOwner.start_link(local_ip: :none, local_port: 55_838, timeout: 100, owner: self())

    on_exit(fn -> StackOwner.close(stack) end)
    {:ok, client} = StackOwner.client(stack)

    {:ok, session} =
      BACnet.connect(
        client: BACstack,
        stack_client: client,
        destination: {{127, 0, 0, 1}, 55_839},
        timeout: 100
      )

    owner = session.handle.owner
    monitor = Process.monitor(owner)
    Process.unlink(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert Process.alive?(stack)
    assert Process.alive?(client)
    assert :ok = BACnet.disconnect(session)
    assert Process.alive?(client)
  end

  test "WBA-S03 stack custody binds once and only through its original owner" do
    {:ok, stack} =
      StackOwner.start_link(local_ip: :none, local_port: 55_838, timeout: 100, owner: self())

    on_exit(fn -> StackOwner.close(stack) end)
    session = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(session, :kill) end)
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}
    assert {:error, %Error{code: :invalid_session}} = StackOwner.bind_session(stack, dead)
    assert {:error, %Error{code: :invalid_session}} = StackOwner.bind_session(stack, :invalid)
    foreign = Task.async(fn -> StackOwner.bind_session(stack, session) end)
    assert {:error, %Error{code: :invalid_session}} = Task.await(foreign)
    assert :ok = StackOwner.bind_session(stack, session)
    assert {:error, %Error{code: :invalid_session}} = StackOwner.bind_session(stack, self())
    monitor = Process.monitor(stack)
    send(session, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^stack, :normal}, 1100
    assert {:error, %Error{code: :connection_closed}} = StackOwner.bind_session(stack, self())
  end

  test "WBA-S03 failed stack-custody binding cleans the temporary session owner" do
    {:ok, stack} =
      StackOwner.start_link(local_ip: :none, local_port: 55_838, timeout: 100, owner: self())

    on_exit(fn -> StackOwner.close(stack) end)
    {:ok, client} = StackOwner.client(stack)
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _}
    {:links, before} = Process.info(self(), :links)

    assert {:error, %Error{code: :connection_closed}} =
             BACstack.connect_owned(
               [stack_client: client, destination: {{127, 0, 0, 1}, 55_839}],
               dead
             )

    assert {:links, after_links} = Process.info(self(), :links)
    assert Enum.sort(before) == Enum.sort(after_links)
    assert Process.alive?(client)
  end
end
