Code.require_file("../../support/software/peer.exs", __DIR__)

defmodule Wotex.Matter.SoftwarePeerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{SoftwareCommand, SoftwarePeer}

  setup do
    root = Path.join(System.tmp_dir!(), "wotex-peer-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WMA-B01 peer readiness spans output chunks and stop reaps its exact child", %{root: root} do
    executable =
      script(
        root,
        "printf 'Server Listen'; sleep 0.03; printf 'ing...secret-canary'; exec sleep 30"
      )

    assert {:ok, peer} = SoftwarePeer.start(executable, [], options(root))
    assert Process.alive?(peer.command.pid)
    assert {:os_pid, child} = Port.info(peer.port, :os_pid)
    assert child == peer.os_pid
    assert :ok = SoftwarePeer.stop(peer)
    assert Port.info(peer.port) == nil
    assert reaped?(child)
    assert File.read!(Path.join(root, "peer.log")) == "Server Listening...secret-canary"
    assert Bitwise.band(File.stat!(Path.join(root, "peer.log")).mode, 0o777) == 0o600
    reference = peer.command.reference
    refute_receive {^reference, _}, 20
  end

  test "WMA-B01 missing readiness and early peer exit fail with no retained child", %{root: root} do
    for {name, body} <- [
          {"partial", "printf 'Server Listen'; exec sleep 30"},
          {"empty", "exec sleep 30"},
          {"failed", "exit 1"},
          {"finished", "exit 0"}
        ] do
      directory = Path.join(root, name)
      File.mkdir!(directory)
      executable = script(directory, "printf '%s' \"$$\" > \"$1\"; " <> body)
      pid_file = Path.join(directory, "pid")

      assert {:error, :peer_not_ready} =
               SoftwarePeer.start(
                 executable,
                 [pid_file],
                 Keyword.put(options(directory), :startup_timeout, 100)
               )

      if File.exists?(pid_file),
        do: assert(reaped?(pid_file |> File.read!() |> String.to_integer()))

      refute Enum.any?(
               Port.list(),
               &(Port.info(&1, :name) == {:name, String.to_charlist(executable)})
             )
    end
  end

  test "WMA-B01 a peer that exits after readiness cannot satisfy successful teardown", %{root: root} do
    executable = script(root, "printf 'Server Listening...'; sleep 0.05; exit 0")
    assert {:ok, peer} = SoftwarePeer.start(executable, [], options(root))
    monitor = Process.monitor(peer.command.pid)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    assert {:error, :peer_exited} = SoftwarePeer.stop(peer)
    assert reaped?(peer.os_pid)
  end

  @tag :late_peer_ready
  test "WMA-B01 queued readiness cannot revive an expired startup budget", %{root: root} do
    executable = script(root, "sleep 0.25; printf 'Server Listening...'; exec sleep 30")
    parent = self()

    owner =
      spawn(fn ->
        result =
          SoftwarePeer.start(executable, [], Keyword.put(options(root), :startup_timeout, 100))

        send(parent, {:late_peer_result, result})
        receive do: (:finish -> :ok)
      end)

    try do
      port = find_port(executable, System.monotonic_time(:millisecond) + 1_000)
      {:connected, worker} = Port.info(port, :connected)
      {:os_pid, child} = Port.info(port, :os_pid)
      :erlang.suspend_process(owner)
      :erlang.trace(worker, true, [:send, {:tracer, self()}])
      assert_receive {:trace, ^worker, :send, {_, :ready}, ^owner}, 1_000
      :erlang.resume_process(owner)
      assert_receive {:late_peer_result, {:error, :peer_not_ready}}, 1_000
      assert reaped?(child)
      assert Port.info(port) == nil
    after
      Process.exit(owner, :kill)
    end
  end

  test "WMA-B01 normal and abrupt caller exit reap an asynchronously owned peer", %{root: root} do
    for mode <- [:normal, :kill] do
      directory = Path.join(root, Atom.to_string(mode))
      File.mkdir!(directory)
      executable = script(directory, "printf 'Server Listening...'; exec sleep 30")
      parent = self()

      owner =
        spawn(fn ->
          {:ok, peer} = SoftwarePeer.start(executable, [], options(directory))
          send(parent, {:peer, peer})
          receive do: (:finish -> :ok)
        end)

      assert_receive {:peer, peer}, 1_000
      monitor = Process.monitor(peer.command.pid)

      try do
        if mode == :normal, do: send(owner, :finish), else: Process.exit(owner, :kill)
        assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
        assert reaped?(peer.os_pid)
        assert Port.info(peer.port) == nil
        assert File.exists?(Path.join(directory, "peer.log"))
      after
        Process.exit(owner, :kill)
      end
    end
  end

  test "WMA-B01 command readiness is one bounded notification and cancellation belongs to its reference",
       %{root: root} do
    executable = script(root, "printf 'Server Listening...Server Listening...'; exec sleep 30")
    command = SoftwareCommand.start(executable, [], options(root))
    reference = command.reference
    assert_receive {^reference, {:started, port, child}}, 1_000
    assert_receive {^reference, :ready}, 1_000
    refute_receive {^reference, :ready}, 20
    send(command.pid, {:cancel, make_ref()})
    refute_receive {^reference, {:error, _}}, 20
    assert {:error, :command_cancelled} = SoftwareCommand.cancel(command)
    assert Port.info(port) == nil
    assert reaped?(child)
  end

  test "a verbose peer remains usable after its log fills and can still be cancelled", %{root: root} do
    executable =
      script(
        root,
        "printf 'Server Listening...'; head -c 33554432 /dev/zero; printf done > \"$1\"; exec cat /dev/zero"
      )

    checkpoint = Path.join(root, "checkpoint")
    assert {:ok, peer} = SoftwarePeer.start(executable, [checkpoint], options(root))

    try do
      assert await_file(checkpoint, System.monotonic_time(:millisecond) + 2_000)
      assert Process.alive?(peer.command.pid)
      started = System.monotonic_time(:millisecond)
      assert :ok = SoftwarePeer.stop(peer)
      assert System.monotonic_time(:millisecond) - started <= 1_000
      assert reaped?(peer.os_pid)
      log = File.read!(Path.join(root, "peer.log"))
      assert byte_size(log) == 16_777_216
      assert String.ends_with?(log, "\n[software peer log truncated]\n")
      assert Bitwise.band(File.stat!(Path.join(root, "peer.log")).mode, 0o777) == 0o600
    after
      SoftwarePeer.stop(peer)
    end
  end

  defp await_file(path, deadline) do
    cond do
      File.regular?(path) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(5)
        await_file(path, deadline)
    end
  end

  test "continuous peer output cannot extend its absolute lifetime", %{root: root} do
    executable =
      script(
        root,
        "printf 'Server Listening...'; while [ ! -f \"$1\" ]; do sleep 0.01; done; exec cat /dev/zero"
      )

    gate = Path.join(root, "release-output")
    options = Keyword.put(options(root), :timeout, 1_500)
    started = System.monotonic_time(:millisecond)
    assert {:ok, peer} = SoftwarePeer.start(executable, [gate], options)
    reference = peer.command.reference

    try do
      File.write!(gate, "ready")
      assert_receive {^reference, {:error, :command_timeout}}, 2_500
      assert System.monotonic_time(:millisecond) - started <= 2_500
      assert reaped?(peer.os_pid)
      assert Port.info(peer.port) == nil
      assert File.stat!(Path.join(root, "peer.log")).size <= 16_777_216
    after
      SoftwarePeer.stop(peer)
    end
  end

  defp options(root),
    do: [
      startup_timeout: 1_000,
      timeout: 30_000,
      ready: "Server Listening...",
      log: Path.join(root, "peer.log")
    ]

  defp script(root, body) do
    path = Path.join(root, "peer")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n", [:exclusive])
    File.chmod!(path, 0o700)
    path
  end

  defp reaped?(child), do: reaped?(child, System.monotonic_time(:millisecond) + 1_000)

  defp find_port(executable, deadline) do
    case Enum.find(Port.list(), &(Port.info(&1, :name) == {:name, String.to_charlist(executable)})) do
      nil ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          find_port(executable, deadline)
        else
          flunk("peer child was not created")
        end

      port ->
        port
    end
  end

  defp reaped?(child, deadline) do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(child)], stderr_to_stdout: true) do
      {_, 0} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          reaped?(child, deadline)
        else
          false
        end

      _ ->
        true
    end
  end
end
