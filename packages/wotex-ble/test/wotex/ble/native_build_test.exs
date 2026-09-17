defmodule Wotex.BLE.NativeBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.Native.{Bootstrap, Build, BuildOperations, Command, Source, Workspace}

  @root Path.expand("../../..", __DIR__)
  @ready ~s({"backend":"bluez-native","event":"ready","revision":"2123ab772fbe97d1369fc9e179ea87c3469cf98f","version":1}\n)

  defmodule Operations do
    @moduledoc false

    # Deterministic process-local build operations. They create the files a
    # successful native toolchain would create; the production recipe, workspace
    # and manifest code under test remain unchanged.
    @ready_line ~s({"backend":"bluez-native","event":"ready","revision":"2123ab772fbe97d1369fc9e179ea87c3469cf98f","version":1}\n)

    @spec platform() :: term()
    def platform, do: setting(:platform, {:ok, "aarch64-unknown-linux-gnu"})

    @spec find_executable(String.t()) :: String.t() | nil
    def find_executable(name),
      do: if(name in setting(:missing_tools, []), do: nil, else: "/fake/bin/#{name}")

    @spec tool_digest(String.t()) :: term()
    def tool_digest(path) do
      if Path.basename(path) in setting(:unreadable_tools, []),
        do: {:error, :invalid_native_tool},
        else: {:ok, Base.encode16(:crypto.hash(:sha256, path), case: :lower)}
    end

    @spec bootstrap(String.t(), String.t(), String.t(), String.t()) :: term()
    def bootstrap(_, _, output, _) do
      record(:bootstrap)

      case setting(:bootstrap, :ok) do
        :ok ->
          File.write!(output, "guardian")
          {:ok, %{output: "", descendant_cleanup: :unverified}}

        :error ->
          {:error, :bootstrap_failed, %{output: "broken", descendant_cleanup: :unverified}}
      end
    end

    @spec fetch(map(), String.t()) :: term()
    def fetch(_, target) do
      record(:fetch)

      case setting(:fetch, :ok) do
        :ok -> File.write!(target, "archive")
        error -> error
      end
    end

    @spec extract(String.t(), String.t(), String.t()) :: term()
    def extract(archive, destination, root), do: Source.extract(archive, destination, root)

    @spec command(String.t(), map()) :: term()
    def command(_, step) do
      record(step.id)

      case Map.fetch(setting(:commands, %{}), step.id) do
        {:ok, result} -> result
        :error -> default(step)
      end
    end

    defp default(%{id: :target}), do: ok(setting(:target, "aarch64-linux-gnu") <> "\n")
    defp default(%{id: :decompress, args: args}), do: decompress(List.last(args))
    defp default(%{id: :compile, args: [_, build | _]}), do: compile(build)
    defp default(%{id: id, args: args}) when id in [:host, :guardian], do: output(args)

    defp default(%{id: :ready_probe}),
      do: {:error, :command_failed, %{output: @ready_line, exit_status: 1}}

    defp default(%{id: id, args: args})
         when id in [:audit_host, :audit_guardian, :audit_daemon, :audit_library],
         do: ok(Map.get(setting(:elf, %{}), id, elf(id, List.last(args))))

    defp default(%{id: id}), do: ok("#{id} 1.0\n")

    defp decompress(archive) do
      tree = archive <> ".tree"
      File.mkdir_p!(Path.join(tree, "dbus-1.16.2/dbus"))
      File.write!(Path.join(tree, "dbus-1.16.2/COPYING"), "license")
      File.write!(Path.join(tree, "dbus-1.16.2/dbus/dbus.h"), "header")
      tar = String.to_charlist(Path.rootname(archive))

      :ok =
        :erl_tar.create(tar, [{~c"dbus-1.16.2", String.to_charlist(Path.join(tree, "dbus-1.16.2"))}])

      File.rm_rf!(tree)
      ok("")
    end

    defp compile(build) do
      unless setting(:omit_library, false) do
        File.mkdir_p!(Path.join(build, "lib"))
        File.write!(Path.join(build, "lib/libdbus-1.so.3.38.3"), "library")
      end

      File.mkdir_p!(Path.join(build, "bin"))
      File.write!(Path.join(build, "bin/dbus-daemon"), "daemon")
      ok("compiled\n")
    end

    defp output(args) do
      [target | _] = Enum.drop_while(args, &(&1 != "-o")) |> tl()
      File.write!(target, Path.basename(target))
      ok("")
    end

    defp elf(:audit_host, _),
      do: readelf(["libdbus-1.so.3", "libstdc++.so.6", "libc.so.6"], "$ORIGIN/../lib", nil)

    defp elf(:audit_guardian, _), do: readelf(["libc.so.6"], nil, nil)

    defp elf(:audit_daemon, _),
      do: readelf(["libdbus-1.so.3", "libexpat.so.1", "libc.so.6"], "$ORIGIN/../lib:", nil)

    defp elf(:audit_library, _), do: readelf(["libc.so.6"], "$ORIGIN:", "libdbus-1.so.3")

    @spec readelf([String.t()], String.t() | nil, String.t() | nil) :: binary()
    def readelf(needed, runpath, soname) do
      [
        "ELF Header:\n  Machine:                           AArch64\n\nDynamic section:\n",
        Enum.map(needed, &" 0x01 (NEEDED)             Shared library: [#{&1}]\n"),
        if(soname, do: " 0x0e (SONAME)             Library soname: [#{soname}]\n", else: ""),
        if(runpath, do: " 0x1d (RUNPATH)            Library runpath: [#{runpath}]\n", else: "")
      ]
      |> IO.iodata_to_binary()
    end

    defp ok(output), do: {:ok, %{output: output, exit_status: 0}}

    defp setting(key, default), do: Map.get(Process.get(__MODULE__, %{}), key, default)

    defp record(id), do: Process.put({__MODULE__, :calls}, [id | calls()])

    @spec calls() :: [atom()]
    def calls, do: Process.get({__MODULE__, :calls}, [])
  end

  setup do
    # Workspaces reject symbolic-link ancestors, including a linked system temporary root.
    root =
      Path.join(
        real_path(System.tmp_dir!()),
        "wotex-ble-build-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Process.delete(Operations)
    Process.delete({Operations, :calls})
    %{root: root}
  end

  test "WBL-B01 build tasks accept exactly one absolute workspace argument", %{root: root} do
    workspace = Path.join(root, "native")
    assert {:ok, ^workspace} = Build.arguments(["--workspace", workspace])

    for invalid <- [
          [],
          ["--workspace"],
          ["--workspace", "relative"],
          ["--workspace", workspace, "--workspace", workspace],
          ["--workspace", workspace, "extra"],
          ["--other", workspace],
          ["--workspace", Path.join(root, "../escape")],
          ["--workspace", workspace <> <<0>>],
          ["--workspace", "/"],
          [:workspace]
        ] do
      assert {:error, :invalid_native_build_arguments} = Build.arguments(invalid)
    end

    assert_raise Mix.Error, ~r/usage: mix wotex.ble.native.build --workspace ABSOLUTE_PATH/, fn ->
      Mix.Tasks.Wotex.Ble.Native.Build.run(["--workspace", "relative"])
    end

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    assert :ok = Mix.Tasks.Wotex.Ble.Native.Build.run(["--workspace", workspace], Operations)
    assert_received {:mix_shell, :info, ["Native build completed: " <> ^workspace]}
    assert_received {:mix_shell, :info, ["Manifest: " <> _]}
    assert_received {:mix_shell, :info, ["Host: " <> _]}
    assert_received {:mix_shell, :info, ["Guardian: " <> _]}
    assert :ok = Mix.Tasks.Wotex.Ble.Native.Build.run(["--workspace", workspace], Operations)
    assert_received {:mix_shell, :info, ["Native build verified: " <> ^workspace]}
    configure(platform: {:error, :linux_required})

    assert_raise Mix.Error, "BLE native build failed: :linux_required", fn ->
      Mix.Tasks.Wotex.Ble.Native.Build.run(["--workspace", Path.join(root, "other")], Operations)
    end

    assert {:error, :invalid_build_workspace} = Build.run(:workspace)
    assert {:error, :invalid_build_workspace} = Build.run(workspace, "operations")
  end

  test "WBL-B01 host platform and missing tools fail before workspace mutation", %{root: root} do
    workspace = Path.join(root, "native")
    configure(platform: {:error, :linux_required})
    assert {:error, :linux_required} = Build.run(workspace, Operations)
    refute File.exists?(workspace)

    configure(missing_tools: ["xz"])
    assert {:error, {:missing_native_tool, "xz"}} = Build.run(workspace, Operations)
    refute File.exists?(workspace)
    configure(unreadable_tools: ["cmake"])
    assert {:error, :invalid_native_tool} = Build.run(workspace, Operations)
    refute File.exists?(workspace)
    assert Operations.calls() == []

    expected =
      if :os.type() == {:unix, :linux},
        do: {:ok, List.to_string(:erlang.system_info(:system_architecture))},
        else: {:error, :linux_required}

    assert BuildOperations.platform() == expected
  end

  test "WBL-B01 complete build binds pinned sources, tools, binaries, logs and ready probe", %{
    root: root
  } do
    workspace = Path.join(root, "native")
    assert {:ok, %{reused: false, manifest: manifest}} = Build.run(workspace, Operations)

    assert manifest["schema"] == "wotex.native-build"
    assert manifest["version"] == 1
    assert manifest["package"] == "wotex_ble"
    assert manifest == Jason.decode!(File.read!(Path.join(workspace, "native-manifest.json")))
    refute File.exists?(Path.join(workspace, ".wotex-ble-build.lock"))

    assert manifest["upstream_sources"]["libdbus"]["sha256"] ==
             "0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2"

    native = Path.join(@root, "priv/bluez/native")
    assert {:ok, files} = Source.file_hashes(native)
    assert manifest["source_files"] == files
    assert {:ok, manifest["source_revision"]} == Source.tree_digest(native)
    assert Map.has_key?(manifest["build_sources"], "build.ex")
    assert manifest["environment_allowlist"] == ~w(HOME LC_ALL PATH TMPDIR)
    assert manifest["toolchain"]["target_triple"] == "aarch64-linux-gnu"
    assert manifest["toolchain"]["executables"]["xz"]["path"] == "/fake/bin/xz"
    assert "-DCMAKE_BUILD_RPATH_USE_ORIGIN=ON" in manifest["arguments"]["configure"]
    assert "-Wl,-rpath,$ORIGIN/../lib" in manifest["arguments"]["host"]

    assert Enum.map(manifest["binaries"], &{&1["path"], &1["purpose"]}) == [
             {"output/bin/wotex-ble-host", "sdk_host"},
             {"output/bin/wotex-ble-guardian", "runtime_guardian"},
             {"output/bin/dbus-daemon", "private_bus_fixture"},
             {"output/lib/libdbus-1.so.3", "runtime_library"}
           ]

    for binary <- manifest["binaries"] do
      assert {:ok, binary["sha256"]} == Source.digest(Path.join(workspace, binary["path"]))
      assert binary["elf_machine"] == "AArch64"
    end

    assert Enum.at(manifest["binaries"], 3)["soname"] == "libdbus-1.so.3"
    assert File.read!(Path.join(workspace, "output/lib/libdbus-1.so.3")) == "library"

    assert Bitwise.band(File.stat!(Path.join(workspace, "output/bin/dbus-daemon")).mode, 0o777) ==
             0o755

    assert manifest["audit"]["ready_probe"]["frame"] == Jason.decode!(@ready)
    assert manifest["audit"]["ready_probe"]["exit_status"] == 1
    assert manifest["audit"]["advisory_scan"] == "not_performed"
    assert manifest["audit"]["python_runtime_dependency"] == false
    assert map_size(manifest["audit"]["logs"]) == 19

    for {id, log} <- manifest["audit"]["logs"] do
      assert {:ok, log["sha256"]} == Source.digest(Path.join(workspace, "logs/#{id}.log"))
      assert manifest["artifacts"]["logs/#{id}.log"] == log["sha256"]
    end

    calls = Operations.calls()
    assert {:ok, %{reused: true, manifest: ^manifest}} = Build.run(workspace, Operations)
    assert Operations.calls() == calls

    File.write!(Path.join(workspace, "output/bin/wotex-ble-host"), "replaced")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace, Operations)
  end

  test "WBL-B01 manifest reuse rejects forged fields and changed identity", %{root: root} do
    workspace = Path.join(root, "native")
    assert {:ok, %{manifest: manifest}} = Build.run(workspace, Operations)
    path = Path.join(workspace, "native-manifest.json")

    for forged <- [
          Map.put(manifest, "extra", true),
          Map.put(manifest, "schema", "other"),
          Map.put(manifest, "package", "other"),
          Map.put(manifest, "binaries", []),
          put_in(manifest, ["toolchain", "target_triple"], "x86_64-linux-gnu"),
          put_in(manifest, ["build_features", "sanitizers"], true),
          put_in(manifest, ["identity", "source_revision"], String.duplicate("0", 64))
        ] do
      File.write!(path, Jason.encode!(forged))
      assert {:error, :build_manifest_mismatch} = Build.run(workspace, Operations)
    end

    File.write!(path, Jason.encode!(manifest))
    assert {:ok, %{reused: true}} = Build.run(workspace, Operations)
    File.write!(path, "[]")
    assert {:error, :unrecognized_build_workspace} = Build.run(workspace, Operations)
  end

  test "WBL-B01 failed steps retain diagnostics and a lock that prevents reuse", %{root: root} do
    failures = [
      {[target: "x86_64-linux-gnu"], {:error, :target_architecture_mismatch}},
      {[bootstrap: :error], {:error, {:bootstrap_failed, :bootstrap}}},
      {[fetch: {:error, :source_hash_mismatch}], {:error, :source_hash_mismatch}},
      {[commands: %{configure: {:error, :command_failed, %{output: "no expat", exit_status: 1}}}],
       {:error, {:native_build_step_failed, :configure, 1}}},
      {[commands: %{compile: {:error, :command_deadline, %{output: "", exit_status: nil}}}],
       {:error, {:native_build_step_failed, :compile, nil}}},
      {[omit_library: true], {:error, :invalid_native_artifact}},
      {[
         elf: %{
           audit_host:
             Operations.readelf(["libpython3.11.so.1.0", "libdbus-1.so.3"], "$ORIGIN/../lib", nil)
         }
       ], {:error, :python_runtime_dependency}},
      {[
         elf: %{
           audit_library: Operations.readelf(["libc.so.6"], "/work/build/lib:", "libdbus-1.so.3")
         }
       ], {:error, :absolute_runpath}},
      {[elf: %{audit_host: Operations.readelf(["libc.so.6"], "$ORIGIN/../lib", nil)}],
       {:error, :invalid_native_artifact}},
      {[elf: %{audit_library: Operations.readelf(["libc.so.6"], nil, "libdbus-1.so.4")}],
       {:error, :invalid_native_artifact}},
      {[elf: %{audit_guardian: "not an ELF report"}], {:error, :invalid_native_artifact}},
      {[commands: %{ready_probe: {:error, :command_failed, %{output: "{}\n", exit_status: 1}}}],
       {:error, :invalid_ready_probe}},
      {[commands: %{ready_probe: {:ok, %{output: @ready, exit_status: 0}}}],
       {:error, {:native_build_step_failed, :ready_probe, 0}}}
    ]

    for {{settings, expected}, index} <- Enum.with_index(failures) do
      workspace = Path.join(root, "failure-#{index}")
      configure(settings)
      assert Build.run(workspace, Operations) == expected
      assert File.exists?(Path.join(workspace, ".wotex-ble-build.lock"))
      refute File.exists?(Path.join(workspace, "native-manifest.json"))
      assert {:error, :build_workspace_locked} = Build.run(workspace, Operations)
    end

    configure(
      commands: %{configure: {:error, :command_failed, %{output: "no expat", exit_status: 1}}}
    )

    workspace = Path.join(root, "diagnostic")
    assert {:error, _} = Build.run(workspace, Operations)
    assert File.read!(Path.join(workspace, "logs/configure.log")) == "no expat"
  end

  test "WBL-B01 workspaces reject unrelated, linked and malformed build inputs", %{root: root} do
    identity = identity()
    unrelated = Path.join(root, "unrelated")
    File.mkdir_p!(unrelated)
    File.write!(Path.join(unrelated, "file"), "user data")

    assert {:error, :unrecognized_build_workspace} =
             Workspace.run(unrelated, identity, ["artifact"], fn -> flunk("builder ran") end)

    assert File.read!(Path.join(unrelated, "file")) == "user data"
    File.ln_s!(root, Path.join(root, "link"))

    assert {:error, :invalid_build_workspace} =
             Workspace.run(Path.join(root, "link/native"), identity, ["artifact"], fn ->
               flunk("builder ran")
             end)

    empty = Path.join(root, "empty")
    File.mkdir_p!(empty)

    assert {:ok, %{reused: false}} =
             Workspace.run(empty, identity, ["artifact"], fn ->
               File.write!(Path.join(empty, "artifact"), "a")
               {:ok, %{}}
             end)

    unreadable = Path.join(root, "unreadable")
    File.mkdir_p!(unreadable)
    File.chmod!(unreadable, 0o000)

    try do
      assert {:error, :invalid_build_workspace} =
               Workspace.run(unreadable, identity, ["artifact"], fn -> flunk("builder ran") end)
    after
      File.chmod!(unreadable, 0o700)
    end

    file = Path.join(root, "regular")
    File.write!(file, "")

    for {path, identity, artifacts} <- [
          {file, identity, ["artifact"]},
          {"relative", identity, ["artifact"]},
          {Path.join(root, "a"), Map.delete(identity, "arguments"), ["artifact"]},
          {Path.join(root, "a"), identity, []},
          {Path.join(root, "a"), identity, ["artifact", "artifact"]},
          {Path.join(root, "a"), identity, ["../artifact"]},
          {Path.join(root, "a"), identity, ["native-manifest.json"]},
          {Path.join(root, "a"), identity, Enum.map(1..65, &"artifact-#{&1}")},
          {Path.join(root, "a"), Map.put(identity, "bad", {:tuple}), ["artifact"]}
        ] do
      assert {:error, _} = Workspace.run(path, identity, artifacts, fn -> flunk("builder ran") end)
    end

    assert {:error, :invalid_build_workspace} =
             Workspace.run(file, identity, ["artifact"], :builder)

    changed = Path.join(root, "changed")

    assert {:error, :build_workspace_changed} =
             Workspace.run(changed, identity, ["artifact"], fn -> :unexpected end)

    missing = Path.join(root, "missing")

    assert {:error, :invalid_build_artifact} =
             Workspace.run(missing, identity, ["artifact"], fn -> {:ok, %{}} end)

    linked = Path.join(root, "linked-artifact")

    assert {:error, :invalid_build_artifact} =
             Workspace.run(linked, identity, ["artifact"], fn ->
               File.ln_s!(file, Path.join(linked, "artifact"))
               {:ok, %{}}
             end)

    oversized = Path.join(root, "oversized")

    assert {:error, :invalid_build_manifest} =
             Workspace.run(oversized, identity, ["artifact"], fn ->
               File.write!(Path.join(oversized, "artifact"), "a")
               {:ok, %{"large" => String.duplicate("x", 1_048_576)}}
             end)
  end

  test "WBL-B01 command guardian bounds output, time and argument vectors", %{root: root} do
    guardian = guardian!(root)
    shell = System.find_executable("sh")

    step = fn args, overrides ->
      Map.merge(
        %{
          id: :probe,
          executable: shell,
          args: args,
          cwd: root,
          env: [{"PATH", "/usr/bin:/bin"}, {"WOTEX_BUILD_VALUE", "value"}, {"UNSET", nil}],
          timeout_ms: 5000,
          output_bytes: 65_536,
          cleanup_ms: 1000
        },
        overrides
      )
    end

    assert {:ok, %{output: "value\n", exit_status: 0}} =
             Command.run(guardian, step.(["-c", "echo \"$WOTEX_BUILD_VALUE\""], %{}))

    assert {:error, :command_failed, %{exit_status: 3}} =
             Command.run(guardian, step.(["-c", "exit 3"], %{}))

    assert {:error, :command_output_limit, _} =
             Command.run(guardian, step.(["-c", "yes"], %{output_bytes: 1024}))

    assert {:error, :command_deadline, _} =
             Command.run(guardian, step.(["-c", "sleep 5"], %{timeout_ms: 100, cleanup_ms: 100}))

    for invalid <- [
          step.([], %{timeout_ms: 600_001}),
          step.([], %{cleanup_ms: 0}),
          step.([], %{output_bytes: 16_777_217}),
          step.([], %{executable: "sh"}),
          step.([], %{cwd: "relative"}),
          step.([<<0>>], %{}),
          step.([], %{env: [{"lower", "value"}]}),
          step.([], %{env: [{"A", "1"}, {"A", "2"}]}),
          step.([], %{id: "probe"}),
          Map.put(step.([], %{}), :extra, true)
        ] do
      assert {:error, :invalid_command, %{exit_status: nil}} = Command.run(guardian, invalid)
    end

    assert {:error, :invalid_command, _} = Command.run(:guardian, step.([], %{}))

    assert {:error, :command_setup_failed, _} =
             Command.run(Path.join(root, "missing-guardian"), step.([], %{}))

    # The BEAM owner keeps its own output and time bounds even if a guardian fails to.
    flooding = script!(root, "flooding-guardian", "#!/bin/sh\nexec yes 2>/dev/null\n")

    assert {:error, :command_output_limit, %{exit_status: nil}} =
             Command.run(flooding, step.([], %{output_bytes: 4096}))

    stalled = script!(root, "stalled-guardian", "#!/bin/sh\nexec sleep 5\n")

    assert {:error, :command_deadline, %{exit_status: nil}} =
             Command.run(stalled, step.([], %{timeout_ms: 1, cleanup_ms: 1}))
  end

  test "WBL-B01 bootstrap compiles the guardian directly with bounded output", %{root: root} do
    compiler = System.find_executable("cc") || flunk("native build tests require cc")
    source = Path.join(@root, "priv/bluez/native/build_command.c")
    output = Path.join(root, "command")

    assert {:ok, %{output: "", descendant_cleanup: :unverified}} =
             Bootstrap.compile(compiler, source, output, root)

    broken = Path.join(root, "broken.c")
    File.write!(broken, "int main(void) { return missing; }\n")

    assert {:error, :bootstrap_failed, %{output: output}} =
             Bootstrap.compile(compiler, broken, Path.join(root, "broken"), root)

    assert output != ""
    assert {:error, :invalid_bootstrap, _} = Bootstrap.compile("cc", source, output, root)

    assert {:error, :bootstrap_failed, _} =
             Bootstrap.compile(Path.join(root, "missing-cc"), source, output, root)
  end

  test "WBL-B01 production operations delegate to bounded components", %{root: root} do
    assert BuildOperations.find_executable("definitely-not-a-wotex-tool") == nil
    file = Path.join(root, "tool")
    File.write!(file, "tool")
    assert BuildOperations.tool_digest(file) == {:ok, sha256("tool")}
    assert BuildOperations.tool_digest(root) == {:error, :invalid_native_tool}
    assert {:error, :invalid_source_download} = BuildOperations.fetch(%{}, file)
    assert {:error, :invalid_source_archive} = BuildOperations.extract(file, root, "dbus")
    assert {:error, :invalid_command, _} = BuildOperations.command("relative", %{})
    assert {:error, :invalid_bootstrap, _} = BuildOperations.bootstrap("cc", "a", "b", "c")
  end

  test "WBL-B01 ELF reports expose machine, needed libraries, runpath and soname" do
    report = Operations.readelf(["libdbus-1.so.3", "libc.so.6"], "$ORIGIN/../lib", "libx.so.1")

    assert Build.elf(report) ==
             {:ok,
              %{
                "elf_machine" => "AArch64",
                "needed_libraries" => ["libdbus-1.so.3", "libc.so.6"],
                "runpath" => "$ORIGIN/../lib",
                "soname" => "libx.so.1"
              }}

    assert {:ok, %{"runpath" => nil, "soname" => nil}} = Build.elf(Operations.readelf([], nil, nil))
    assert {:error, :invalid_native_artifact} = Build.elf("")
    assert {:error, :invalid_native_artifact} = Build.elf(:report)
  end

  defp configure(settings), do: Process.put(Operations, Map.new(settings))

  defp identity do
    %{
      "toolchain" => %{},
      "source_revision" => "r",
      "source_files" => %{},
      "build_sources" => %{},
      "upstream_sources" => %{},
      "arguments" => %{},
      "environment_allowlist" => [],
      "build_features" => %{}
    }
  end

  defp guardian!(root) do
    compiler = System.find_executable("cc") || flunk("native build tests require cc")
    output = Path.join(root, "command")
    source = Path.join(@root, "priv/bluez/native/build_command.c")
    assert {:ok, _} = Bootstrap.compile(compiler, source, output, root)
    output
  end

  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp script!(root, name, contents) do
    path = Path.join(root, name)
    File.write!(path, contents)
    File.chmod!(path, 0o700)
    path
  end

  defp real_path(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.reduce("/", fn part, parent ->
      current = Path.join(parent, part)

      case File.read_link(current) do
        {:ok, target} -> real_path(Path.expand(target, parent))
        {:error, _} -> current
      end
    end)
  end
end
