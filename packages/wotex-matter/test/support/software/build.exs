Code.require_file("command.exs", __DIR__)
Code.require_file("peer_extension.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBuild do
  @moduledoc false

  alias Wotex.Matter.{SoftwareCommand, SoftwareManifest, SoftwarePeerExtension}

  @timeout 5_400_000
  @container_environment [
    {"PATH", "/work/tools/zap:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
    {"DEBIAN_FRONTEND", "noninteractive"},
    {"LC_ALL", "C.UTF-8"},
    {"CIPD_CACHE_DIR", "/work/cipd-cache"}
  ]
  @host_arguments """
  chip_crypto = "boringssl"
  chip_config_network_layer_ble = false
  chip_enable_ble = false
  chip_inet_config_enable_ipv4 = true
  chip_build_tools = false
  chip_support_thread_meshcop = false
  chip_logging_backend = "external"
  enable_exceptions = true
  treat_warnings_as_errors = true
  target_defines = [ "CHIP_CONFIG_KVS_PATH=\\\"sdk-kvs\\\"" ]
  """
  @peer_arguments """
  chip_crypto = "boringssl"
  chip_config_network_layer_ble = false
  chip_enable_ble = false
  chip_inet_config_enable_ipv4 = true
  chip_build_tools = true
  chip_support_thread_meshcop = false
  chip_enable_pw_rpc = false
  chip_build_libshell = false
  chip_examples_enable_imgui_ui = false
  treat_warnings_as_errors = false
  """
  @groups """

  group("wotex-matter-host") {
    deps = [ "//examples/wotex-matter-host:wotex-matter-host" ]
  }
  if (chip_build_tools) {
    group("wotex-software-peers") {
      deps = [
        "//examples/lighting-app/linux:chip-lighting-app",
        "//examples/all-clusters-app/linux:chip-all-clusters-app",
        "//examples/bridge-app/linux:chip-bridge-app",
      ]
    }
  }
  """

  @spec run(String.t(), String.t(), :native | :software) :: map()
  def run(root, workspace, mode) do
    sources = SoftwareManifest.read(Path.join(root, "test/support/software/sources.json"))
    unless sources["schema"] == "wotex.matter.native-sources@1", do: fail(:source_manifest)

    for directory <- ~w(downloads logs metadata tools bin),
        do: File.mkdir_p!(Path.join(workspace, directory))

    context = %{
      root: root,
      workspace: workspace,
      source_identity: SoftwareManifest.identity(root),
      name: "wotex-matter-build-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      deadline: System.monotonic_time(:millisecond) + @timeout
    }

    Mix.shell().info("Verifying Matter source archives and native advisories")
    audit(context, sources, mode)
    prepare_sources(context, sources, mode)
    watcher = cleanup_watcher(context)

    result =
      try do
        start_container(context)
        install_tools(context, sources)
        build_native(context, mode)
        extensions = if mode == :software, do: build_peers(context), else: []
        manifest(context, sources, mode, extensions)
      after
        release_watcher(watcher)
      end

    unless SoftwareManifest.identity(root) == context.source_identity,
      do: fail(:source_changed_during_build)

    SoftwareManifest.write(Path.join(workspace, "native-manifest.json"), result)
    result
  end

  defp prepare_sources(context, sources, mode) do
    for source <- archives(sources, mode) do
      download(context, source)
      target = Path.join(context.workspace, source["destination"])
      File.mkdir_p!(target)

      host(context, "extract-" <> source["name"], "tar", [
        "-xzf",
        Path.join(context.workspace, "downloads/" <> source["filename"]),
        "-C",
        target,
        "--strip-components=1"
      ])
    end

    for source <- sources["python"] ++ [sources["header"], sources["cipd"]],
        do: download(context, source)

    sdk = Path.join(context.workspace, "sdk")
    host_source = Path.join(sdk, "examples/wotex-matter-host")
    File.cp_r!(Path.join(context.root, "native"), host_source)
    File.mkdir_p!(Path.join(host_source, "third_party/nlohmann"))

    File.cp!(
      Path.join(context.workspace, "downloads/json.hpp"),
      Path.join(host_source, "third_party/nlohmann/json.hpp")
    )

    File.cp!(
      Path.join(context.workspace, "downloads/cipd"),
      Path.join(context.workspace, "tools/cipd")
    )

    File.chmod!(Path.join(context.workspace, "tools/cipd"), 0o500)

    File.write!(
      Path.join(sdk, "build_overrides/pigweed_environment.gni"),
      "# Archive-only system-toolchain build.\n"
    )

    File.write!(Path.join(sdk, "BUILD.gn"), @groups, [:append])
    host(context, "sdk-git-init", "git", ["init", "--quiet", "--initial-branch=main", sdk])

    for tool <- sources["tools"] do
      File.mkdir_p!(Path.join(context.workspace, "tools/" <> tool["name"]))

      File.write!(
        Path.join(context.workspace, tool["name"] <> ".ensure"),
        tool["package"] <> " " <> tool["instance"] <> "\n",
        [:exclusive]
      )
    end
  end

  defp download(context, source) do
    destination = Path.join(context.workspace, "downloads/" <> source["filename"])

    host(context, "download-" <> source["filename"], "curl", [
      "--disable",
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      "--proto",
      "=https",
      "--proto-redir",
      "=https",
      "--max-redirs",
      "3",
      "--connect-timeout",
      "20",
      "--max-time",
      "300",
      "--max-filesize",
      "536870912",
      "--output",
      destination,
      source["url"]
    ])

    unless SoftwareManifest.digest(destination) == source["sha256"],
      do: fail(:source_digest_mismatch)
  end

  defp start_container(context) do
    host(context, "container-start", "docker", [
      "run",
      "--detach",
      "--rm",
      "--name",
      context.name,
      "--platform",
      "linux/amd64",
      "--volume",
      context.root <> ":/src:ro",
      "--volume",
      context.workspace <> ":/work",
      SoftwareManifest.image(),
      "/bin/sleep",
      "5400"
    ])
  end

  defp install_tools(context, sources) do
    inside(context, "apt-update", ["apt-get", "update", "-qq"])

    inside(
      context,
      "apt-install",
      ["apt-get", "install", "-y", "-qq"] ++
        ~w(binutils build-essential ca-certificates cmake curl git libavahi-client-dev
         libdbus-1-dev libglib2.0-dev libssl-dev ninja-build pkg-config python3 python3-dev python3-pip unzip)
    )

    require_output(inside(context, "architecture", ["uname", "-m"]), "x86_64\n")

    require_output(
      inside(context, "compiler", ["g++", "-dumpfullversion", "-dumpversion"]),
      "12.2.0\n"
    )

    require_output(inside(context, "ninja", ["ninja", "--version"]), "1.11.1\n")
    cmake = inside(context, "cmake", ["cmake", "--version"])
    unless String.starts_with?(cmake, "cmake version 3.25.1\n"), do: fail(:toolchain_mismatch)

    inside(
      context,
      "python-install",
      [
        "python3",
        "-m",
        "pip",
        "install",
        "--break-system-packages",
        "--no-build-isolation",
        "--no-deps",
        "--no-index"
      ] ++
        Enum.map(sources["python"], &("/work/downloads/" <> &1["filename"]))
    )

    for tool <- sources["tools"] do
      name = tool["name"]

      inside(context, "install-" <> name, [
        "/work/tools/cipd",
        "ensure",
        "-root",
        "/work/tools/" <> name,
        "-ensure-file",
        "/work/" <> name <> ".ensure"
      ])

      path = Path.join([context.workspace, "tools", name, tool["executable"]])
      unless SoftwareManifest.digest(path) == tool["sha256"], do: fail(:tool_digest_mismatch)
    end

    require_output(
      inside(context, "gn", ["/work/tools/gn/gn", "--version"]),
      "2255 (97b68a0bb62b)\n"
    )

    zap = inside(context, "zap", ["/work/tools/zap/zap-cli", "--version"])
    unless String.contains?(zap, "Version: 2026.5.12"), do: fail(:toolchain_mismatch)
  end

  defp build_native(context, mode) do
    Mix.shell().info("Building normal and sanitizer Matter controllers")

    for {directory, flags, output} <- [
          {"build", "", "wotex-matter-host"},
          {"build-sanitized", "is_asan = true\nis_ubsan = true\n", "wotex-matter-host-sanitized"}
        ] do
      File.mkdir!(Path.join(context.workspace, directory))
      File.write!(Path.join([context.workspace, directory, "args.gn"]), @host_arguments <> flags)

      inside(context, directory <> "-generate", [
        "/work/tools/gn/gn",
        "--root=/work/sdk",
        "gen",
        "/work/" <> directory
      ])

      targets =
        ["obj/examples/wotex-matter-host/bin/wotex-matter-host"] ++
          if(mode == :software,
            do: ["obj/examples/wotex-matter-host/bin/wotex-matter-flow-host"],
            else: []
          )

      inside(
        context,
        directory <> "-compile",
        [
          "ninja",
          "--quiet",
          "-C",
          "/work/" <> directory,
          "-j",
          "4"
        ] ++ targets
      )

      File.cp!(
        Path.join([
          context.workspace,
          directory,
          "obj/examples/wotex-matter-host/bin/wotex-matter-host"
        ]),
        Path.join(context.workspace, "bin/" <> output)
      )

      File.chmod!(Path.join(context.workspace, "bin/" <> output), 0o500)

      if mode == :software do
        suffix = if flags == "", do: "", else: "-sanitized"
        destination = Path.join(context.workspace, "bin/wotex-matter-flow-host" <> suffix)

        File.cp!(
          Path.join([
            context.workspace,
            directory,
            "obj/examples/wotex-matter-host/bin/wotex-matter-flow-host"
          ]),
          destination
        )

        File.chmod!(destination, 0o500)
      end
    end

    for {directory, sanitizer} <- [{"cmake-normal", "OFF"}, {"cmake-sanitized", "ON"}] do
      inside(context, directory <> "-configure", [
        "cmake",
        "-S",
        "/src/native",
        "-B",
        "/work/" <> directory,
        "-G",
        "Ninja",
        "-DWOTEX_MATTER_SANITIZERS=" <> sanitizer,
        "-DWOTEX_MATTER_SDK_ROOT=/work/sdk",
        "-DWOTEX_MATTER_JSON_INCLUDE=/work/sdk/examples/wotex-matter-host/third_party"
      ])

      inside(context, directory <> "-compile", [
        "cmake",
        "--build",
        "/work/" <> directory,
        "--parallel",
        "4"
      ])

      inside(
        context,
        directory <> "-test",
        ["ctest", "--test-dir", "/work/" <> directory, "--output-on-failure"],
        [{"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1"}, {"UBSAN_OPTIONS", "halt_on_error=1"}]
      )

      suffix = if sanitizer == "ON", do: "-sanitized", else: ""

      targets =
        ["contract_driver"] ++ if(mode == :software, do: ["controller_test"], else: [])

      for target <- targets do
        destination =
          Path.join(
            context.workspace,
            "bin/wotex-matter-" <> String.replace(target, "_", "-") <> suffix
          )

        File.cp!(
          Path.join(context.workspace, directory <> "/wotex_matter_" <> target),
          destination
        )

        File.chmod!(destination, 0o500)
      end
    end
  end

  defp build_peers(context) do
    Mix.shell().info("Building the pinned lighting, all-clusters and bridge peers")
    extensions = SoftwarePeerExtension.apply!(context.root, Path.join(context.workspace, "sdk"))
    File.mkdir!(Path.join(context.workspace, "build-peers"))
    File.write!(Path.join(context.workspace, "build-peers/args.gn"), @peer_arguments)

    inside(context, "peers-generate", [
      "/work/tools/gn/gn",
      "--root=/work/sdk",
      "gen",
      "/work/build-peers"
    ])

    inside(context, "peers-compile", [
      "ninja",
      "--quiet",
      "-C",
      "/work/build-peers",
      "-j",
      "4",
      "wotex-software-peers"
    ])

    for name <- ~w(chip-lighting-app chip-all-clusters-app chip-bridge-app) do
      File.cp!(
        Path.join(context.workspace, "build-peers/" <> name),
        Path.join(context.workspace, "bin/" <> name)
      )

      File.chmod!(Path.join(context.workspace, "bin/" <> name), 0o500)
    end

    File.mkdir!(Path.join(context.workspace, "paa"))

    for name <-
          ~w(Chip-Test-PAA-FFF1-Cert.der Chip-Test-PAA-NoVID-Cert.der Chip-Test-PAA-NoVID-ToResignPAIs-Cert.der) do
      destination = Path.join(context.workspace, "paa/" <> name)

      File.cp!(
        Path.join(context.workspace, "sdk/credentials/test/attestation/" <> name),
        destination
      )

      File.chmod!(destination, 0o400)
    end

    extensions
  end

  defp manifest(context, sources, mode, extensions) do
    tools =
      for {name, executable, arguments} <- [
            {"compiler", "/usr/bin/g++", ["--version"]},
            {"linker", "/usr/bin/ld", ["--version"]},
            {"cmake", "/usr/bin/cmake", ["--version"]},
            {"ninja", "/usr/bin/ninja", ["--version"]},
            {"gn", "/work/tools/gn/gn", ["--version"]},
            {"zap", "/work/tools/zap/zap-cli", ["--version"]},
            {"python", "/usr/bin/python3", ["--version"]}
          ],
          into: %{} do
        version = inside(context, "version-" <> name, [executable | arguments])

        digest =
          inside(context, "digest-" <> name, ["sha256sum", executable]) |> String.split() |> hd()

        {name, %{"version" => String.trim(version), "sha256" => digest}}
      end

    binaries =
      for name <- binaries(mode) do
        header = inside(context, "elf-" <> name, ["readelf", "-h", "/work/bin/" <> name])

        unless String.contains?(header, "Advanced Micro Devices X86-64"),
          do: fail(:architecture_mismatch)

        needed = inside(context, "needed-" <> name, ["readelf", "-d", "/work/bin/" <> name])
        libraries = Regex.scan(~r/\(NEEDED\).*\[([^\]]+)\]/, needed) |> Enum.map(&List.last/1)

        if Enum.any?(libraries, &String.match?(&1, ~r/python|libssl|libcrypto/i)),
          do: fail(:runtime_dependency)

        linkage = inside(context, "linkage-" <> name, ["ldd", "/work/bin/" <> name])
        if String.contains?(linkage, "not found"), do: fail(:runtime_dependency)

        %{
          "path" => "bin/" <> name,
          "sha256" => SoftwareManifest.digest(Path.join(context.workspace, "bin/" <> name)),
          "elf_machine" => "Advanced Micro Devices X86-64",
          "needed_libraries" => libraries
        }
      end

    identity = context.source_identity

    %{
      "schema" => "wotex.native-build",
      "version" => 1,
      "package" => "wotex_matter",
      "source_revision" => revision(context, identity),
      "source_files" => identity["source_files_sha256"],
      "peer_extensions" => extensions,
      "upstream_sources" =>
        archives(sources, mode) ++ sources["python"] ++ [sources["header"], sources["cipd"]],
      "sdk_gitlinks" =>
        sources["archives"]
        |> Enum.reject(&(&1["name"] == "connectedhomeip"))
        |> Map.new(&{&1["name"], &1["revision"]})
        |> Map.put("uriparser", "04d8b8df5e0c6bf6c06e472540c015943a613bd2"),
      "toolchain" => %{
        "target" => "x86_64-linux-gnu",
        "container_image" => SoftwareManifest.image(),
        "executables" => tools,
        "installed_tools" => sources["tools"]
      },
      "arguments" => %{
        "host_gn" => @host_arguments,
        "peer_gn" => if(mode == :software, do: @peer_arguments, else: nil),
        "container_environment" => Map.new(@container_environment),
        "parallel_compilers" => 4,
        "steps" =>
          context.workspace
          |> Path.join("metadata/commands.jsonl")
          |> File.stream!()
          |> Enum.map(&Jason.decode!/1)
      },
      "build_features" =>
        ~w(boringssl controller-data-model dns-sd ipv4 ipv6 no-ble stderr-logging asan ubsan),
      "binaries" => binaries,
      "audit_results" => %{
        "cmake_normal" => "passed",
        "cmake_asan_ubsan" => "passed",
        "osv" => "passed",
        "protocol_interoperability" => "not_executed"
      },
      "logs" =>
        context.workspace
        |> Path.join("logs/*.log")
        |> Path.wildcard()
        |> Map.new(fn path ->
          {Path.relative_to(path, context.workspace), SoftwareManifest.digest(path)}
        end)
    }
  end

  defp revision(context, identity) do
    if File.exists?(Path.join(context.root, ".git")) do
      context |> host("source-revision", "git", ["rev-parse", "HEAD"]) |> String.trim()
    else
      "sha256:" <> identity["source_sha256"]
    end
  end

  defp audit(context, sources, mode) do
    queries =
      Enum.map(archives(sources, mode) ++ [sources["header"]], &%{"commit" => &1["revision"]}) ++
        Enum.map(
          sources["python"],
          &%{
            "package" => %{"ecosystem" => "PyPI", "name" => &1["name"]},
            "version" => &1["version"]
          }
        )

    request = Path.join(context.workspace, "metadata/advisory-request.json")
    SoftwareManifest.write(request, %{"queries" => queries})

    result =
      host(context, "advisories", "curl", [
        "--disable",
        "--fail",
        "--silent",
        "--show-error",
        "--connect-timeout",
        "10",
        "--max-time",
        "60",
        "--max-filesize",
        "8388608",
        "--proto",
        "=https",
        "-H",
        "Content-Type: application/json",
        "--data-binary",
        "@" <> request,
        "https://api.osv.dev/v1/querybatch"
      ])

    with {:ok, %{"results" => results}} <- Jason.decode(result),
         true <- length(results) == length(queries),
         true <- Enum.all?(results, &(&1 == %{} or &1 == %{"vulns" => []})) do
      :ok
    else
      _ -> fail(:native_advisory_failure)
    end
  end

  defp archives(sources, :software), do: sources["archives"]

  defp archives(sources, :native),
    do: Enum.reject(sources["archives"], &(&1["purpose"] == "software_peer_source"))

  defp binaries(:native),
    do: ~w(wotex-matter-host wotex-matter-host-sanitized
           wotex-matter-contract-driver wotex-matter-contract-driver-sanitized)

  defp binaries(:software),
    do: binaries(:native) ++ ~w(wotex-matter-flow-host wotex-matter-flow-host-sanitized
                               wotex-matter-controller-test wotex-matter-controller-test-sanitized
                               chip-lighting-app chip-all-clusters-app chip-bridge-app)

  defp require_output(actual, expected), do: if(actual != expected, do: fail(:toolchain_mismatch))

  defp inside(context, id, arguments, extra_environment \\ []) do
    env =
      Enum.flat_map(@container_environment ++ extra_environment, fn {key, value} ->
        ["--env", key <> "=" <> value]
      end)

    host(context, id, "docker", ["exec"] ++ env ++ [context.name | arguments])
  end

  defp host(context, id, executable, arguments) do
    remaining = context.deadline - System.monotonic_time(:millisecond)
    if remaining <= 0, do: fail(:software_build_timeout)

    normalized =
      Enum.map(arguments, fn argument ->
        argument
        |> String.replace(context.workspace, "${workspace}")
        |> String.replace(context.root, "${source}")
        |> String.replace(context.name, "${container}")
      end)

    step = %{
      "id" => id,
      "executable" => executable,
      "arguments" => normalized,
      "timeout_ms" => remaining
    }

    File.write!(
      Path.join(context.workspace, "metadata/commands.jsonl"),
      Jason.encode!(step) <> "\n",
      [:append]
    )

    SoftwareCommand.run!(executable, arguments,
      cd: context.root,
      timeout: remaining,
      log: Path.join(context.workspace, "logs/" <> id <> ".log")
    )
  end

  defp cleanup_watcher(context) do
    owner = self()

    spawn(fn ->
      monitor = Process.monitor(owner)

      receive do
        {:release, caller} ->
          Process.demonitor(monitor, [:flush])
          send(caller, {:container_cleanup, self(), cleanup(context)})

        {:DOWN, ^monitor, :process, ^owner, _} ->
          cleanup(context)
      end
    end)
  end

  defp release_watcher(watcher) do
    send(watcher, {:release, self()})

    receive do
      {:container_cleanup, ^watcher, :ok} -> :ok
      {:container_cleanup, ^watcher, _} -> fail(:container_cleanup_unverified)
    after
      12_000 -> fail(:container_cleanup_unverified)
    end
  end

  defp cleanup(context) do
    SoftwareCommand.run("docker", ["rm", "--force", context.name], timeout: 5_000)

    case SoftwareCommand.run(
           "docker",
           ["ps", "--all", "--filter", "name=^" <> context.name <> "$", "--format", "{{.ID}}"],
           timeout: 5_000
         ) do
      {:ok, ""} -> :ok
      _ -> :error
    end
  end

  defp fail(reason), do: Mix.raise(Atom.to_string(reason))
end
