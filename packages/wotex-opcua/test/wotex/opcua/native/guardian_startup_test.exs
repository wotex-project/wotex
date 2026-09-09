defmodule Wotex.OPCUA.Native.GuardianStartupTest do
  @moduledoc false

  use ExUnit.Case, async: false

  setup_all do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-opcua-startup-#{Base.encode16(:crypto.strong_rand_bytes(12))}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    root = Path.expand("../../../..", __DIR__)
    compiler = System.find_executable("cc") || flunk("native startup tests require a C11 compiler")
    flags = ~w(-std=c11 -Wall -Wextra -Werror)
    fault = Path.join(root, "test/native/guardian_setpgid_fault.c")

    for {name, source} <- [
          {"command", "priv/native/build_command.c"},
          {"custody", "priv/native/custody.c"},
          {"check", "test/native/guardian_startup_check.c"}
        ] do
      source = Path.join(root, source)
      compile!(compiler, flags ++ [source, "-o", Path.join(directory, name)])

      if name != "check" do
        compile!(
          compiler,
          flags ++
            [
              "-Dsetpgid=wop_fault_setpgid",
              source,
              fault,
              "-o",
              Path.join(directory, name <> "_fault")
            ]
        )
      end
    end

    %{directory: directory}
  end

  for kind <- ~w(command custody) do
    @kind kind
    @tag timeout: 60_000
    test "WOP-X02 WOP-G01 #{@kind} owns the child group before 1000 short launches", context do
      assert run(context, @kind, @kind, "1000", "plain", "0") ==
               %{"launches" => 1000, "status" => "passed"}
    end

    @kind kind
    test "WOP-X02 WOP-G01 #{@kind} clears inherited ignored SIGCHLD and blocked signals", context do
      assert run(context, @kind, @kind, "32", "inherit", "0") ==
               %{"launches" => 32, "status" => "passed"}
    end

    @kind kind
    test "WOP-X02 WOP-G01 #{@kind} never releases a child after failed parent group admission",
         context do
      assert run(context, @kind <> "_fault", @kind, "32", "inherit", "126") ==
               %{"launches" => 32, "status" => "passed"}
    end
  end

  defp compile!(compiler, arguments) do
    {output, status} =
      System.cmd(compiler, arguments,
        stderr_to_stdout: true,
        env: [{"CFLAGS", nil}, {"LDFLAGS", nil}]
      )

    assert status == 0, output
  end

  defp run(context, executable, kind, count, inheritance, expected) do
    {output, status} =
      System.cmd(
        Path.join(context.directory, "check"),
        [
          Path.join(context.directory, executable),
          kind,
          count,
          inheritance,
          context.directory,
          expected
        ],
        stderr_to_stdout: true,
        env: [{"LC_ALL", "C"}]
      )

    assert status == 0, output
    Jason.decode!(output)
  end
end
