defmodule Wotex.BLE.SoftwareFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.Software.{Build, Fixture, Operations, Run}

  defmodule Docker do
    @moduledoc false

    # Deterministic Docker and host operations for the software task contract.
    # Build and run code under test is unchanged; these functions create only the
    # files that the corresponding real command would create.

    @spec find_executable(String.t()) :: String.t() | nil
    def find_executable(name),
      do: if(name in setting(:missing, []), do: nil, else: "/fake/bin/#{name}")

    @spec tool_digest(String.t()) :: {:ok, String.t()}
    def tool_digest(path), do: {:ok, sha(path)}

    @spec bootstrap(String.t(), String.t(), String.t(), String.t()) :: term()
    def bootstrap(_, _, output, _) do
      File.write!(output, "guardian")
      {:ok, %{output: "", descendant_cleanup: :unverified}}
    end

    @spec transfer(String.t(), String.t(), String.t()) :: term()
    def transfer(url, target, _) do
      record({:transfer, url})

      if setting(:download_failure, false),
        do: {:error, :source_hash_mismatch},
        else: File.write!(target, url)
    end

    @spec digest(String.t()) :: term()
    def digest(path), do: Operations.digest(path)

    @spec command(String.t(), map()) :: term()
    def command(_, step) do
      record({:docker, hd(step.args)})
      Map.get(setting(:overrides, %{}), step.id, fn -> respond(step) end).()
    end

    @spec calls() :: list()
    def calls, do: Process.get({__MODULE__, :calls}, []) |> Enum.reverse()

    defp respond(%{args: ["build" | _]}), do: ok("built\n")

    defp respond(%{args: ["image", "inspect", reference]}),
      do:
        ok(
          Jason.encode!([
            %{"Id" => "sha256:" <> sha(reference), "Architecture" => "arm64", "Os" => "linux"}
          ])
        )

    defp respond(%{args: ["run", "--rm", "--network", "none", _, "cat", "/opt/wbl/build.json"]}),
      do: ok(Jason.encode!(%{"bluez_version" => "5.85"}))

    defp respond(%{args: ["run", "--rm", "--network", "none", _, "cat", _]}),
      do:
        ok(
          Jason.encode!(%{
            "schema" => "wotex.native-build",
            "binaries" => [%{"purpose" => "sdk_host", "sha256" => String.duplicate("a", 64)}]
          })
        )

    defp respond(%{args: ["export", "--output", path, _]}) do
      File.write!(path, "rootfs")
      ok("")
    end

    defp respond(%{
           args: ["run", "--rm", "--name", _, "--network", "none", "--mount", mount, _, "bash" | _]
         }) do
      File.write!(Path.join(source(mount), "rootfs.raw"), "raw")
      ok("")
    end

    defp respond(%{
           args: [
             "run",
             "--rm",
             "--name",
             _,
             "--network",
             "none",
             "--mount",
             _,
             _,
             "qemu-img" | rest
           ]
         }) do
      disk = List.last(rest)
      record({:disk, disk})
      ok("")
    end

    defp respond(%{
           args: [
             "run",
             "--rm",
             "--name",
             _,
             "--network",
             "none",
             "--mount",
             mount,
             _,
             "qemu-system-aarch64" | rest
           ]
         }) do
      ["local,id=fixture,path=/work/" <> relative, _] =
        rest
        |> Enum.drop_while(&(&1 != "-fsdev"))
        |> tl()
        |> Enum.take(1)
        |> hd()
        |> String.split(",security")

      directory = Path.join(source(mount), relative)
      lane = File.read!(Path.join(directory, "lane"))
      # The guest console is QEMU's own output; the shared directory holds results.
      ok(guest(directory, Map.get(setting(:guests, %{}), lane, :passed)))
    end

    defp respond(%{args: ["ps" | _]}), do: ok(setting(:remaining, ""))
    defp respond(_), do: ok("")

    defp guest(directory, outcome) do
      result = %{
        "result" => 0,
        "owned_processes_remaining" => 0,
        "virtual_controllers_remaining" => 0
      }

      counts = %{"passed" => 3}
      cases = for n <- 1..3, do: %{"name" => "case #{n}", "status" => "passed"}
      peer = %{"clean" => true, "statistics" => %{"native_senders" => []}}

      {result, counts, cases, peer, console} =
        case outcome do
          :passed -> {result, counts, cases, peer, "ok"}
          :guest -> {%{result | "result" => 1}, counts, cases, peer, "ok"}
          :panic -> {result, counts, cases, peer, "Kernel panic - not syncing"}
          :peer -> {result, counts, cases, %{peer | "clean" => false}, "ok"}
          :exunit -> {result, %{"passed" => 2, "failed" => 1}, cases, peer, "ok"}
          :cases -> {result, counts, Enum.take(cases, 2), peer, "ok"}
          :missing -> {nil, counts, cases, peer, "ok"}
        end

      if result, do: File.write!(Path.join(directory, "guest-result.json"), Jason.encode!(result))
      File.write!(Path.join(directory, "public-peer-result.json"), Jason.encode!(peer))

      File.write!(
        Path.join(directory, "exunit.json"),
        Jason.encode!(%{"counts" => counts, "cases" => cases})
      )

      File.write!(Path.join(directory, "disk.qcow2"), "overlay")
      console
    end

    defp source(mount) do
      ["type=bind", "src=" <> source, "target=/work"] = String.split(mount, ",")
      source
    end

    defp ok(output), do: {:ok, %{output: output, exit_status: 0}}
    defp setting(key, default), do: Map.get(Process.get(__MODULE__, %{}), key, default)

    defp record(call),
      do: Process.put({__MODULE__, :calls}, [call | Process.get({__MODULE__, :calls}, [])])

    defp sha(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  setup do
    root =
      Path.join(
        real_path(System.tmp_dir!()),
        "wotex-ble-software-#{System.unique_integer([:positive])}"
      )

    checkout = Path.join(root, "checkout/wotex-ble")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Process.delete(Docker)
    Process.delete({Docker, :calls})

    for package <- ~w(wotex wotex-runtime wotex-ble) do
      package_root = Path.join([root, "checkout", package])
      File.mkdir_p!(Path.join(package_root, "lib"))
      File.write!(Path.join(package_root, "mix.exs"), "#{package} project")
      File.write!(Path.join(package_root, "mix.lock"), "%{}")
      File.write!(Path.join(package_root, "lib/module.ex"), "#{package} module")
      File.mkdir_p!(Path.join(package_root, "_build/ignored"))
      File.write!(Path.join(package_root, "_build/ignored/file"), "ignored")
    end

    vendor = Path.join(checkout, "priv/bluez/native/vendor")
    File.mkdir_p!(vendor)
    File.write!(Path.join(vendor, "json.hpp"), "fixture json header")

    virtual = Path.join(checkout, "test/interop/virtual")
    File.mkdir_p!(virtual)

    for name <- ~w(Dockerfile.system Dockerfile.bluez Dockerfile.public guest.sh),
        do: File.write!(Path.join(virtual, name), name)

    File.chmod!(Path.join(virtual, "guest.sh"), 0o755)

    File.write!(Path.join(checkout, "test/interop/bluez_test.exs"), ~s(  test "one"\n))
    File.write!(Path.join(checkout, "test/interop/bluez_runtime_test.exs"), ~s(  test "two"\n))
    File.mkdir_p!(Path.join(checkout, "test/software"))

    File.write!(
      Path.join(checkout, "test/software/lifecycle_stress_test.exs"),
      ~s(  test "three"\n)
    )

    %{root: root, checkout: checkout, workspace: Path.join(root, "workspace")}
  end

  test "WBL-B01 virtual-controller peer uses the admitted native fixture stack" do
    virtual = Path.expand("../../interop/virtual", __DIR__)

    names =
      virtual
      |> File.ls!()
      |> Enum.sort()

    assert "public_peer.cpp" in names
    refute Enum.any?(names, &(Path.extname(&1) == ".py"))
    refute "requirements.txt" in names

    bluez = File.read!(Path.join(virtual, "Dockerfile.bluez"))
    system = File.read!(Path.join(virtual, "Dockerfile.system"))
    public = File.read!(Path.join(virtual, "public.sh"))
    manifest = File.read!(Path.join(virtual, "build_manifest.exs"))
    peer = File.read!(Path.join(virtual, "public_peer.cpp"))

    assert bluez =~ "public_peer.cpp"
    assert bluez =~ "pkg-config --cflags --libs gio-2.0"
    assert public =~ "/opt/wbl/bin/wotex-ble-public-peer"
    assert manifest =~ "/opt/wbl/bin/wotex-ble-public-peer"

    refute Enum.any?([bluez, system, public, manifest], &Regex.match?(~r/\bpython\d*\b/i, &1))
    refute Enum.any?([bluez, system, public, manifest], &Regex.match?(~r/\bpip\d*\b/i, &1))

    assert peer =~
             ~r/static GDBusMessage \*filter\(.*?gboolean incoming.*?if \(incoming &&.*?G_DBUS_MESSAGE_TYPE_METHOD_CALL\).*?return nullptr;.*?return message;/s
  end

  test "WBL-B01 software builder declares its HTTPS runtime applications" do
    applications = Application.spec(:wotex_ble, :applications)

    assert :inets in applications
    assert :ssl in applications
  end

  test "WBL-B01 fixture inputs bind package sources, modes and assets without build output",
       context do
    assert {:ok, inputs} = Fixture.inputs(context.checkout)
    assert inputs["wotex-ble/test/interop/virtual/guest.sh"]["mode"] == 0o755
    assert inputs["wotex/lib/module.ex"]["sha256"] == sha("wotex module")
    assert Map.has_key?(inputs, "wotex-runtime/mix.lock")
    refute Enum.any?(Map.keys(inputs), &String.contains?(&1, "_build"))
    assert Fixture.packages() == ~w(wotex wotex-runtime wotex-ble)
    assert {:ok, 3} = Fixture.public_case_count(context.checkout)

    File.ln_s!("module.ex", Path.join(context.root, "checkout/wotex/lib/link.ex"))
    assert {:error, :invalid_software_sources} = Fixture.inputs(context.checkout)
    File.rm!(Path.join(context.root, "checkout/wotex/lib/link.ex"))
    File.ln_s!("guest.sh", Path.join(context.checkout, "test/interop/virtual/link"))
    assert {:error, :invalid_software_sources} = Fixture.inputs(context.checkout)
    File.rm!(Path.join(context.checkout, "test/interop/virtual/link"))
    File.rm!(Path.join(context.root, "checkout/wotex-runtime/mix.lock"))
    assert {:error, :invalid_software_sources} = Fixture.inputs(context.checkout)
    assert {:error, :invalid_software_sources} = Fixture.inputs("relative")
    assert {:error, :invalid_software_sources} = Fixture.inputs(:root)
    File.rm!(Path.join(context.checkout, "test/interop/bluez_runtime_test.exs"))
    assert {:error, :invalid_software_sources} = Fixture.public_case_count(context.checkout)
  end

  test "WBL-B01 software build binds images, guest evidence and artifacts, then verifies read-only",
       context do
    assert {:ok, %{reused: false, manifest: manifest}} =
             Build.run(context.workspace, context.checkout, Docker)

    assert manifest["schema"] == "wotex.ble.software-build" and manifest["version"] == 1
    assert Map.keys(manifest["images"]) |> Enum.sort() == ~w(bluez public system)
    assert manifest["images"]["public"]["tag"] == Build.tag(context.workspace, :public)
    assert manifest["guest"] == %{"bluez_version" => "5.85"}
    assert manifest["native"]["schema"] == "wotex.native-build"
    assert manifest["identity"]["downloads"]["bluez.tar.gz"]["sha256"] =~ ~r/\A[0-9a-f]{64}\z/
    assert Map.has_key?(manifest["artifacts"], "rootfs.raw")
    assert Map.has_key?(manifest["artifacts"], "logs/image_public.log")
    refute File.exists?(Path.join(context.workspace, ".wotex-ble-software.lock"))

    assert File.read!(Path.join(context.workspace, "context/bluez/virtual/guest.sh")) == "guest.sh"

    assert File.read!(Path.join(context.workspace, "context/bluez/json.hpp")) ==
             "fixture json header"

    assert File.read!(Path.join(context.workspace, "context/public/source/wotex/lib/module.ex")) ==
             "wotex module"

    calls = Docker.calls()

    assert {:ok, %{reused: true, manifest: ^manifest}} =
             Build.run(context.workspace, context.checkout, Docker)

    assert Enum.count(Docker.calls() -- calls, &match?({:docker, "build"}, &1)) == 0
    assert {:ok, ^manifest} = Build.verified(context.workspace, context.checkout, Docker)

    File.write!(Path.join(context.workspace, "rootfs.raw"), "changed")

    assert {:error, :build_manifest_mismatch} =
             Build.run(context.workspace, context.checkout, Docker)

    File.write!(Path.join(context.workspace, "rootfs.raw"), "raw")
    assert {:ok, %{reused: true}} = Build.run(context.workspace, context.checkout, Docker)

    configure(overrides: %{verify_public: fn -> {:ok, %{output: "[]", exit_status: 0}} end})

    assert {:error, :build_manifest_mismatch} =
             Build.run(context.workspace, context.checkout, Docker)

    configure([])
    File.write!(Path.join(context.root, "checkout/wotex/lib/module.ex"), "changed")

    assert {:error, :build_manifest_mismatch} =
             Build.run(context.workspace, context.checkout, Docker)

    File.write!(Path.join(context.workspace, "software-manifest.json"), "[]")

    assert {:error, :unrecognized_build_workspace} =
             Build.run(context.workspace, context.checkout, Docker)
  end

  test "WBL-B01 software build admission and failures retain the lock without a manifest",
       context do
    assert {:error, :invalid_native_build_arguments} =
             Build.run("relative", context.checkout, Docker)

    assert {:error, :invalid_build_workspace} = Build.run(:workspace, context.checkout, Docker)
    configure(missing: ["docker"])

    assert {:error, {:missing_software_tool, "docker"}} =
             Build.run(context.workspace, context.checkout, Docker)

    refute File.exists?(context.workspace)

    unrelated = Path.join(context.root, "unrelated")
    File.mkdir_p!(unrelated)
    File.write!(Path.join(unrelated, "file"), "user")
    configure([])
    assert {:error, :unrecognized_build_workspace} = Build.run(unrelated, context.checkout, Docker)

    failures = [
      {[download_failure: true],
       {:software_download_failed, "bluez.tar.gz", :source_hash_mismatch}},
      {[
         overrides: %{
           image_bluez: fn ->
             {:error, :command_failed, %{output: "apt failure", exit_status: 1}}
           end
         }
       ], {:software_command_failed, :image_bluez, :command_failed, 1}},
      {[
         overrides: %{
           inspect_system: fn ->
             {:ok,
              %{output: ~s([{"Id":"sha256:x","Architecture":"amd64","Os":"linux"}]), exit_status: 0}}
           end
         }
       ], :invalid_software_image},
      {[overrides: %{guest_build: fn -> {:ok, %{output: "not json", exit_status: 0}} end}],
       :invalid_guest_build_evidence},
      {[
         overrides: %{
           export_rootfs: fn -> {:error, :command_deadline, %{output: "", exit_status: nil}} end
         }
       ], {:software_command_failed, :export_rootfs, :command_deadline, nil}}
    ]

    for {{settings, reason}, index} <- Enum.with_index(failures) do
      workspace = Path.join(context.root, "failure-#{index}")
      configure(settings)
      assert {:error, ^reason} = Build.run(workspace, context.checkout, Docker)
      assert File.exists?(Path.join(workspace, ".wotex-ble-software.lock"))
      refute File.exists?(Path.join(workspace, "software-manifest.json"))
      assert {:error, :build_workspace_locked} = Build.run(workspace, context.checkout, Docker)
    end

    assert File.read!(Path.join(context.root, "failure-1/logs/image_bluez.log")) == "apt failure"
    assert Enum.any?(Docker.calls(), &match?({:docker, "rm"}, &1))

    changed = Path.join(context.root, "changed")

    configure(
      overrides: %{
        image_public: fn ->
          File.write!(
            Path.join(context.root, "checkout/wotex/lib/module.ex"),
            "edited during build"
          )

          {:ok, %{output: "", exit_status: 0}}
        end
      }
    )

    assert {:error, :software_sources_changed} = Build.run(changed, context.checkout, Docker)
  end

  test "WBL-B01 software environment and owned tags are explicit" do
    tools = %{"docker" => %{"path" => "/opt/docker/bin/docker"}}
    environment = Build.environment(tools)
    assert {"PATH", "/opt/docker/bin:/usr/local/bin:/usr/bin:/bin"} in environment
    assert {"LC_ALL", "C"} in environment

    assert Enum.all?(environment, fn {name, _} ->
             name in ~w(PATH LC_ALL HOME DOCKER_CONFIG DOCKER_CONTEXT DOCKER_HOST)
           end)

    assert Build.tag("/a", :system) =~ ~r/\Awotex-ble-software:[0-9a-f]{16}-system\z/
    refute Build.tag("/a", :system) == Build.tag("/b", :system)
  end

  test "WBL-N03 software run boots both lanes and retains passing evidence", context do
    File.mkdir_p!(Path.join(context.root, "empty-run"))
    File.write!(Path.join(context.root, "empty-run/x"), "")

    assert {:error, :unrecognized_build_workspace} ==
             Run.run(Path.join(context.root, "empty-run"), context.checkout, Docker)

    assert {:error, :software_build_required} = Run.run(context.workspace, context.checkout, Docker)
    refute File.exists?(context.workspace)
    assert {:ok, _} = Build.run(context.workspace, context.checkout, Docker)
    assert {:ok, result} = Run.run(context.workspace, context.checkout, Docker)
    assert result["result"] == "passed" and result["expected_cases"] == 3
    assert result["native_host_sha256"] == String.duplicate("a", 64)

    assert Enum.map(result["lanes"], &{&1["lane"], &1["status"], &1["containers_remaining"]}) ==
             [{"latest", "passed", 0}, {"lower", "passed", 0}]

    for lane <- result["lanes"] do
      assert lane["exunit"] == %{"passed" => 3}
      assert Map.has_key?(lane["evidence"], "console.log")
      refute File.exists?(Path.join([result["directory"], lane["lane"], "disk.qcow2"]))
    end

    assert Jason.decode!(File.read!(Path.join(result["directory"], "result.json")))["result"] ==
             "passed"

    assert {:ok, %{reused: true}} = Build.run(context.workspace, context.checkout, Docker)
  end

  test "WBL-N03 software run rejects failed guest, panic, peer, ExUnit and cleanup evidence",
       context do
    assert {:ok, _} = Build.run(context.workspace, context.checkout, Docker)

    for outcome <- [:guest, :panic, :peer, :exunit, :cases, :missing] do
      configure(guests: %{"lower" => outcome})

      assert {:error, {:software_run_failed, directory}} =
               Run.run(context.workspace, context.checkout, Docker)

      result = Jason.decode!(File.read!(Path.join(directory, "result.json")))
      assert result["result"] == "failed"

      assert [%{"status" => "passed"}, %{"status" => "failed", "reason" => reason}] =
               result["lanes"]

      assert is_binary(reason)
    end

    configure(remaining: "abc123\n")

    assert {:error, {:software_run_failed, directory}} =
             Run.run(context.workspace, context.checkout, Docker)

    result = Jason.decode!(File.read!(Path.join(directory, "result.json")))

    assert Enum.all?(
             result["lanes"],
             &(&1["reason"] == "container_cleanup" and &1["containers_remaining"] == 2)
           )

    configure(
      overrides: %{
        console: fn -> {:error, :command_deadline, %{output: "slow", exit_status: nil}} end
      }
    )

    assert {:error, {:software_run_failed, _}} =
             Run.run(context.workspace, context.checkout, Docker)

    assert {:error, :invalid_build_workspace} = Run.run(:workspace, context.checkout, Docker)
  end

  test "WBL-N03 software Mix tasks report success and fixed usage errors", context do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    build = Mix.Tasks.Wotex.Ble.Software.Build
    run = Mix.Tasks.Wotex.Ble.Software.Run

    assert_raise Mix.Error, ~r/usage: mix wotex.ble.software.build/, fn -> build.run(["x"]) end
    assert_raise Mix.Error, ~r/usage: mix wotex.ble.software.run/, fn -> run.run(["x"]) end
    assert :ok = build.run(["--workspace", context.workspace], context.checkout, Docker)
    assert_received {:mix_shell, :info, ["Software build completed: " <> _]}
    assert :ok = build.run(["--workspace", context.workspace], context.checkout, Docker)
    assert_received {:mix_shell, :info, ["Software build verified: " <> _]}
    assert :ok = run.run(["--workspace", context.workspace], context.checkout, Docker)
    assert_received {:mix_shell, :info, ["Software run passed: " <> _]}
    configure(guests: %{"latest" => :panic})

    assert_raise Mix.Error, ~r/BLE software run failed/, fn ->
      run.run(["--workspace", context.workspace], context.checkout, Docker)
    end

    configure(missing: ["cc"])

    assert_raise Mix.Error, ~r/BLE software build failed/, fn ->
      build.run(["--workspace", Path.join(context.root, "new")], context.checkout, Docker)
    end
  end

  test "WBL-N03 lane evaluation requires exact guest, peer and ExUnit evidence", context do
    directory = Path.join(context.root, "lane")
    File.mkdir_p!(directory)
    assert {:error, {:missing_lane_evidence, "guest-result.json"}} = Run.evaluate(directory, 1)
    assert Run.arguments(["--workspace", directory]) == {:ok, directory}
    assert Operations.find_executable("definitely-not-a-wotex-tool") == nil
    assert {:error, :invalid_native_tool} = Operations.tool_digest(directory)
    assert {:error, :invalid_command, _} = Operations.command("relative", %{})
    assert {:error, :invalid_bootstrap, _} = Operations.bootstrap("cc", "a", "b", "c")
    assert {:error, :invalid_source_download} = Operations.transfer("http://x", "/a", "b")
  end

  defp configure(settings), do: Process.put(Docker, Map.new(settings))
  defp sha(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)

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
