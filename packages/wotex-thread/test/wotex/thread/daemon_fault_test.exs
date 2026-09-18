defmodule Wotex.Thread.DaemonFaultTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Thread.{Address, Daemon}

  @external_resource "priv/fixtures/contract-v1.json"
  @corpus File.read!(@external_resource)
  @cases Map.fetch!(Jason.decode!(@corpus), "cases")
  @moduletag requirements: ["WTH-S02", "WTH-N02", "WTH-N04"], vectors: ["WTH-V03"]

  @tag fixture_sha256: Base.encode16(:crypto.hash(:sha256, @corpus), case: :lower)
  test "WTH-F06 WTH-S02 WTH-V03 executes the exact fragmented daemon corpus" do
    fixture = Enum.find(@cases, &(&1["id"] == "WTH-F06"))
    command = fixture["input"]["request"]
    expected = fixture["expectation"]["value"]
    events = Enum.filter(fixture["input"]["events"], &(&1["event"] == "socket_bytes"))

    {path, task} =
      peer(fn socket ->
        assert {:ok, command_bytes} = :gen_tcp.recv(socket, 0, 1000)
        assert command_bytes == command <> "\n"

        Enum.each(events, fn event ->
          :ok = :gen_tcp.send(socket, Base.decode16!(event["bytes_hex"], case: :lower))
        end)

        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
        %{daemon_commands: [String.trim_trailing(command_bytes, "\n")], completion_markers: 1}
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert Daemon.request(handle, %{type: :state}, 1000) == {:ok, expected["result"]["ok"]}
    assert :ok = Daemon.disconnect(handle)

    assert Task.await(task) == %{
             daemon_commands: expected["daemon_commands"],
             completion_markers: expected["completion_markers"]
           }
  end

  @tag sdk_revision: "5c8c318627954c99cd1a957a290bbd4b1027d04b",
       sdk_sources: ["include/openthread/platform/radio.h", "src/core/thread/mle_types.hpp"]
  test "WTH-S02 WTH-V03 admits exactly one typed result and its matching optional echo" do
    for role <- ~w(disabled detached child router leader) do
      assert Daemon.parse("state\r\n#{role}\r\nDone\r\n> ", :state) == {:ok, role}
      assert Daemon.parse("> #{role}\nDone\n", :state) == {:ok, role}
    end

    assert {:ok, 0} = Daemon.parse("0000\nDone\n", :rloc16)
    assert {:ok, 0xFFFD} = Daemon.parse("rloc16\nfffd\nDone\n", :rloc16)
    assert {:ok, nil} = Daemon.parse("fffe\nDone\n", :rloc16)
    assert {:ok, 0xFFFF} = Daemon.parse("ffff\nDone\n", :rloc16)

    assert {:ok, "OpenThread/1.4.0; POSIX"} =
             Daemon.parse("OpenThread/1.4.0; POSIX\nDone\n", :version)

    assert {:ok, " a network "} = Daemon.parse("networkname\n a network \nDone\n", :network_name)
    assert {:ok, "Done"} = Daemon.parse("Done\nDone\n", :network_name)
    assert {:ok, "éééééééé"} = Daemon.parse("éééééééé\nDone\n", :network_name)

    for {type, bytes} <- [
          {:state, "leader\nrouter\nDone\n"},
          {:state, "version\nleader\nDone\n"},
          {:state, "leader\nDone\nDone\n"},
          {:state, "leader\nDone\nextra\n"},
          {:state, "leader\nDone\nextra"},
          {:state, "leader\nError 5: secret-canary\nDone\n"},
          {:state, "Done\n"},
          {:state, "mystery\nDone\n"},
          {:state, " leader\nDone\n"},
          {:state, "leader \nDone\n"},
          {:rloc16, "0x1234\nDone\n"},
          {:rloc16, "12345\nDone\n"},
          {:rloc16, "12gg\nDone\n"},
          {:rloc16, "-001\nDone\n"},
          {:version, "\nDone\n"},
          {:version, "a\0b\nDone\n"},
          {:version, String.duplicate("v", 1025) <> "\nDone\n"},
          {:network_name, String.duplicate("n", 17) <> "\nDone\n"},
          {:network_name, "a\tb\nDone\n"},
          {:network_name, "\nDone\n"},
          {:state, <<255, "\nDone\n">>}
        ] do
      assert {:error, error} = Daemon.parse(bytes, type)
      refute inspect(error) =~ "secret-canary"
    end

    assert {:error, _} = Daemon.parse("leader\nDone\n", :dataset_set)
    assert :more = Daemon.parse("leader\nDone", :state)
    assert :more = Daemon.parse("leader\nDo", :state)
    assert {:ok, _} = Daemon.parse(String.duplicate("v", 1024) <> "\nDone\n", :version)
  end

  property "WTH-S02 WTH-V03 every prefix of a valid response remains incomplete until the marker ends" do
    check all(
            role <- member_of(~w(disabled detached child router leader)),
            echo <- boolean(),
            crlf <- boolean()
          ) do
      newline = if crlf, do: "\r\n", else: "\n"
      bytes = if(echo, do: "state" <> newline, else: "") <> role <> newline <> "Done" <> newline

      for length <- 0..(byte_size(bytes) - 1) do
        assert :more = Daemon.parse(binary_part(bytes, 0, length), :state)
      end

      assert {:ok, ^role} = Daemon.parse(bytes, :state)
    end
  end

  test "WTH-S02 WTH-V03 malformed or extra output closes the socket before reuse" do
    for {bytes, code} <- [
          {"state\nleader\nrouter\nDone\n", :invalid_response},
          {"leader\nDone\nextra\n", :invalid_response},
          {"leader\nDone\nDone\n", :invalid_response},
          {"bogus\nDone\n", :invalid_response},
          {"leader\n", :timeout},
          {<<255, "\n">>, :invalid_response},
          {String.duplicate("x", 4096) <> "\n" <> String.duplicate("x", 4096) <> "\n",
           :response_limit}
        ] do
      {path, task} =
        peer(fn socket ->
          assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
          :ok = :gen_tcp.send(socket, bytes)
          assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
        end)

      assert {:ok, handle} = Daemon.connect(socket_path: path)
      assert {:error, %{code: ^code}} = Daemon.request(handle, %{type: :state}, 100)
      assert {:error, %{code: :transport_closed}} = Daemon.request(handle, %{type: :state}, 100)
      assert :ok = Daemon.disconnect(handle)
      Task.await(task)
    end
  end

  test "WTH-S02 WTH-V03 rejected request shapes cause no command writes" do
    {path, task} =
      peer(fn socket ->
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)

    for message <- [
          %{type: :state, args: "leader"},
          %{type: :state, unknown: true},
          %{type: :dataset_set},
          [:state],
          nil
        ] do
      assert {:error, _} = Address.validate_message(message)
      assert {:error, _} = Daemon.request(handle, message, 1000)
    end

    assert {:error, _} = Daemon.request(%{socket: :forged, owner: self()}, %{type: :state}, 1000)
    assert {:error, _} = Daemon.disconnect(%{socket: :forged, owner: self()})
    assert :ok = Daemon.disconnect(handle)
    Task.await(task)
  end

  test "WTH-S02 WTH-V03 a forged owner does not grant another process socket access" do
    {path, task} = peer(fn socket -> assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000) end)
    assert {:ok, handle} = Daemon.connect(socket_path: path)

    Task.await(
      Task.async(fn ->
        forged = %{handle | owner: self()}
        assert {:error, %{code: :wrong_owner}} = Daemon.request(forged, %{type: :state}, 100)
        assert {:error, %{code: :wrong_owner}} = Daemon.disconnect(forged)
      end)
    )

    assert :ok = Daemon.disconnect(handle)
    Task.await(task)
  end

  test "WTH-S02 WTH-V03 pending unsolicited output is rejected before the next command" do
    parent = self()

    {path, task} =
      peer(fn socket ->
        assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
        :ok = :gen_tcp.send(socket, "leader\nDone\n")

        receive do
          :inject -> :ok = :gen_tcp.send(socket, "router\nDone\n")
        after
          1000 -> flunk("injection was not requested")
        end

        send(parent, :injected)
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert {:ok, "leader"} = Daemon.request(handle, %{type: :state}, 1000)
    send(task.pid, :inject)
    assert_receive :injected, 1000
    assert {:error, %{code: :invalid_response}} = Daemon.request(handle, %{type: :state}, 1000)
    assert :ok = Daemon.disconnect(handle)
    Task.await(task)
  end

  test "WTH-S02 WTH-V03 invalid options and non-TCP handles fail without raising" do
    for opts <- [
          [socket_path: "x", timeout: 1000, timeout: 1000],
          [{:socket_path, "x"} | :bad],
          List.duplicate({:socket_path, "x"}, 1000)
        ] do
      assert {:error, %{code: :invalid_options}} = Daemon.connect(opts)
    end

    assert {:ok, udp} = :gen_udp.open(0, active: false)
    handle = %{socket: udp, owner: self()}
    assert {:error, %{code: :invalid_request}} = Daemon.request(handle, %{type: :state}, 100)
    assert {:error, %{code: :invalid_request}} = Daemon.disconnect(handle)
    :gen_udp.close(udp)
  end

  test "WTH-S02 WTH-V03 owner death closes an in-flight read without stopping the borrowed peer" do
    parent = self()

    {path, task} =
      peer(fn socket ->
        assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
        send(parent, :pending)
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
        :borrowed_peer_survived
      end)

    owner =
      spawn(fn ->
        {:ok, handle} = Daemon.connect(socket_path: path)
        Daemon.request(handle, %{type: :state}, 60_000)
      end)

    monitor = Process.monitor(owner)
    assert_receive :pending, 1000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 1000
    assert :borrowed_peer_survived = Task.await(task, 1000)
  end

  test "WTH-S02 WTH-V03 a peer close before a command cannot become a successful read" do
    {path, task} = peer(fn _ -> :closed end)
    assert {:ok, handle} = Daemon.connect(socket_path: path)
    assert :closed = Task.await(task)
    assert {:error, %{code: :transport_closed}} = Daemon.request(handle, %{type: :state}, 1000)
    assert :ok = Daemon.disconnect(handle)
  end

  test "WTH-S02 WTH-V03 a complete response remains valid when the peer then closes" do
    parent = self()

    {path, task} =
      peer(fn socket ->
        assert {:ok, "state\n"} = :gen_tcp.recv(socket, 0, 1000)
        send(parent, :command_received)
        assert_receive :respond, 1000
        :ok = :gen_tcp.send(socket, "leader\nDone\n")
        :ok = :gen_tcp.shutdown(socket, :write)
        send(parent, :peer_closed)
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
      end)

    owner =
      spawn_link(fn ->
        {:ok, handle} = Daemon.connect(socket_path: path)
        result = Daemon.request(handle, %{type: :state}, 5000)
        closed = Daemon.request(handle, %{type: :state}, 1000)
        send(parent, {:owner, result, closed, Daemon.disconnect(handle)})
      end)

    # The owner is held after its command until the peer has written the response and its
    # close, so the read after the terminator always observes the close.
    assert_receive :command_received, 1000
    true = :erlang.suspend_process(owner)
    send(task.pid, :respond)
    assert_receive :peer_closed, 1000
    true = :erlang.resume_process(owner)

    assert_receive {:owner, {:ok, "leader"}, {:error, %{code: :transport_closed}}, :ok}, 5000
    Task.await(task)
  end

  test "WTH-S02 WTH-V03 an already-received frame cannot hide bytes after completion" do
    assert {:error, %{code: :invalid_response}} = Daemon.parse("leader\nDone\nextra", :state)

    assert {:error, %{code: :response_limit}} =
             Daemon.parse("leader\nDone\n" <> String.duplicate("x", 8193), :state)
  end

  defp peer(fun) do
    path =
      Path.join(
        System.tmp_dir!(),
        "wt-f-#{System.pid()}-#{System.unique_integer([:positive])}.sock"
      )

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
