defmodule Wotex.OPCUA.Native.CommandTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.OPCUA.Native.Command

  setup_all do
    dir =
      Path.join(
        System.tmp_dir!(),
        "wotex-opcua-build-command-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    compiler = System.find_executable("cc") || flunk("native tooling tests require a C11 compiler")
    root = Path.expand("../../../..", __DIR__)

    for {file, name} <- [
          {"priv/native/build_command.c", "guardian"},
          {"test/native/build_probe.c", "probe"}
        ] do
      {_, status} =
        System.cmd(
          compiler,
          [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            Path.join(root, file),
            "-o",
            Path.join(dir, name)
          ],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status == 0
    end

    %{dir: dir, guardian: Path.join(dir, "guardian"), probe: Path.join(dir, "probe")}
  end

  test "WOP-X02 actual guarded commands preserve output and exit status", c do
    assert {:ok, %{output: output, exit_status: 0}} = Command.run(c.guardian, step(c, "output"))
    assert output =~ "stdout\n"
    assert output =~ "stderr\n"
    assert {:error, :command_failed, %{exit_status: 7}} = Command.run(c.guardian, step(c, "exit"))
  end

  test "WOP-X02 timeout and output overflow remain failures after group cleanup", c do
    assert {:error, :command_deadline, %{exit_status: 124, output: pids}} =
             Command.run(c.guardian, %{step(c, "hang") | timeout_ms: 1000})

    assert_dead(pids)

    assert {:error, :command_output_limit, %{exit_status: 125, output: output}} =
             Command.run(c.guardian, %{step(c, "flood") | output_bytes: 4097})

    assert output == String.duplicate("x", 4097)
  end

  test "WOP-X02 successful root exit closes remaining owned descendants", c do
    assert {:ok, %{output: pids}} = Command.run(c.guardian, step(c, "background"))
    assert_dead(pids)
  end

  test "WOP-X02 invalid executable and working directory fail without an unbounded wait", c do
    assert {:error, :command_setup_failed, %{exit_status: nil}} =
             Command.run(c.guardian <> ".absent", step(c, "output"))

    assert {:error, :command_setup_failed, %{exit_status: 126}} =
             Command.run(c.guardian, %{step(c, "output") | executable: c.probe <> ".absent"})

    assert {:error, :command_setup_failed, %{exit_status: 126}} =
             Command.run(c.guardian, %{step(c, "output") | cwd: c.dir <> "/absent"})
  end

  test "WOP-X02 malformed command values fail before process creation", c do
    valid = step(c, "output")

    for bad <- [
          nil,
          %{},
          Map.put(valid, :unknown, true),
          %{valid | executable: nil},
          %{valid | cwd: "relative"},
          %{valid | args: nil},
          %{valid | args: [nil]},
          %{valid | args: [<<0>>]},
          %{valid | args: List.duplicate("x", 257)},
          %{valid | args: [String.duplicate("x", 8193)]},
          %{valid | env: nil},
          %{valid | env: [{"BAD=KEY", "x"}]},
          %{valid | env: [{"CC", nil}, {"CC", "other"}]},
          %{valid | env: [nil]},
          %{valid | timeout_ms: 0},
          %{valid | output_bytes: -1},
          %{valid | cleanup_ms: 5001}
        ] do
      assert {:error, :invalid_command, %{output: <<>>, exit_status: nil}} =
               Command.run(c.guardian, bad)
    end

    assert {:error, :invalid_command, _} = Command.run(nil, valid)
    assert {:error, :invalid_command, _} = Command.run("relative", valid)
  end

  test "WOP-X02 only explicit environment reaches the child", c do
    previous = System.get_env("WOTEX_NATIVE_TEST_CANARY")
    System.put_env("WOTEX_NATIVE_TEST_CANARY", "private-build-canary")

    on_exit(fn ->
      if previous,
        do: System.put_env("WOTEX_NATIVE_TEST_CANARY", previous),
        else: System.delete_env("WOTEX_NATIVE_TEST_CANARY")
    end)

    assert {:ok, %{output: "canary=absent\nlocale=C\n"}} =
             Command.run(c.guardian, step(c, "environment"))
  end

  test "WOP-X02 actual caller death closes its guarded descendant group", c do
    file = Path.join(c.dir, "owner-death.pids")
    request = %{step(c, "hang") | env: [{"WOTEX_NATIVE_TEST_PIDFILE", file}], timeout_ms: 10_000}
    owner = spawn(fn -> Command.run(c.guardian, request) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert eventually(fn -> File.regular?(file) and File.stat!(file).size > 0 end)
    pids = File.read!(file)
    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert eventually(fn -> dead?(pids) end)
  end

  test "WOP-X02 suspended caller cannot stop the guardian's native deadline", c do
    file = Path.join(c.dir, "suspended-owner.pids")
    parent = self()

    request = %{
      step(c, "hang")
      | env: [{"WOTEX_NATIVE_TEST_PIDFILE", file}],
        timeout_ms: 1000,
        cleanup_ms: 100
    }

    owner = spawn(fn -> send(parent, {:command_result, Command.run(c.guardian, request)}) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert eventually(fn -> File.regular?(file) and File.stat!(file).size > 0 end)
    pids = File.read!(file)
    true = :erlang.suspend_process(owner)
    assert eventually(fn -> dead?(pids) end)
    true = :erlang.resume_process(owner)
    assert_receive {:command_result, {:error, :command_deadline, _}}, 1000
  end

  defp eventually(check, remaining \\ 200)
  defp eventually(_, 0), do: false

  defp eventually(check, remaining) do
    if check.() do
      true
    else
      Process.sleep(10)
      eventually(check, remaining - 1)
    end
  end

  defp dead?(text) do
    pids = Regex.scan(~r/\d+/, text) |> List.flatten()

    length(pids) in 1..2 and
      Enum.all?(pids, fn pid ->
        {_, status} =
          System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true, env: [{"CFLAGS", nil}])

        status != 0
      end)
  end

  defp step(c, mode) do
    %{
      id: :fixture,
      executable: c.probe,
      args: [mode],
      cwd: c.dir,
      env: [{"CFLAGS", nil}, {"LC_ALL", "C"}],
      timeout_ms: 1000,
      output_bytes: 65_536,
      cleanup_ms: 500
    }
  end

  defp assert_dead(text) do
    pids = Regex.scan(~r/\d+/, text) |> List.flatten()
    assert length(pids) in 1..2

    for pid <- pids do
      {_, status} =
        System.cmd("/bin/kill", ["-0", pid],
          stderr_to_stdout: true,
          env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
        )

      assert status != 0
    end
  end
end
