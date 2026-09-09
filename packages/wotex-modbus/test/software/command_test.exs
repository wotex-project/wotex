Code.require_file("../support/software/command.exs", __DIR__)

defmodule Wotex.Modbus.SoftwareCommandTest do
  @moduledoc false

  use ExUnit.Case, async: false
  @native Path.expand("../interop/native", __DIR__)

  setup_all do
    directory = temporary()
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    compiler = System.find_executable("cc") || flunk("native fixture tests require a C11 compiler")

    for name <- ["command", "probe", "command_fault"] do
      args = [
        "-std=c11",
        "-O1",
        "-g",
        "-Wall",
        "-Wextra",
        "-Werror"
      ]

      sources =
        if name == "command_fault",
          do: [
            "-Dsetpgid=wmb_fault_setpgid",
            Path.join(@native, "command.c"),
            Path.join(@native, "group_fault.c")
          ],
          else: [Path.join(@native, name <> ".c")]

      args = args ++ sources ++ ["-o", Path.join(directory, name)]

      port =
        Port.open({:spawn_executable, compiler}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])

      assert {_, 0} = drain(port, 15_000)
    end

    context = %{
      directory: directory,
      guardian: Path.join(directory, "command"),
      probe: Path.join(directory, "probe")
    }

    initialized = launch(context, "output", timeout: "10000")
    assert {output, 0} = drain(initialized, 15_000)
    assert output =~ "stdout\n" and output =~ "stderr\n"
    context
  end

  test "WMB-N02 WMB-N03 direct argv preserves combined output and child exit", context do
    assert {output, 0} = execute(context, "output")
    assert output =~ "stdout\n"
    assert output =~ "stderr\n"
    assert {"", 7} = execute(context, "exit")
  end

  test "WMB-N02 WMB-N03 inherited masks and child auto-reaping are reset before execution",
       context do
    assert {"signals-reset\n", 0} = execute(context, "signals", inherited: true)
    port = launch(context, "hang", inherited: true)
    assert_receive {^port, {:data, output}}, 1000
    {:os_pid, guardian_pid} = Port.info(port, :os_pid)

    assert {_, 0} =
             System.cmd("/bin/kill", ["-TERM", Integer.to_string(guardian_pid)],
               env: empty_environment()
             )

    assert {"", 127} = drain(port)
    assert_dead(pids(output))
  end

  test "WMB-N02 WMB-N03 repeated short children retain output and their exact exit", context do
    for iteration <- 1..100 do
      assert {"signals-reset\n", 0} =
               execute(context, "signals", inherited: rem(iteration, 2) == 0)

      assert {"", 7} = execute(context, "exit", inherited: rem(iteration, 2) == 1)
    end
  end

  test "WMB-N02 WMB-N03 failed parent group admission never executes the child", context do
    denied = Map.put(context, :guardian, Path.join(context.directory, "command_fault"))

    for _ <- 1..32 do
      assert {"", 126} = execute(denied, "signals", inherited: true)
    end
  end

  test "WMB-N02 WMB-N03 missing executable and invalid limits fail", context do
    assert {"", 126} =
             context
             |> Map.put(:probe, "/absent/wotex-fixture-probe")
             |> launch("output")
             |> drain()

    for invalid <- ["0", "-1", "1x", "600001", "18446744073709551616"] do
      assert {"", 126} = execute(context, "output", timeout: invalid)
    end
  end

  test "WMB-N02 WMB-N03 timeout kills TERM-resistant owned process group", context do
    started = System.monotonic_time(:millisecond)
    port = launch(context, "hang", timeout: "500")
    assert {output, 124} = drain(port)
    pids = pids(output)
    assert length(pids) == 2
    assert_dead(pids)
    assert System.monotonic_time(:millisecond) - started < 1500
  end

  test "WMB-N02 WMB-N03 successful root exit still kills background descendants", context do
    assert {output, 0} = execute(context, "background")
    assert_dead(pids(output))
  end

  test "WMB-N02 WMB-N03 stopped children remain owned until the command deadline", context do
    port = launch(context, "hang", timeout: "1000")
    assert_receive {^port, {:data, output}}, 1000
    [child, _] = children = pids(output)

    assert {_, 0} =
             System.cmd("/bin/kill", ["-STOP", Integer.to_string(child)], env: empty_environment())

    refute_receive {^port, {:exit_status, _}}, 100
    assert {"", 124} = drain(port)
    assert_dead(children)
  end

  test "WMB-N02 WMB-N03 output flood never emits beyond the exact bound", context do
    assert {output, 125} = execute(context, "flood", output: "4097")
    assert output == String.duplicate("x", 4097)
  end

  test "WMB-N02 WMB-N03 owner EOF releases a live process group", context do
    parent = self()

    owner =
      spawn(fn ->
        port = launch(context, "hang")
        send(parent, {:owned_port, port})

        receive do
          {^port, {:data, output}} -> send(parent, {:owned_processes, pids(output)})
        end

        receive do: (:remain -> :ok)
      end)

    assert_receive {:owned_port, port}, 1000
    assert_receive {:owned_processes, children}, 1000
    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert_dead(children)
    assert Port.info(port) == nil
  end

  test "WMB-N02 WMB-N03 suspended consumer and full pipe cannot block native deadline", context do
    parent = self()

    owner =
      spawn(fn ->
        port = launch(context, "flood", timeout: "500", output: "16777216")
        send(parent, {:suspended_port, port})
        receive do: (:finish -> send(parent, {:drained, drain(port)}))
      end)

    assert_receive {:suspended_port, port}, 1000
    true = :erlang.suspend_process(owner)
    Process.sleep(1100)
    assert Port.info(port) == nil
    assert {:messages, messages} = Process.info(owner, :messages)

    buffered_bytes =
      Enum.reduce(messages, 0, fn
        {^port, {:data, bytes}}, total -> total + byte_size(bytes)
        _, total -> total
      end)

    assert buffered_bytes > 0
    assert buffered_bytes <= 16_777_216
    true = :erlang.resume_process(owner)
    send(owner, :finish)
    assert_receive {:drained, {output, status}}, 1500
    assert byte_size(output) <= 16_777_216
    assert status in [124, 125]
  end

  test "WMB-N02 WMB-N03 terminating one command preserves another owned group", context do
    retained = launch(context, "hang")
    assert_receive {^retained, {:data, retained_output}}, 1000
    assert {failed_output, 124} = execute(context, "hang", timeout: "500")
    assert_dead(pids(failed_output))
    assert Port.info(retained) != nil

    for pid <- pids(retained_output) do
      assert {status, 0} =
               System.cmd("/bin/ps", ["-p", Integer.to_string(pid), "-o", "stat="],
                 env: empty_environment()
               )

      refute String.starts_with?(String.trim(status), "Z")
    end

    true = Port.close(retained)
    assert_dead(pids(retained_output))
  end

  test "WMB-N02 WMB-N03 guardian TERM preserves bounded child cleanup", context do
    port = launch(context, "hang")
    assert_receive {^port, {:data, output}}, 1000
    {:os_pid, guardian_pid} = Port.info(port, :os_pid)

    assert {_, 0} =
             System.cmd("/bin/kill", ["-TERM", Integer.to_string(guardian_pid)],
               env: empty_environment()
             )

    assert {"", 127} = drain(port)
    assert_dead(pids(output))
  end

  test "WMB-N02 WMB-N03 malformed owner input is terminal", context do
    port = launch(context, "hang")
    assert_receive {^port, {:data, output}}, 1000
    true = Port.command(port, "unexpected")
    assert {"", 126} = drain(port)
    assert_dead(pids(output))
  end

  test "WMB-N01 WMB-N03 advisory lease rejects overlap and releases on owner death", context do
    path = Path.join(context.directory, "workspace.lock")
    parent = self()

    owner =
      spawn(fn ->
        port = lock(context, path)

        receive do
          {^port, {:data, "wotex_fixture_lock\n"}} -> send(parent, {:lease_ready, port})
        end

        receive do: (:remain -> :ok)
      end)

    assert_receive {:lease_ready, first}, 1000
    assert {"", 130} = drain(lock(context, path))
    Process.exit(owner, :kill)
    assert_dead_lease(context, path, System.monotonic_time(:millisecond) + 1000)
    assert Port.info(first) == nil
    assert File.read!(path) == ""
  end

  test "WMB-N01 WMB-N03 advisory lease refuses unrelated content and symlinks", context do
    path = Path.join(context.directory, "unrelated.lock")
    File.write!(path, "retain")
    File.chmod!(path, 0o600)
    assert {"", 126} = drain(lock(context, path))
    link = Path.join(context.directory, "symlink.lock")
    File.ln_s!(path, link)
    assert {"", 126} = drain(lock(context, link))
    assert File.read!(path) == "retain"
  end

  test "WMB-N01 WMB-N03 acknowledged lease release permits immediate reacquisition", context do
    path = Path.join(context.directory, "acknowledged.lock")

    for _ <- 1..10 do
      port = lock(context, path)
      assert_receive {^port, {:data, "wotex_fixture_lock\n"}}, 1000
      assert Port.command(port, "R")
      assert {"wotex_fixture_unlocked\n", 0} = drain(port)
    end

    assert File.read!(path) == ""
  end

  test "WMB-N01 WMB-N03 lease readiness accumulates split bytes and rejects malformed output",
       context do
    alias Wotex.Modbus.SoftwareCommand
    assert {:ok, port} = SoftwareCommand.lease(context.probe, "/split")
    assert :ok = SoftwareCommand.release_lease(port)

    for path <- ["/invalid", "/extra"] do
      started = System.monotonic_time(:millisecond)
      assert {:error, :invalid_workspace_lock} = SoftwareCommand.lease(context.probe, path)
      assert System.monotonic_time(:millisecond) - started < 500
    end
  end

  defp lock(context, path) do
    Port.open({:spawn_executable, context.guardian}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: ["--lock", path]
    ])
  end

  defp assert_dead_lease(context, path, deadline) do
    port = lock(context, path)

    receive do
      {^port, {:data, "wotex_fixture_lock\n"}} ->
        Port.close(port)

      {^port, {:exit_status, 130}} ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: flunk("native advisory lease remains live")

        Process.sleep(10)
        assert_dead_lease(context, path, deadline)
    after
      1000 -> flunk("native lease command did not answer")
    end
  end

  defp execute(context, mode, options \\ []) do
    context
    |> launch(mode, options)
    |> drain()
  end

  defp empty_environment, do: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)

  defp launch(context, mode, options \\ []) do
    arguments = [
      Keyword.get(options, :timeout, "2000"),
      Keyword.get(options, :output, "65536"),
      "400",
      context.directory,
      context.probe,
      mode
    ]

    {executable, arguments} =
      if Keyword.get(options, :inherited, false),
        do: {context.probe, ["--inherited", context.guardian | arguments]},
        else: {context.guardian, arguments}

    Port.open({:spawn_executable, executable}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: arguments
    ])
  end

  defp drain(port, timeout \\ 3000),
    do: collect(port, [], System.monotonic_time(:millisecond) + timeout)

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, bytes}} -> collect(port, [bytes | output], deadline)
      {^port, {:exit_status, code}} -> {IO.iodata_to_binary(Enum.reverse(output)), code}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        if Port.info(port), do: Port.close(port)
        flunk("native fixture command exceeded its test deadline")
    end
  end

  defp pids(output) do
    output
    |> String.split()
    |> Enum.map(&String.to_integer/1)
  end

  defp assert_dead(pids), do: dead(pids, System.monotonic_time(:millisecond) + 1500)

  defp dead(pids, deadline) do
    running =
      Enum.filter(pids, fn pid ->
        {output, _} =
          System.cmd("/bin/ps", ["-p", Integer.to_string(pid), "-o", "stat="],
            env: empty_environment()
          )

        status = String.trim(output)
        status != "" and not String.starts_with?(status, "Z")
      end)

    cond do
      running == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("owned native processes remain: #{inspect(running)}")

      true ->
        Process.sleep(10)
        dead(running, deadline)
    end
  end

  defp temporary,
    do: Path.join(System.tmp_dir!(), "wotex-modbus-command-#{System.unique_integer([:positive])}")
end
