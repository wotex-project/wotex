defmodule Wotex.CoAP.Native.BuildCommandTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP.Native.BuildCommand

  setup_all do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-build-command-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    compiler = System.find_executable("cc") || flunk("native build tests require a C11 compiler")
    guardian = Path.join(root, "build-command")

    assert {:ok, %{output: output, exit_status: 0}} =
             BuildCommand.direct(
               compiler,
               [
                 "-std=c11",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 "native/oscore/build_command.c",
                 "-o",
                 guardian
               ],
               File.cwd!(),
               env: [{"CFLAGS", false}, {"LDFLAGS", false}]
             )

    assert output == ""
    %{guardian: guardian, root: root}
  end

  test "WCO-N01 runs an argv-only command with exact combined output", context do
    printf = System.find_executable("printf") || flunk("printf is required")

    assert {:ok, %{output: "native-build\n", exit_status: 0}} =
             BuildCommand.run(
               context.guardian,
               printf,
               ["%s\n", "native-build"],
               context.root
             )
  end

  @tag timeout: 10_000
  test "WCO-N01 stops the complete process group at the command deadline", context do
    shell = System.find_executable("sh") || flunk("sh is required")
    pid_file = Path.join(context.root, "deadline.pid")
    started = System.monotonic_time(:millisecond)

    assert {:error, :build_command_deadline, %{exit_status: 124}} =
             BuildCommand.run(
               context.guardian,
               shell,
               ["-c", "echo $$ > \"$1\"; trap '' TERM; while :; do sleep 1; done", "sh", pid_file],
               context.root,
               timeout: 100,
               cleanup: 200
             )

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed in 100..1_500
    pid = String.trim(File.read!(pid_file))

    assert {:error, :build_command_failed, %{exit_status: 1}} =
             BuildCommand.direct("/bin/kill", ["-0", pid], context.root)
  end

  @tag timeout: 10_000
  test "WCO-N01 bounds combined command output and cleans up the producer", context do
    yes = System.find_executable("yes") || flunk("yes is required")

    assert {:error, :build_command_output_limit, %{output: output, exit_status: 125}} =
             BuildCommand.run(context.guardian, yes, ["bounded"], context.root,
               output: 4_096,
               cleanup: 200
             )

    assert byte_size(output) <= 4_096
    assert output != ""
  end

  @tag timeout: 10_000
  test "WCO-N01 passes unbounded output through and reaps the group when its owner leaves",
       context do
    shell = System.find_executable("sh") || flunk("sh is required")

    # 17,000,000 bytes exceed the 16 MiB relay bound; stderr joins stdout.
    passthrough =
      guardian(context, [
        "10000",
        "0",
        "200",
        context.root,
        shell,
        "-c",
        "head -c 17000000 /dev/zero; echo done >&2"
      ])

    assert {output_size, 0} = drain(passthrough, 0)
    assert output_size == 17_000_005

    pid_file = Path.join(context.root, "passthrough.pid")

    owned =
      guardian(context, [
        "10000",
        "0",
        "200",
        context.root,
        shell,
        "-c",
        "echo $$ > \"$1\"; trap '' TERM; while :; do sleep 1; done",
        "sh",
        pid_file
      ])

    pid = await_pid(pid_file, System.monotonic_time(:millisecond) + 2_000)

    assert {_, 0} =
             System.cmd("/bin/kill", ["-0", pid],
               stderr_to_stdout: true,
               env: cleared_environment()
             )

    # Closing the Port closes the guardian's stdin, as an exiting owner BEAM does.
    Port.close(owned)
    assert gone?(pid, System.monotonic_time(:millisecond) + 1_000)
  end

  test "WCO-N01 rejects invalid command paths before spawning", context do
    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.run(context.guardian, "relative", [], context.root)

    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.run(context.guardian, "/bin/echo", ["bad" <> <<0>>], context.root)

    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.run(context.guardian, "/bin/echo", [], "relative")

    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.run(context.guardian, "/bin/echo", [], context.root, timeout: 0)

    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.direct("relative", [], context.root)

    for {guardian, arguments, cwd} <- [
          {nil, [], context.root},
          {context.guardian, :arguments, context.root},
          {context.guardian, [], nil}
        ] do
      assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
               BuildCommand.run(guardian, "/bin/echo", arguments, cwd)
    end
  end

  test "WCO-N01 reports ordinary and setup command failures", context do
    shell = System.find_executable("sh") || flunk("sh is required")

    assert {:error, :build_command_failed, %{output: "rejected\n", exit_status: 23}} =
             BuildCommand.run(
               context.guardian,
               shell,
               ["-c", "printf 'rejected\\n'; exit 23"],
               context.root
             )

    nonexecutable = Path.join(context.root, "nonexecutable")
    File.write!(nonexecutable, "not an executable")

    assert {:error, :build_command_setup, %{output: "", exit_status: 126}} =
             BuildCommand.run(context.guardian, nonexecutable, [], context.root)

    assert {:error, :invalid_build_command, %{output: "", exit_status: 126}} =
             BuildCommand.direct(nonexecutable, [], context.root)
  end

  test "WCO-N01 preserves every reserved guardian failure", context do
    expected = [
      {127, :build_command_owner_lost},
      {128, :build_command_signal},
      {129, :build_command_cleanup}
    ]

    for {status, reason} <- expected do
      guardian = Path.join(context.root, "failure-#{status}")
      File.write!(guardian, "#!/bin/sh\nexit #{status}\n")
      File.chmod!(guardian, 0o700)

      assert {:error, ^reason, %{output: "", exit_status: ^status}} =
               BuildCommand.run(guardian, "/bin/echo", [], context.root)
    end
  end

  @tag timeout: 10_000
  test "WCO-N01 enforces its own output bound if a guardian violates the protocol", context do
    yes = System.find_executable("yes") || flunk("yes is required")
    guardian = Path.join(context.root, "overproducing-guardian")
    File.write!(guardian, "#!/bin/sh\nexec #{yes} overflow 2>/dev/null\n")
    File.chmod!(guardian, 0o700)

    assert {:error, :build_command_output_limit, %{output: output, exit_status: 125}} =
             BuildCommand.run(guardian, "/bin/echo", [], context.root, output: 1)

    assert output in ["", "o"]
  end

  @tag timeout: 10_000
  test "WCO-N01 bounds direct guardian bootstrap commands", context do
    sleep = System.find_executable("sleep") || flunk("sleep is required")
    started = System.monotonic_time(:millisecond)

    assert {:error, :build_command_deadline, %{output: "", exit_status: 124}} =
             BuildCommand.direct(sleep, ["30"], context.root, timeout: 20)

    assert (System.monotonic_time(:millisecond) - started) in 20..1_000
  end

  defp guardian(context, arguments) do
    Port.open({:spawn_executable, context.guardian}, [
      :binary,
      :exit_status,
      args: arguments
    ])
  end

  defp drain(port, size) do
    receive do
      {^port, {:data, bytes}} -> drain(port, size + byte_size(bytes))
      {^port, {:exit_status, status}} -> {size, status}
    after
      5_000 -> flunk("passthrough guardian produced no exit status")
    end
  end

  defp await_pid(path, deadline) do
    case File.read(path) do
      {:ok, text} when text != "" ->
        String.trim(text)

      _ ->
        if System.monotonic_time(:millisecond) >= deadline, do: flunk("no child pid")
        Process.sleep(10)
        await_pid(path, deadline)
    end
  end

  defp gone?(pid, deadline) do
    case System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true, env: cleared_environment()) do
      {_, 0} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(20)
          gone?(pid, deadline)
        else
          false
        end

      _ ->
        true
    end
  end

  defp cleared_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, nil} end)
end
