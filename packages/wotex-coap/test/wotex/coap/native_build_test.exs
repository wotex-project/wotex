defmodule Wotex.CoAP.NativeBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wotex.Coap.Native.Build, as: BuildTask
  alias Wotex.CoAP.{Native.Build, Native.BuildOperations, Native.Workspace, NativeBackend}

  @revision "7cf7465b784baded4de183290c547d582becfd28"

  defmodule TaskBuild do
    @moduledoc false

    @spec run(String.t()) :: {:ok, map()} | {:error, term()}
    def run(_), do: Process.get({__MODULE__, :result})

    @spec result(term()) :: term()
    def result(value), do: Process.put({__MODULE__, :result}, value)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :result})
  end

  defmodule Operations do
    @moduledoc false

    alias Wotex.CoAP.Native.Workspace

    @revision "7cf7465b784baded4de183290c547d582becfd28"

    @patched %{
      "src/coap_oscore.c" => "601eb687f33794297c4571aa3481da0e480ec4165493d5081b52aa6511623ca6",
      "src/oscore/oscore_cbor.c" =>
        "d42ccc47c16a043a22d55a44d36802141a53c671def0fdcee37e6b6ccf53586c",
      "src/coap_block.c" => "a4aebab153fc94b5f8c3fb9c067f2768e840b0f73bc4326c1d08c64098f4fad6",
      "src/coap_net.c" => "838e16cffaa1c4b0d7d6d76ea293e51fab237f2ad1b3a7b9230846f1b66ef52d"
    }

    @spec resolve() :: {:ok, map()}
    def resolve do
      executable = System.find_executable("true")
      paths = Map.new(~w(cc cmake curl openssl patch pkg_config system)a, &{&1, executable})

      {:ok,
       %{
         paths: paths,
         hashes: hashes(paths),
         openssl_root: System.tmp_dir!(),
         target: {:darwin, :aarch64}
       }}
    end

    @spec identify(map(), String.t(), term()) :: {:ok, map()} | {:error, atom()}
    def identify(paths, openssl_root, target) do
      if Process.get({__MODULE__, :failure}) == :identify,
        do: {:error, :changed_toolchain},
        else:
          {:ok, %{paths: paths, hashes: hashes(paths), openssl_root: openssl_root, target: target}}
    end

    @spec direct(term(), [String.t()], term(), term()) ::
            {:ok, map()} | {:error, atom(), map()}
    def direct(_, arguments, _, _) do
      if Process.get({__MODULE__, :failure}) == :bootstrap do
        {:error, :build_command_failed, %{output: "bootstrap failed", exit_status: 7}}
      else
        output = output(arguments)
        File.write!(output, "fixture guardian")
        File.chmod!(output, 0o700)
        {:ok, %{output: "compiled guardian\n", exit_status: 0}}
      end
    end

    @spec command(term(), String.t(), [String.t()], term(), term()) ::
            {:ok, map()} | {:error, atom(), map()}
    def command(_, executable, arguments, _, _) do
      mode = Process.get({__MODULE__, :failure})

      case command_kind(executable, arguments, mode) do
        :version_failure -> version_failure()
        :feature -> feature(mode)
        :worker_probe -> worker(mode)
        :download -> download(arguments, mode)
        :build -> build(arguments)
        :compile -> compile(arguments)
        :dependencies -> dependencies(mode)
        :version -> version(mode)
      end
    end

    @spec extract(term(), String.t(), map()) :: :ok | {:error, atom()}
    def extract(_, destination, %{root: root}) do
      if Process.get({__MODULE__, :failure}) == :extract do
        {:error, :fixture_extract_failed}
      else
        for file <- Map.keys(@patched) do
          path = Path.join([destination, root, file])
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, "patched fixture")
        end

        File.mkdir_p!(Path.join([destination, root, "include"]))
        :ok
      end
    end

    @spec digest(String.t()) :: {:ok, String.t()} | {:error, term()}
    def digest(path) do
      suffix =
        Enum.find(Map.keys(@patched), fn file ->
          String.ends_with?(path, "/" <> file)
        end)

      cond do
        suffix && Process.get({__MODULE__, :failure}) == :patched ->
          {:ok, String.duplicate("0", 64)}

        suffix ->
          {:ok, @patched[suffix]}

        true ->
          Workspace.digest(path)
      end
    end

    @spec fail(atom()) :: term()
    def fail(mode), do: Process.put({__MODULE__, :failure}, mode)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :failure})

    defp hashes(paths) do
      Map.new(paths, fn {key, path} ->
        {:ok, digest} = Workspace.digest(path)
        {key, digest}
      end)
    end

    defp success(output), do: {:ok, %{output: output, exit_status: 0}}
    defp output(arguments), do: argument_after(arguments, "-o")

    defp argument_after(arguments, option) do
      arguments
      |> Enum.drop_while(&(&1 != option))
      |> Enum.at(1)
    end

    defp download?(arguments), do: "--output" in arguments

    defp dynamic?(["-L", executable]), do: String.ends_with?(executable, "wotex-coap-oscore")
    defp dynamic?(_), do: false

    defp command_kind(_, ["--version"], :version), do: :version_failure

    defp command_kind(executable, arguments, _) do
      cond do
        String.ends_with?(executable, "native-feature-probe") -> :feature
        String.ends_with?(executable, "native-worker-probe") -> :worker_probe
        download?(arguments) -> :download
        match?(["--build" | _], arguments) -> :build
        "-o" in arguments -> :compile
        dynamic?(arguments) -> :dependencies
        true -> :version
      end
    end

    defp version_failure,
      do: {:error, :build_command_failed, %{output: "version failed", exit_status: 7}}

    defp version(:version_change), do: success("changed tool version\n")
    defp version(_), do: success("fixture tool version\n")

    defp feature(:feature),
      do: success(~s({"backend":"libcoap","version":"wrong","oscore":false}\n))

    defp feature(_),
      do: success(~s({"backend":"libcoap","version":"libcoap 4.3.5","oscore":true}\n))

    defp worker(:worker), do: success(~s({"version":1,"event":"wrong"}\n))

    defp worker(_),
      do: success(~s({"version":1,"event":"ready","backend":"libcoap","revision":"#{@revision}"}\n))

    defp download(_, :download),
      do: {:error, :build_command_failed, %{output: "download failed", exit_status: 22}}

    defp download(arguments, _) do
      File.write!(argument_after(arguments, "--output"), "fixture archive")
      success("downloaded\n")
    end

    defp build(arguments) do
      build = Enum.at(arguments, 1)
      File.mkdir_p!(build)
      File.write!(Path.join(build, "libcoap-3.a"), "fixture static libcoap")
      success("built libcoap\n")
    end

    defp compile(arguments) do
      output = output(arguments)
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, "fixture executable #{Path.basename(output)}")
      File.chmod!(output, 0o700)
      success("compiled #{Path.basename(output)}\n")
    end

    defp dependencies(:dependencies), do: success("")
    defp dependencies(_), do: success("fixture => /usr/lib/fixture\n")
  end

  setup do
    Operations.reset()
    TaskBuild.reset()

    root =
      Path.join(System.tmp_dir!(), "wotex-coap-native-build-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      Operations.reset()
      TaskBuild.reset()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "WCO-N01 accepts exactly one absolute workspace before build I/O" do
    assert {:ok, "/absolute/workspace"} = Build.arguments(["--workspace", "/absolute/workspace"])

    for invalid <- [
          nil,
          [],
          ["--workspace"],
          ["--workspace", "relative"],
          ["--workspace", nil],
          ["--workspace", "/one", "--workspace", "/two"],
          ["--unknown", "/one"],
          ["--workspace", "/one/../two"],
          ["--workspace", "/one\nother"],
          ["--workspace", "/one" <> <<0>>]
        ] do
      assert {:error, :invalid_native_build_arguments} = Build.arguments(invalid)
    end

    assert {:error, :invalid_build_workspace} = Build.run(nil, Operations)
    assert_raise Mix.Error, ~r/usage:/, fn -> BuildTask.run(["--workspace", "relative"]) end
    assert Mix.Project.config()[:aliases][:"wotex.native.build"] == "wotex.coap.native.build"
  end

  test "WCO-N01 builds a complete content-bound manifest and verifies reuse", %{root: root} do
    assert {:ok, %{reused: false, manifest: manifest}} = Build.run(root, Operations)
    assert manifest["schema"] == "wotex.coap.native@1"

    assert manifest["backend"] == %{
             "name" => "libcoap",
             "version" => "4.3.5",
             "revision" => @revision
           }

    assert manifest["build"]["feature_probe"]["oscore"]
    assert manifest["build"]["worker_probe"]["event"] == "ready"
    assert length(manifest["build"]["steps"]) == 17
    assert manifest["build"]["sanitizers"] == []
    assert length(manifest["build"]["dynamic_dependencies"]) == 1
    assert length(manifest["build"]["source"]["patches"]) == 7
    assert map_size(manifest["build"]["tools"]["versions"]) == 7

    executable = Path.join(root, "bin/wotex-coap-oscore")
    manifest_path = Path.join(root, "native-manifest.json")
    assert {:ok, backend} = NativeBackend.verify(%{executable: executable, manifest: manifest_path})
    assert backend.sha256 == manifest["executables"]["wotex-coap-oscore"]["sha256"]
    refute File.exists?(Path.join(root, "sources"))
    refute File.exists?(Path.join(root, "build"))
    refute File.exists?(Path.join(root, "probe"))

    original = File.read!(manifest_path)
    assert {:ok, %{reused: true, manifest: ^manifest}} = Build.run(root, Operations)
    assert File.read!(manifest_path) == original

    Operations.fail(:version_change)
    assert {:error, :build_manifest_mismatch} = Build.run(root, Operations)
    Operations.reset()

    log = Path.join(root, "logs/worker-probe.log")
    File.write!(log, "tampered")
    assert {:error, :build_manifest_mismatch} = Build.run(root, Operations)
    assert File.read!(log) == "tampered"
  end

  test "WCO-N01 command and semantic failures never publish readiness", %{root: root} do
    for mode <- [
          :bootstrap,
          :version,
          :download,
          :extract,
          :patched,
          :feature,
          :worker,
          :dependencies,
          :identify
        ] do
      workspace = Path.join(root, Atom.to_string(mode))
      Operations.fail(mode)
      assert {:error, _} = Build.run(workspace, Operations)
      refute File.exists?(Path.join(workspace, "native-manifest.json"))
      Operations.reset()
    end
  end

  test "WCO-N01 unrelated workspace content remains untouched", %{root: root} do
    File.mkdir!(root)
    preserved = Path.join(root, "preserve")
    File.write!(preserved, "original")
    assert {:error, :unrecognized_build_workspace} = Build.run(root, Operations)
    assert File.read!(preserved) == "original"
    assert File.ls!(root) == ["preserve"]
  end

  test "WCO-N01 task reports completion, verified reuse and finite failure" do
    workspace = "/absolute/workspace"
    TaskBuild.result({:ok, %{reused: false}})

    assert capture_io(fn ->
             assert :ok = BuildTask.execute(["--workspace", workspace], TaskBuild)
           end) =~
             "Native build completed: #{workspace}"

    TaskBuild.result({:ok, %{reused: true}})

    output =
      capture_io(fn -> assert :ok = BuildTask.execute(["--workspace", workspace], TaskBuild) end)

    assert output =~ "Native build verified: #{workspace}"
    assert output =~ "Executable: #{workspace}/bin/wotex-coap-oscore"
    assert output =~ "Manifest: #{workspace}/native-manifest.json"

    TaskBuild.result({:error, :fixture_failure})

    assert_raise Mix.Error, ~r/CoAP native build failed: :fixture_failure/, fn ->
      BuildTask.execute(["--workspace", workspace], TaskBuild)
    end
  end

  test "WCO-N01 production operations delegate bounded tool, command, archive and digest work", %{
    root: root
  } do
    File.mkdir!(root)
    assert {:ok, tools} = BuildOperations.resolve()

    assert {:ok, identified} =
             BuildOperations.identify(tools.paths, tools.openssl_root, tools.target)

    assert identified.hashes == tools.hashes
    source = Path.join(root, "source.c")
    guardian = Path.join(root, "guardian")
    File.write!(source, "int main(void) { return 0; }\n")

    assert {:ok, %{exit_status: 0}} =
             BuildOperations.direct(
               tools.paths.cc,
               ["-std=c11", source, "-o", guardian],
               root,
               timeout: 10_000,
               output: 65_536,
               env: []
             )

    assert {:ok, digest} = BuildOperations.digest(guardian)
    assert digest =~ ~r/\A[0-9a-f]{64}\z/

    command_guardian = Path.join(root, "build-command")

    assert {:ok, %{exit_status: 0}} =
             BuildOperations.direct(
               tools.paths.cc,
               [
                 "-std=c11",
                 Path.expand("native/oscore/build_command.c"),
                 "-o",
                 command_guardian
               ],
               root,
               timeout: 10_000,
               output: 65_536,
               env: []
             )

    assert {:ok, %{exit_status: 0}} =
             BuildOperations.command(command_guardian, guardian, [], root,
               timeout: 10_000,
               output: 65_536,
               cleanup: 1_000,
               env: []
             )

    archive = Path.join(root, "source.tar.gz")

    :ok =
      :erl_tar.create(String.to_charlist(archive), [{~c"source/value", "content"}], [:compressed])

    destination = Path.join(root, "extracted")

    assert :ok =
             BuildOperations.extract(archive, destination, %{
               root: "source",
               sha256: Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)
             })

    assert File.read!(Path.join(destination, "source/value")) == "content"
  end
end
