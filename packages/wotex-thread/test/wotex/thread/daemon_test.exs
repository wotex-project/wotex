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
    assert {:error, _} = Daemon.request(%{handle | owner: task.pid}, %{type: :state}, 1000)
    assert :ok = Daemon.disconnect(handle)
    assert :ok = Daemon.disconnect(handle)
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
          [socket_path: <<0>>],
          [socket_path: path, timeout: 0],
          [socket_path: path <> "missing"]
        ],
        do: assert(match?({:error, _}, Daemon.connect(opts)))

    assert {:error, _} = Address.validate_message(%{type: :dataset_set})
  end

  defp peer(fun) do
    path = Path.join(System.tmp_dir!(), "wt-#{System.unique_integer([:positive])}.sock")
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
