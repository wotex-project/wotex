defmodule Wotex.CoAP.SoftwareRunTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wotex.Coap.Software.Run, as: RunTask
  alias Wotex.CoAP.Software.{Build, Run}

  @hash String.duplicate("a", 64)

  defmodule Verifier do
    @moduledoc false

    @spec verify(String.t()) :: term()
    def verify(_), do: Process.get({__MODULE__, :result})

    @spec result(term()) :: term()
    def result(value), do: Process.put({__MODULE__, :result}, value)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :result})
  end

  defmodule Operations do
    @moduledoc false

    @spec command(term(), term(), term(), term(), keyword()) :: term()
    def command(guardian, executable, arguments, cwd, options) do
      send(self(), {:software_command, guardian, executable, arguments, cwd, options})
      Process.get({__MODULE__, :result})
    end

    @spec result(term()) :: term()
    def result(value), do: Process.put({__MODULE__, :result}, value)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :result})
  end

  defmodule RaisingVerifier do
    @moduledoc false

    @spec verify(String.t()) :: no_return()
    def verify(_), do: raise(ArgumentError, "invalid receipt")
  end

  defmodule TaskRun do
    @moduledoc false

    @spec run(String.t()) :: term()
    def run(_), do: Process.get({__MODULE__, :result})

    @spec result(term()) :: term()
    def result(value), do: Process.put({__MODULE__, :result}, value)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :result})
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "wotex-coap-software-run-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    Verifier.reset()
    Operations.reset()
    TaskRun.reset()

    on_exit(fn ->
      Verifier.reset()
      Operations.reset()
      TaskRun.reset()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "WCO-N05 accepts one built absolute workspace and records a bounded passing result", %{
    root: root
  } do
    Verifier.result({:ok, %{manifest: manifest(), reused: true}})
    Operations.result({:ok, %{output: "437 tests passed\n", exit_status: 0}})

    assert {:ok, %{path: path, evidence: evidence}} = Run.run(root, Verifier, Operations)
    assert path == Path.join(root, "software-run/result.json")
    assert evidence["schema"] == "wotex.coap.software@1"
    assert evidence["status"] == "passed"
    assert evidence["failure"] == nil
    assert evidence["exit_status"] == 0
    assert evidence["toolchain"] =~ "Elixir"
    assert evidence["scenario_ids"] == Enum.sort(evidence["scenario_ids"])
    assert evidence["cleanup"]["peer_processes_retained"] == 0

    assert_receive {:software_command, guardian, mix, arguments, cwd, options}
    assert guardian == Path.join(root, "native/bin/build-command")
    assert Path.basename(mix) == "mix"
    assert cwd == File.cwd!()
    assert arguments == Enum.drop(evidence["command"], 1)
    assert options[:timeout] == 300_000
    assert options[:output] == 16_777_216
    assert options[:cleanup] == 5_000
    assert {"MIX_ENV", "test"} in options[:env]
    assert {"WOTEX_COAP_LIBCOAP_SERVER", Path.join(root, "bin/coap-server")} in options[:env]

    decoded = Jason.decode!(File.read!(path))
    assert decoded == evidence
    refute String.contains?(Enum.join(decoded["command"], " "), root)
    refute File.read!(path) =~ "fixture-key"

    assert {:error, :software_result_exists} = Run.run(root, Verifier, Operations)
  end

  test "WCO-N05 retains finite failure evidence and rejects unverified inputs", %{root: root} do
    assert {:error, :invalid_software_run_workspace} = Run.run(nil)
    assert {:error, :invalid_native_build_arguments} = Run.run("relative", Verifier, Operations)

    Verifier.result({:error, :software_build_required})
    assert {:error, :software_build_required} = Run.run(root, Verifier, Operations)

    Verifier.result({:ok, %{manifest: %{}, reused: true}})
    assert {:error, :invalid_software_manifest} = Run.run(root, Verifier, Operations)

    invalid_digest = put_in(manifest()["executables"]["coap-server"]["sha256"], nil)
    Verifier.result({:ok, %{manifest: invalid_digest, reused: true}})
    assert {:error, :invalid_software_manifest} = Run.run(root, Verifier, Operations)

    Verifier.result({:ok, %{manifest: manifest(), reused: true}})
    Operations.result({:error, :build_command_failed, %{output: "suite failed\n", exit_status: 2}})

    assert {:error, {:software_suite_failed, path, "build_command_failed"}} =
             Run.run(root, Verifier, Operations)

    result = Jason.decode!(File.read!(path))
    assert result["status"] == "failed"
    assert result["exit_status"] == 2
    assert result["cleanup"]["peer_processes_retained"] == nil
    assert File.read!(Path.join(root, "software-run/tests.log")) == "suite failed\n"
  end

  test "WCO-N05 reports unavailable tools, outputs and source inputs", %{root: root} do
    Verifier.result({:ok, %{manifest: manifest(), reused: true}})

    assert {:error, {:software_run_setup, "invalid receipt"}} =
             Run.run(root, RaisingVerifier, Operations)

    missing = Path.join(root, "missing.ex")
    assert {:error, :software_source_unavailable} = Run.source_hash([missing])

    blocked = Path.join(root, "blocked")
    File.write!(blocked, "ordinary file")
    assert {:error, :software_result_unavailable} = Run.run(blocked, Verifier, Operations)

    path = System.fetch_env!("PATH")
    mix = System.find_executable("mix")
    erl = System.find_executable("erl")
    System.put_env("PATH", "/no-software-tools")
    on_exit(fn -> System.put_env("PATH", path) end)
    assert {:error, :software_toolchain_unavailable} = Run.run(root, Verifier, Operations)

    tools = Path.join(root, "tools")
    File.mkdir!(tools)
    File.ln_s!(mix, Path.join(tools, "mix"))
    File.ln_s!(erl, Path.join(tools, "erl"))
    File.write!(Path.join(tools, "elixir"), "#!/bin/sh\nexit 1\n")
    File.chmod!(Path.join(tools, "elixir"), 0o700)
    System.put_env("PATH", tools)
    Operations.result({:ok, %{output: "15 tests passed\n", exit_status: 0}})

    assert {:error, :software_toolchain_unavailable} = Run.run(root, Verifier, Operations)
  end

  test "WCO-N05 child environment does not invent an absent path-dependency selector", %{root: root} do
    path_dependencies = System.get_env("WOTEX_PATH_DEPS")
    System.delete_env("WOTEX_PATH_DEPS")

    on_exit(fn ->
      if path_dependencies,
        do: System.put_env("WOTEX_PATH_DEPS", path_dependencies),
        else: System.delete_env("WOTEX_PATH_DEPS")
    end)

    Verifier.result({:ok, %{manifest: manifest(), reused: true}})
    Operations.result({:ok, %{output: "15 tests passed\n", exit_status: 0}})

    assert {:ok, _} = Run.run(root, Verifier, Operations)
    assert_receive {:software_command, _, _, _, _, options}
    refute Enum.any?(options[:env], &match?({"WOTEX_PATH_DEPS", _}, &1))
  end

  test "WCO-N05 task reports the retained result and every finite failure" do
    workspace = "/absolute/workspace"
    path = "/absolute/workspace/software-run/result.json"
    TaskRun.result({:ok, %{path: path}})

    assert capture_io(fn ->
             assert :ok = RunTask.execute(["--workspace", workspace], TaskRun)
           end) =~ "Software suite passed: #{path}"

    assert_raise Mix.Error, ~r/usage:/, fn ->
      RunTask.run(["--workspace", "relative"])
    end

    TaskRun.result({:error, {:software_suite_failed, path, "timeout"}})

    assert_raise Mix.Error, ~r/software suite failed \(timeout\); inspect/, fn ->
      RunTask.execute(["--workspace", workspace], TaskRun)
    end

    TaskRun.result({:error, :software_build_required})

    assert_raise Mix.Error, ~r/software run failed: :software_build_required/, fn ->
      RunTask.execute(["--workspace", workspace], TaskRun)
    end

    assert Mix.Project.config()[:aliases][:"wotex.software.run"] ==
             "wotex.coap.software.run"
  end

  test "WCO-N01 software verification never builds a missing workspace", %{root: root} do
    missing = Path.join(root, "missing")
    assert {:error, :software_build_required} = Build.verify(missing)
    refute File.exists?(missing)
    assert {:error, :invalid_build_workspace} = Build.verify(nil)
  end

  defp manifest do
    %{
      "schema" => "wotex.coap.native@1",
      "software_build" => %{
        "profile" => "software",
        "peer" => %{
          "features" => %{"dtls" => true, "oscore" => true, "version" => true}
        }
      },
      "executables" => %{
        "coap-server" => %{"sha256" => @hash},
        "wotex-coap-oscore" => %{"sha256" => @hash}
      },
      "workspace" => %{"artifacts" => %{}}
    }
  end
end
