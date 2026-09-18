defmodule Wotex.Thread.DaemonTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.{Address, Daemon}

  test "read-only Unix transport assembles fragments and owns cleanup" do
    {path, task} =
      peer(fn socket ->
        assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
        :ok = :gen_tcp.send(socket, "leader\nDo")
        :ok = :gen_tcp.send(socket, "ne\n")
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert {:ok, "leader"} = Daemon.request(handle, %{type: :state}, 1000)
    assert {:error, _} = Daemon.request(handle, %{type: :dataset_set}, 1000)
    assert {:error, _} = Daemon.request(handle, %{}, 1000)
    assert {:error, _} = Daemon.request(handle, %{type: :state}, 0)
    assert {:error, _} = Daemon.request(%{handle | owner: task.pid}, %{type: :state}, 1000)

    assert {:error, %{code: :wrong_owner}} =
             Task.await(Task.async(fn -> Daemon.disconnect(handle) end))

    assert :ok = Daemon.disconnect(handle)
    assert :ok = Daemon.disconnect(handle)
    assert {:error, _} = Daemon.disconnect(nil)
    Task.await(task)
  end

  test "timeouts close the socket and malformed configuration never creates a session" do
    {path, task} =
      peer(fn socket ->
        assert {:ok, _} = :gen_tcp.recv(socket, 0, 1000)
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert {:error, %{code: :timeout}} = Daemon.request(handle, %{type: :version}, 10)
    Task.await(task)

    for opts <- [
          [],
          [:invalid],
          [socket_path: <<0>>],
          [socket_path: path, timeout: 0],
          [socket_path: path, timeout: 1000, unknown: true],
          [socket_path: path, socket_path: path],
          [socket_path: path <> "missing"]
        ],
        do: assert(match?({:error, _}, Daemon.connect(opts)))

    assert {:error, _} = Daemon.connect(nil)

    assert {:error, _} = Address.validate_message(%{type: :dataset_set})
  end

  test "packet and aggregate limits close oversized daemon responses" do
    {path, task} =
      peer(fn socket ->
        assert {:ok, _} = :gen_tcp.recv(socket, 0, 1000)
        :ok = :gen_tcp.send(socket, :binary.copy("x", 8193) <> "\n")
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert {:error, %{code: :response_limit}} = Daemon.request(handle, %{type: :state}, 1000)
    Task.await(task)
  end

  test "a line beyond the packet size fails in the socket driver as response_limit" do
    {path, task} =
      peer(fn socket ->
        assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
        :ok = :gen_tcp.send(socket, :binary.copy("x", 8193) <> "\n")
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)

    # Line mode enforces packet_size only when the driver buffer is larger; with the OTP 27
    # default of 1460 bytes the driver hands over the line in pieces instead. A larger buffer
    # makes the driver refuse the line with :emsgsize whatever the release default.
    assert :ok = :inet.setopts(handle.socket, buffer: 16_384)
    assert {:error, %{code: :response_limit}} = Daemon.request(handle, %{type: :state}, 1000)
    assert {:error, %{code: :transport_closed}} = Daemon.request(handle, %{type: :state}, 1000)
    Task.await(task)
  end

  test "remote errors and premature closure are distinct failures" do
    {error_path, error_task} =
      peer(fn socket ->
        assert {:ok, _} = :gen_tcp.recv(socket, 0, 1000)
        :ok = :gen_tcp.send(socket, "Error 1: failed\n")
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, error_handle} = Daemon.connect(socket_path: error_path)
    assert {:error, %{code: :remote_error}} = Daemon.request(error_handle, %{type: :state}, 1000)
    Task.await(error_task)

    {closed_path, closed_task} =
      peer(fn socket ->
        assert {:ok, _} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, closed_handle} = Daemon.connect(socket_path: closed_path)

    assert {:error, %{code: :transport_closed}} =
             Daemon.request(closed_handle, %{type: :state}, 1000)

    Task.await(closed_task)
  end

  test "the socket closes when its owner exits" do
    {path, task} = peer(fn socket -> assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000) end)
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:owner_connected, Daemon.connect(socket_path: path)})
      end)

    monitor = Process.monitor(owner)
    assert_receive {:owner_connected, {:ok, _handle}}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1000
    Task.await(task)
  end

  defp peer(fun) do
    path =
      Path.join(System.tmp_dir!(), "wt-#{System.pid()}-#{System.unique_integer([:positive])}.sock")

    parent = self()

    task =
      Task.async(fn ->
        {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, path}])
        send(parent, :listening)

        try do
          {:ok, socket} = :gen_tcp.accept(listener, 1000)

          try do
            fun.(socket)
          after
            :gen_tcp.close(socket)
          end
        after
          :gen_tcp.close(listener)
          File.rm(path)
        end
      end)

    assert_receive :listening, 1000
    {path, task}
  end
end
