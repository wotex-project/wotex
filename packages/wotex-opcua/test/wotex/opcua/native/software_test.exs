defmodule Wotex.OPCUA.Native.SoftwareTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.OPCUA.Native.Software

  @python """
  #!/bin/sh
  case "$1 $2" in
    "-m venv") mkdir -p "$3/bin" && cp "$0" "$3/bin/python" && chmod 755 "$3/bin/python" ;;
    "-m pip")
      if [ "$3" = freeze ]; then echo "sortedcontainers==2.4.0"; echo "asyncua==2.0.1"; fi ;;
    *)
      echo "secure peer ready"
      exec sleep 30 ;;
  esac
  """
  @cmake """
  #!/bin/sh
  if [ "$1" = "--build" ]; then touch "$2/wotex_opcua_native"; fi
  exit 0
  """
  @succeed "#!/bin/sh\necho lane\nexit 0\n"

  setup do
    base =
      Path.join(System.tmp_dir!(), "wotex-opcua-software-#{System.unique_integer([:positive])}")

    root = Path.join(base, "root")
    bin = Path.join(base, "bin")

    for file <-
          ~w(test/interop/requirements.lock test/interop/secure_peer.py priv/native/CMakeLists.txt) do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, file)
    end

    File.mkdir_p!(bin)

    tools =
      Map.new([python: @python, cmake: @cmake, ctest: @succeed, mix: @succeed], fn {name, body} ->
        path = Path.join(bin, Atom.to_string(name))
        File.write!(path, body)
        File.chmod!(path, 0o755)
        {name, path}
      end)

    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base, root: root, tools: tools, workspace: Path.join(base, "workspace")}
  end

  test "WOP-X06 build records peer distributions and executables, and run passes every lane",
       context do
    options = [root: context.root, tools: context.tools, native_build: &native_build/1]
    assert {:ok, manifest} = Software.build(context.workspace, options)

    assert %{
             "format_version" => 1,
             "peer_distributions" => ["asyncua==2.0.1", "sortedcontainers==2.4.0"],
             "artifacts" => artifacts
           } = manifest

    assert map_size(artifacts) == 5
    assert File.regular?(Path.join(context.workspace, "software-build.json"))
    assert {:ok, report} = Software.run(context.workspace, options)

    assert Enum.sort(Map.keys(report["lanes"])) ==
             ~w(deps_audit hex_audit interop native_ctest sanitizer_ctest)

    assert Enum.all?(report["lanes"], fn {_, lane} -> lane["exit_status"] == 0 end)
    assert File.regular?(Path.join(context.workspace, "software-run.json"))

    assert {:error, :unrelated_software_workspace} =
             Software.build(context.workspace, options)
  end

  test "WOP-X06 a failed lane fails the run after recording the report", context do
    options = [root: context.root, tools: context.tools, native_build: &native_build/1]
    assert {:ok, _} = Software.build(context.workspace, options)
    parent = self()

    failing = fn _, arguments, command_options, log ->
      File.write!(log, "lane")
      send(parent, {:lane, arguments, command_options[:env]})
      if arguments == ["deps.audit"], do: 2, else: 0
    end

    assert {:error, {:software_lanes_failed, ["deps_audit"]}} =
             Software.run(context.workspace, Keyword.put(options, :command, failing))

    assert_received {:lane, ["test" | _], env}
    assert {"WOTEX_REQUIRE_SOFTWARE", "1"} in env
    report = Jason.decode!(File.read!(Path.join(context.workspace, "software-run.json")))
    assert report["lanes"]["deps_audit"]["exit_status"] == 2
  end

  test "WOP-X06 invalid inputs and stale builds fail before running lanes", context do
    options = [root: context.root, tools: context.tools, native_build: &native_build/1]

    assert {:error, :invalid_software_workspace} = Software.build("relative", options)
    assert {:error, :invalid_software_workspace} = Software.run(:workspace, options)

    assert {:error, :software_fixtures_unavailable} =
             Software.build(context.workspace, Keyword.put(options, :root, context.base))

    assert {:error, {:missing_software_tool, :cmake}} =
             Software.build(
               context.workspace,
               Keyword.put(options, :tools, %{context.tools | cmake: "/missing/cmake"})
             )

    assert {:error, :stale_software_build} = Software.run(context.workspace, options)

    assert {:error, :native_failed} =
             Software.build(
               Path.join(context.base, "native-failure"),
               Keyword.put(options, :native_build, fn _ -> {:error, :native_failed} end)
             )

    failing = fn _, _, _, log ->
      File.write!(log, "step")
      1
    end

    assert {:error, {:software_step_failed, "sanitizer_configure", 1}} =
             Software.build(
               Path.join(context.base, "step-failure"),
               Keyword.put(options, :command, failing)
             )

    peer_failing = fn _, arguments, _, log ->
      File.write!(log, "step")
      if arguments |> List.first() == "-m" and Enum.at(arguments, 1) == "pip", do: 3, else: 0
    end

    assert {:error, {:software_step_failed, "peer_install", 3}} =
             Software.build(
               Path.join(context.base, "peer-failure"),
               Keyword.put(options, :command, peer_failing)
             )

    assert {:error, {:missing_software_artifact, _}} =
             Software.build(
               Path.join(context.base, "missing-artifact"),
               Keyword.put(options, :native_build, fn _ -> {:ok, %{}} end)
             )

    assert {:ok, _} = Software.build(context.workspace, options)
    File.write!(Path.join(context.workspace, "native/output/bin/wotex_opcua_native"), "changed")
    assert {:error, :stale_software_build} = Software.run(context.workspace, options)
  end

  test "WOP-X06 a peer that exits or never becomes ready stops the run", context do
    options = [root: context.root, tools: context.tools, native_build: &native_build/1]
    assert {:ok, _} = Software.build(context.workspace, options)
    python = Path.join(context.workspace, "peer/venv/bin/python")
    File.write!(python, "#!/bin/sh\nexit 4\n")

    assert {:error, {:software_peer_exited, 4}} = Software.run(context.workspace, options)

    File.write!(python, "#!/bin/sh\necho starting\nexec sleep 30\n")
    silent = Keyword.put(options, :peer_deadline_ms, 100)
    assert {:error, :software_peer_not_ready} = Software.run(context.workspace, silent)
    refute File.exists?(Path.join(context.workspace, "software-run.json"))
  end

  test "WOP-X06 software tasks require one absolute workspace argument" do
    for task <- [Mix.Tasks.Wotex.Opcua.Software.Build, Mix.Tasks.Wotex.Opcua.Software.Run] do
      assert_raise Mix.Error, ~r/usage: mix wotex.opcua.software/, fn -> task.run([]) end

      assert_raise Mix.Error, ~r/invalid_software_workspace/, fn ->
        task.run(["--workspace", "relative"])
      end
    end
  end

  defp native_build(native) do
    for path <- ~w(output/bin/wotex_opcua_native output/bin/wotex_opcua_custody
                   native-build/wotex_opcua_session_probe native-build/wotex_opcua_paged_peer) do
      file = Path.join(native, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, path)
    end

    {:ok, %{}}
  end
end
