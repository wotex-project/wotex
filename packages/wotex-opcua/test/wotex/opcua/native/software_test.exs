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
  # Builds the .NET peer into the volume mounted at /work, reports the SDK
  # version and runs the peer until it is stopped.
  @docker """
  #!/bin/sh
  [ "$1" = run ] || exit 0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --volume) case "$2" in *:/work) work="${2%:/work}" ;; esac; shift ;;
      build) mkdir -p "$work/output" && echo peer > "$work/output/DotnetPeer.dll" ;;
      --version) echo 10.0.401 ;;
      /peer/DotnetPeer.dll) echo "dotnet peer ready"; exec sleep 30 ;;
    esac
    shift
  done
  exit 0
  """
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
  @contract Path.expand("../../../../priv/fixtures/native-contract-v1.json", __DIR__)
  @observation ~s(WOP-X-F48 {"operations_succeeded":6,"runtime_python_processes":0,) <>
                 ~s("runtime_shell_processes":0,"active_local_resources":0})

  setup do
    base =
      Path.join(System.tmp_dir!(), "wotex-opcua-software-#{System.unique_integer([:positive])}")

    root = Path.join(base, "root")
    bin = Path.join(base, "bin")

    for file <-
          ~w(test/interop/requirements.lock test/interop/audit-requirements.lock
             test/interop/secure_peer.py priv/native/CMakeLists.txt
             test/interop/dotnet_peer/DotnetPeer.csproj test/interop/dotnet_peer/Program.cs
             test/interop/dotnet_peer/nuget.config test/interop/dotnet_peer/packages.lock.json) do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, file)
    end

    sources = Path.join(root, "priv/fixtures/native-sources-v1.json")
    File.mkdir_p!(Path.dirname(sources))
    File.cp!(@native_sources, sources)
    File.cp!(@contract, Path.join(root, "priv/fixtures/native-contract-v1.json"))

    File.mkdir_p!(bin)

    template = Path.join(base, "template.tar")
    archive!(template)
    core = Path.join(base, "wotex-0.1.0.tar")
    runtime = Path.join(base, "wotex_runtime-0.1.0.tar")
    File.cp!(template, core)
    File.cp!(template, runtime)

    # Answers `mix hex.build --output PATH` with the template archive.
    mix = """
    #!/bin/sh
    if [ "$1" = "hex.build" ]; then cp #{template} "$3"; fi
    if [ "$1" = "test" ]; then echo '#{@observation}'; fi
    echo lane
    exit 0
    """

    tools =
      Map.new(
        [python: @python, cmake: @cmake, ctest: @succeed, mix: mix, curl: @curl, docker: @docker],
        fn {name, body} ->
          path = Path.join(bin, Atom.to_string(name))
          File.write!(path, body)
          File.chmod!(path, 0o755)
          {name, path}
        end
      )

    on_exit(fn -> File.rm_rf!(base) end)

    %{
      base: base,
      root: root,
      tools: tools,
      template: template,
      archives: %{core: core, runtime: runtime},
      workspace: Path.join(base, "workspace")
    }
  end

  test "WOP-X06 build records peer distributions and executables, and run passes every lane",
       context do
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

    assert {:ok, manifest} = Software.build(context.workspace, options)

    assert %{
             "format_version" => 1,
             "peer_distributions" => ["asyncua==2.0.1", "sortedcontainers==2.4.0"],
             "audit_distributions" => ["asyncua==2.0.1", "sortedcontainers==2.4.0"],
             "artifacts" => artifacts
           } = manifest

    assert map_size(artifacts) == 6

    assert %{"sdk_version" => "10.0.401", "image" => image, "sources" => sources} =
             manifest["dotnet_peer"]

    assert image =~ ~r/\Amcr\.microsoft\.com\/dotnet\/sdk@sha256:[0-9a-f]{64}\z/

    assert Enum.sort(Map.keys(sources)) ==
             ~w(DotnetPeer.csproj Program.cs nuget.config packages.lock.json)

    refute File.exists?(Path.join(context.root, "test/interop/dotnet_peer/bin"))
    assert File.regular?(Path.join(context.workspace, "software-build.json"))
    assert {:ok, report} = Software.run(context.workspace, options)

    assert Enum.sort(Map.keys(report["lanes"])) ==
             ~w(archive_consumer deps_audit hex_audit interop native_audit native_ctest pip_audit
                sanitizer_ctest)

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

    consumer = Jason.decode!(File.read!(Path.join(context.workspace, "archive-consumer.json")))
    assert consumer["registry_publication_asserted"] == false
    assert consumer["case"] == "WOP-X-F48"

    assert consumer["observation"] == %{
             "operations_succeeded" => 6,
             "runtime_python_processes" => 0,
             "runtime_shell_processes" => 0,
             "active_local_resources" => 0
           }

    assert map_size(consumer["archives"]) == 3
    project = Path.join(context.workspace, "consumer/project")
    assert File.read!(Path.join(project, "mix.exs")) =~ "consumer/deps/wotex_opcua"
    assert File.read!(Path.join(project, "test/archive_consumer_test.exs")) =~ "WOP-X-F48"

    assert File.read!(Path.join(context.workspace, "logs/archive_consumer.log")) =~
             "== native_build"

    assert {:error, :unrelated_software_workspace} =
             Software.build(context.workspace, options)
  end

  test "WOP-X06 a failed lane fails the run after recording the report", context do
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

    assert {:ok, _} = Software.build(context.workspace, options)
    parent = self()

    failing = fn _, arguments, command_options, log ->
      File.write!(log, "lane")
      send(parent, {:lane, arguments, command_options[:env]})
      outputs(arguments, ~s({"results":[{},{},{}]}), context.template, log)
      if arguments == ["deps.audit"], do: 2, else: 0
    end

    assert {:error, {:software_lanes_failed, ["deps_audit"]}} =
             Software.run(context.workspace, Keyword.put(options, :command, failing))

    assert_received {:lane, ["test" | _], env}
    assert {"WOTEX_REQUIRE_SOFTWARE", "1"} in env

    assert {"WOTEX_OPCUA_DOTNET_CONFIG", dotnet_config} =
             List.keyfind(env, "WOTEX_OPCUA_DOTNET_CONFIG", 0)

    assert Path.basename(dotnet_config) == "dotnet-config.json"
    report = Jason.decode!(File.read!(Path.join(context.workspace, "software-run.json")))
    assert report["lanes"]["deps_audit"]["exit_status"] == 2
  end

  test "WOP-X06 the audits fail the run on a finding, a malformed answer or other pins", context do
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

    assert {:ok, _} = Software.build(context.workspace, options)
    report = Path.join(context.workspace, "software-run.json")

    answering = fn answer, pip_status ->
      fn _, arguments, _, log ->
        File.write!(log, "lane")
        outputs(arguments, answer, context.template, log)
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

    unequal = fn _, arguments, _, log ->
      File.write!(log, "lane")
      outputs(arguments, ~s({"results":[{},{},{}]}), context.template, log)

      if arguments == ["test", "--warnings-as-errors"],
        do: File.write!(log, String.replace(@observation, ":6,", ":5,"))

      0
    end

    assert {:error, {:software_lanes_failed, ["archive_consumer"]}} =
             Software.run(context.workspace, Keyword.put(options, :command, unequal))

    assert File.read!(Path.join(context.workspace, "logs/archive_consumer.log")) =~
             "does not equal WOP-X-F48"

    File.write!(Path.join(context.root, "priv/fixtures/native-sources-v1.json"), "{}")

    assert {:error, {:software_lanes_failed, ["native_audit"]}} =
             Software.run(context.workspace, options)

    assert File.read!(Path.join(context.workspace, "logs/native_audit.log")) =~
             "does not match the built pins"

    File.write!(Path.join(context.root, "test/interop/audit-requirements.lock"), "changed")
    assert {:error, :stale_software_build} = Software.run(context.workspace, options)
  end

  test "WOP-X06 a changed .NET peer project makes the build stale", context do
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

    assert {:ok, _} = Software.build(context.workspace, options)
    File.write!(Path.join(context.root, "test/interop/dotnet_peer/packages.lock.json"), "{}")
    assert {:error, :stale_software_build} = Software.run(context.workspace, options)
  end

  test "WOP-X06 invalid inputs and stale builds fail before running lanes", context do
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

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
    options = [
      root: context.root,
      tools: context.tools,
      native_build: &native_build/1,
      archives: context.archives
    ]

    assert {:ok, _} = Software.build(context.workspace, options)
    python = Path.join(context.workspace, "peer/venv/bin/python")
    File.write!(python, "#!/bin/sh\nexit 4\n")

    assert {:error, {:software_peer_exited, 4}} = Software.run(context.workspace, options)

    File.write!(python, "#!/bin/sh\necho starting\nexec sleep 30\n")
    silent = Keyword.put(options, :peer_deadline_ms, 100)
    assert {:error, :software_peer_not_ready} = Software.run(context.workspace, silent)
    refute File.exists?(Path.join(context.workspace, "software-run.json"))

    File.write!(python, "#!/bin/sh\necho 'secure peer ready'\nexec sleep 30\n")
    docker = Path.join(context.base, "bin/docker-exiting")
    File.write!(docker, "#!/bin/sh\n[ \"$1\" = rm ] || echo \"$@\" > #{docker}.args\nexit 5\n")
    File.chmod!(docker, 0o755)
    exiting = Keyword.put(options, :tools, %{context.tools | docker: docker})

    assert {:error, {:dotnet_peer, {:software_peer_exited, 5}}} =
             Software.run(context.workspace, exiting)

    arguments = File.read!(docker <> ".args")
    assert arguments =~ "--network host"
    assert arguments =~ "--interactive"
    assert arguments =~ "/peer/DotnetPeer.dll /fixture 40"
    refute File.exists?(Path.join(context.workspace, "software-run.json"))
  end

  test "WOP-X06 software tasks require an absolute workspace and the run its archives",
       context do
    archives = [
      "--core-archive",
      context.archives.core,
      "--runtime-archive",
      context.archives.runtime
    ]

    for {task, extra} <- [
          {Mix.Tasks.Wotex.Opcua.Software.Build, []},
          {Mix.Tasks.Wotex.Opcua.Software.Run, archives}
        ] do
      assert_raise Mix.Error, ~r/usage: mix wotex.opcua.software/, fn -> task.run([]) end

      assert_raise Mix.Error, ~r/invalid_software_workspace/, fn ->
        task.run(["--workspace", "relative" | extra])
      end
    end

    assert_raise Mix.Error, ~r/usage: mix wotex.opcua.software.run/, fn ->
      Mix.Tasks.Wotex.Opcua.Software.Run.run(["--workspace", context.workspace])
    end

    options = [root: context.root, tools: context.tools]

    for archives <- [
          nil,
          %{core: "relative.tar", runtime: context.archives.runtime},
          %{core: context.archives.core, runtime: "/missing/runtime.tar"},
          %{core: context.archives.core}
        ] do
      assert {:error, :software_archives_required} =
               Software.run(context.workspace, Keyword.put(options, :archives, archives))
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

  # Writes the OSV answer where a curl call asks for its output and the template
  # archive where `mix hex.build` does.
  defp outputs(["hex.build", "--output", path], _, template, _), do: File.cp!(template, path)
  defp outputs(["test", "--warnings-as-errors"], _, _, log), do: File.write!(log, @observation)

  defp outputs(arguments, answer, _, _) do
    case Enum.drop_while(arguments, &(&1 != "--output")) do
      ["--output", path | _] -> File.write!(path, answer)
      _ -> :ok
    end
  end

  # A Hex-shaped archive: an outer tar holding contents.tar.gz.
  defp archive!(path) do
    directory = path <> "-parts"
    File.mkdir_p!(directory)
    inner = Path.join(directory, "contents.tar.gz")

    :ok =
      :erl_tar.create(String.to_charlist(inner), [{~c"mix.exs", "defmodule Fake do end\n"}], [
        :compressed
      ])

    :ok =
      :erl_tar.create(String.to_charlist(path), [{~c"contents.tar.gz", String.to_charlist(inner)}])
  end
end
