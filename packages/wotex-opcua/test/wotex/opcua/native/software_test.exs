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
    "-m pip_audit") echo "No known vulnerabilities found" ;;
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
  # Answers the OSV batch query with no advisory for each of the three commits.
  @curl """
  #!/bin/sh
  while [ "$#" -gt 1 ]; do
    if [ "$1" = "--output" ]; then printf '{"results":[{},{},{}]}' > "$2"; fi
    shift
  done
  exit 0
  """
  @native_sources Path.expand("../../../../priv/fixtures/native-sources-v1.json", __DIR__)

  setup do
    base =
      Path.join(System.tmp_dir!(), "wotex-opcua-software-#{System.unique_integer([:positive])}")

    root = Path.join(base, "root")
    bin = Path.join(base, "bin")

    for file <-
          ~w(test/interop/requirements.lock test/interop/audit-requirements.lock
             test/interop/secure_peer.py priv/native/CMakeLists.txt) do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, file)
    end

    sources = Path.join(root, "priv/fixtures/native-sources-v1.json")
    File.mkdir_p!(Path.dirname(sources))
    File.cp!(@native_sources, sources)

    File.mkdir_p!(bin)

    tools =
      Map.new(
        [python: @python, cmake: @cmake, ctest: @succeed, mix: @succeed, curl: @curl],
        fn {name, body} ->
          path = Path.join(bin, Atom.to_string(name))
          File.write!(path, body)
          File.chmod!(path, 0o755)
          {name, path}
        end
      )

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
             "audit_distributions" => ["asyncua==2.0.1", "sortedcontainers==2.4.0"],
             "artifacts" => artifacts
           } = manifest

    assert map_size(artifacts) == 5
    assert File.regular?(Path.join(context.workspace, "software-build.json"))
    assert {:ok, report} = Software.run(context.workspace, options)

    assert Enum.sort(Map.keys(report["lanes"])) ==
             ~w(deps_audit hex_audit interop native_audit native_ctest pip_audit sanitizer_ctest)

    assert Enum.all?(report["lanes"], fn {_, lane} -> lane["exit_status"] == 0 end)
    assert File.regular?(Path.join(context.workspace, "software-run.json"))

    audit = Jason.decode!(File.read!(Path.join(context.workspace, "native-audit.json")))
    assert audit["status"] == "clean"
    assert audit["service"] == "https://api.osv.dev/v1/querybatch"
    assert audit["source_manifest_sha256"] == Wotex.OPCUA.Native.Source.manifest_digest()

    assert [
             %{"name" => "open62541", "advisories" => []},
             %{"name" => "openssl"},
             %{"name" => "yyjson"}
           ] =
             audit["sources"]

    assert [%{"id" => _, "sha256" => _} | _] = audit["sdk_patches"]

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
      osv(arguments, ~s({"results":[{},{},{}]}))
      if arguments == ["deps.audit"], do: 2, else: 0
    end

    assert {:error, {:software_lanes_failed, ["deps_audit"]}} =
             Software.run(context.workspace, Keyword.put(options, :command, failing))

    assert_received {:lane, ["test" | _], env}
    assert {"WOTEX_REQUIRE_SOFTWARE", "1"} in env
    report = Jason.decode!(File.read!(Path.join(context.workspace, "software-run.json")))
    assert report["lanes"]["deps_audit"]["exit_status"] == 2
  end

  test "WOP-X06 the audits fail the run on a finding, a malformed answer or other pins", context do
    options = [root: context.root, tools: context.tools, native_build: &native_build/1]
    assert {:ok, _} = Software.build(context.workspace, options)
    report = Path.join(context.workspace, "software-run.json")

    answering = fn answer, pip_status ->
      fn _, arguments, _, log ->
        File.write!(log, "lane")
        osv(arguments, answer)
        if "pip_audit" in arguments, do: pip_status, else: 0
      end
    end

    vulnerable = ~s({"results":[{"vulns":[{"id":"OSV-2026-2"},{"id":"CVE-2026-1"}]},{},{}]})

    assert {:error, {:software_lanes_failed, ["native_audit", "pip_audit"]}} =
             Software.run(
               context.workspace,
               Keyword.put(options, :command, answering.(vulnerable, 1))
             )

    audit = Jason.decode!(File.read!(Path.join(context.workspace, "native-audit.json")))
    assert audit["status"] == "vulnerable"
    assert [%{"advisories" => ["CVE-2026-1", "OSV-2026-2"]}, _, _] = audit["sources"]
    assert File.read!(Path.join(context.workspace, "logs/native_audit.log")) =~ "CVE-2026-1"
    assert Jason.decode!(File.read!(report))["lanes"]["pip_audit"]["exit_status"] == 1

    for malformed <- [~s({"results":[{},{}]}), ~s({"results":[{"vulns":[{}]},{},{}]}), "[]"] do
      assert {:error, {:software_lanes_failed, ["native_audit"]}} =
               Software.run(
                 context.workspace,
                 Keyword.put(options, :command, answering.(malformed, 0))
               )
    end

    File.write!(Path.join(context.root, "priv/fixtures/native-sources-v1.json"), "{}")

    assert {:error, {:software_lanes_failed, ["native_audit"]}} =
             Software.run(context.workspace, options)

    assert File.read!(Path.join(context.workspace, "logs/native_audit.log")) =~
             "does not match the built pins"

    File.write!(Path.join(context.root, "test/interop/audit-requirements.lock"), "changed")
    assert {:error, :stale_software_build} = Software.run(context.workspace, options)
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

  # Writes the OSV answer where a curl call asks for its output.
  defp osv(arguments, answer) do
    case Enum.drop_while(arguments, &(&1 != "--output")) do
      ["--output", path | _] -> File.write!(path, answer)
      _ -> :ok
    end
  end
end
