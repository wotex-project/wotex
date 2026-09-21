Code.require_file("command.exs", __DIR__)
Code.require_file("manifest.exs", __DIR__)
Code.require_file("package.exs", __DIR__)
Code.require_file("run.exs", __DIR__)

defmodule Wotex.BACnet.SoftwareFixture do
  @moduledoc false

  alias Wotex.BACnet.{SoftwareCommand, SoftwareManifest, SoftwarePackage}

  @fixture_files ~w(CMakeLists.txt Dockerfile.software peer.c peer.h control.c property_peer.c property_peer.h)
  @metadata_files ~w(compiler.txt linker.txt cmake.txt libc.txt os.txt cpu.txt packages.txt sha256.txt normal-cmake.txt sanitizer-cmake.txt)
  @binaries ~w(/normal/wotex-bacnet-peer /normal/sdk/libbacnet-stack.a /sanitizer/wotex-bacnet-peer /sanitizer/sdk/libbacnet-stack.a /usr/bin/cc /usr/bin/ld /usr/bin/cmake)
  @base "debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171"
  @build_options %{
    "common" => ["-DCMAKE_BUILD_TYPE=RelWithDebInfo", "-DWOTEX_BACNET_STACK_SOURCE=/sdk"],
    "normal" => ["-DWOTEX_BACNET_SANITIZE=OFF"],
    "sanitizer" => ["-DWOTEX_BACNET_SANITIZE=ON"],
    "sanitizer_compile" => ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"],
    "sanitizer_link" => ["-fsanitize=address,undefined"],
    "link" => ["-Wl,--wrap=bip_send_pdu"]
  }

  @spec main(:build | :run, [String.t()]) :: :ok
  def main(operation, arguments) when operation in [:build, :run] do
    root = File.cwd!()
    workspace = SoftwareManifest.arguments(arguments, root)
    prepare(operation, workspace)

    context = %{
      root: root,
      workspace: workspace,
      guardian: Path.join(workspace, "command"),
      sources: SoftwareManifest.sources(root),
      source: SoftwareManifest.identity(root),
      inputs: SoftwareManifest.inputs(root)
    }

    lease = lease(context)

    result =
      try do
        dispatch(operation, context)
      after
        release(lease)
      end

    Mix.shell().info("software fixture #{operation} completed: #{workspace}")
    result
  end

  defp lease(context) do
    manifest_path = Path.join(context.workspace, "peer-manifest.json")

    if File.exists?(manifest_path) do
      SoftwareManifest.verify_local(
        context.root,
        context.workspace,
        SoftwareManifest.read(manifest_path)
      )

      case SoftwareCommand.lease(context.guardian, context.workspace <> ".lock") do
        {:ok, port} -> {:native, port}
        {:error, code} -> fail(code)
      end
    else
      path = context.workspace <> ".bootstrap.lock"
      unless File.mkdir(path) == :ok, do: fail(:workspace_locked)
      owner = self()

      watcher =
        spawn(fn ->
          monitor = Process.monitor(owner)

          receive do
            :release ->
              Process.demonitor(monitor, [:flush])
              send(owner, {:bootstrap_released, self(), File.rmdir(path)})

            {:DOWN, ^monitor, :process, ^owner, _} ->
              File.rmdir(path)
          end
        end)

      {:bootstrap, watcher}
    end
  end

  defp release({:native, port}) do
    case SoftwareCommand.release_lease(port) do
      :ok -> :ok
      {:error, code} -> fail(code)
    end
  end

  defp release({:bootstrap, watcher}) do
    monitor = Process.monitor(watcher)
    deadline = System.monotonic_time(:millisecond) + 1000
    send(watcher, :release)

    receive do
      {:bootstrap_released, ^watcher, :ok} ->
        receive do
          {:DOWN, ^monitor, :process, ^watcher, :normal} -> :ok
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            fail(:workspace_unlock_unverified)
        end

      {:bootstrap_released, ^watcher, _} ->
        fail(:workspace_unlock_failed)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        fail(:workspace_unlock_unverified)
    end
  end

  defp dispatch(:build, context) do
    manifest_path = Path.join(context.workspace, "peer-manifest.json")

    if File.exists?(manifest_path) do
      verify(context, SoftwareManifest.read(manifest_path))
      :ok
    else
      build(context, manifest_path)
    end
  end

  defp dispatch(:run, context) do
    manifest =
      verify(context, SoftwareManifest.read(Path.join(context.workspace, "peer-manifest.json")))

    Wotex.BACnet.SoftwareRun.run(context, manifest)
  end

  defp prepare(:build, workspace) do
    File.mkdir_p!(workspace)
    entries = File.ls!(workspace)
    unless entries == [] or "peer-manifest.json" in entries, do: fail(:unrelated_workspace)
  end

  defp prepare(:run, workspace) do
    unless File.dir?(workspace), do: fail(:invalid_workspace)
  end

  defp build(context, manifest_path) do
    try do
      compiler = executable(System.get_env("CC", "cc"))
      docker = executable("docker")
      curl = executable("curl")
      source = Path.join(context.root, "test/interop/native/command.c")

      case SoftwareCommand.bootstrap(compiler, source, context.guardian) do
        {:ok, log, 0} -> File.write!(Path.join(context.workspace, "compiler.log"), log)
        _ -> fail(:compiler_bootstrap_failed_cleanup_unverified)
      end

      compiler_info = %{
        "name" => Path.basename(compiler),
        "sha256" => SoftwareManifest.digest(compiler),
        "version" => capture(context, compiler, ["--version"])
      }

      SoftwareManifest.write(Path.join(context.workspace, "compiler.json"), compiler_info)
      package = download_package(context, curl)
      archive = download(context, curl)
      build_context = Path.join(context.workspace, "context")
      File.mkdir!(build_context)
      File.write!(Path.join(build_context, "source.tar.gz"), archive)

      for name <- @fixture_files do
        File.cp!(
          Path.join([context.root, "test/interop/cstack", name]),
          Path.join(build_context, name)
        )
      end

      image_file = Path.join(context.workspace, "image.id")

      log =
        capture(
          context,
          docker,
          [
            "build",
            "--progress=plain",
            "--iidfile",
            image_file,
            "--file",
            Path.join(build_context, "Dockerfile.software"),
            build_context
          ],
          timeout: 600_000
        )

      File.write!(Path.join(context.workspace, "build.log"), log)
      image_id = File.read!(image_file) |> String.trim()
      unless Regex.match?(~r/\Asha256:[a-f0-9]{64}\z/, image_id), do: fail(:invalid_image_id)
      [image] = Jason.decode!(capture(context, docker, ["image", "inspect", image_id]))
      unless image["Id"] == image_id and image["Os"] == "linux", do: fail(:image_identity_mismatch)
      native = native_info(context, docker, image_id)
      SoftwareManifest.write(Path.join(context.workspace, "native-toolchain.json"), native)

      unless SoftwareManifest.identity(context.root) == context.source,
        do: fail(:source_changed_during_build)

      manifest = %{
        "schema" => "wotex.bacnet.native-peer@1",
        "status" => "ready",
        "source_url" => SoftwareManifest.source_url(context.sources),
        "source_commit" => SoftwareManifest.pin(context.sources),
        "source_archive_sha256" => SoftwareManifest.archive_sha(context.sources),
        "source_inventory_sha256" => context.sources.sha256,
        "runtime_dependency" => package,
        "inputs" => context.inputs,
        "build_source" => context.source,
        "image_id" => image_id,
        "operating_system" => image["Os"],
        "architecture" => image["Architecture"],
        "compiler" => compiler_info,
        "native" => native,
        "container_base" => @base,
        "build_options" => @build_options,
        "native_cases" => ["WBA-CP01-control-boundaries", "WBA-CP10-property-boundaries"],
        "files" => file_hashes(context.workspace)
      }

      SoftwareManifest.write(manifest_path, manifest)
      :ok
    rescue
      error ->
        SoftwareManifest.write(Path.join(context.workspace, "build-result.json"), %{
          "schema" => "wotex.bacnet.build@1",
          "status" => "failed",
          "failure" => failure_code(error),
          "cleanup" => "unverified"
        })

        reraise error, __STACKTRACE__
    end
  end

  defp download_package(context, curl) do
    archive = download_bytes(context, curl, SoftwarePackage.url(context.sources), 1_048_576)

    package =
      SoftwarePackage.verify(
        archive,
        Mix.Dep.Lock.read()[:bacstack],
        Mix.Project.deps_paths()[:bacstack],
        context.sources
      )

    File.write!(Path.join(context.workspace, "bacstack.tar"), archive)
    SoftwareManifest.write(Path.join(context.workspace, "bacstack-source.json"), package)
    package
  end

  defp download(context, curl) do
    archive =
      download_bytes(context, curl, SoftwareManifest.source_url(context.sources), 16_777_216)

    unless SoftwareManifest.hash(archive) == SoftwareManifest.archive_sha(context.sources),
      do: fail(:archive_hash_mismatch)

    path = Path.join(context.workspace, "source.tar.gz")
    File.write!(path, archive)
    # The pinned GitHub archive has one global PAX comment containing its commit.
    # Validate that exact record before omitting it from filesystem member checks.
    expanded = :zlib.gunzip(archive)
    expected_comment = "52 comment=" <> SoftwareManifest.pin(context.sources) <> "\n"

    unless binary_part(expanded, 156, 1) == "g" and
             binary_part(expanded, 512, 52) == expected_comment,
           do: fail(:unsafe_archive)

    {:ok, [{~c"pax_global_header", :unknown, 52, _, _, _, _} | entries]} =
      :erl_tar.table(String.to_charlist(path), [:compressed, :verbose])

    :ok = SoftwareManifest.archive_members(entries)
    archive
  end

  defp download_bytes(context, curl, url, limit) do
    capture(
      context,
      curl,
      [
        "--silent",
        "--show-error",
        "--fail",
        "--location",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--max-time",
        "30",
        url
      ],
      timeout: 30_000,
      limit: limit
    )
  end

  defp native_info(context, docker, image) do
    command = fn executable, args ->
      capture(
        context,
        docker,
        ["run", "--rm", "--network", "none", "--entrypoint", executable, image | args],
        timeout: 15_000
      )
    end

    versions =
      for binary <- ["/normal/wotex-bacnet-peer", "/sanitizer/wotex-bacnet-peer"], into: %{} do
        version = String.trim(command.(binary, ["--version"]))

        unless version == "wotex-bacnet-peer 1 bacnet-stack 1.7.0-rc4",
          do: fail(:native_version_mismatch)

        {binary, version}
      end

    hashes = parse_hashes(command.("/usr/bin/sha256sum", @binaries))
    unless Enum.sort(Map.keys(hashes)) == Enum.sort(@binaries), do: fail(:native_hash_mismatch)

    archive = command.("/usr/bin/tar", ["-C", "/provenance", "-cf", "-" | @metadata_files])
    {:ok, entries} = :erl_tar.table({:binary, archive}, [:verbose])
    :ok = SoftwareManifest.archive_members(entries)
    {:ok, files} = :erl_tar.extract({:binary, archive}, [:memory])
    metadata = Map.new(files, fn {name, bytes} -> {List.to_string(name), bytes} end)

    unless Enum.sort(Map.keys(metadata)) == Enum.sort(@metadata_files),
      do: fail(:native_metadata_mismatch)

    unless parse_hashes(metadata["sha256.txt"]) == hashes, do: fail(:native_hash_mismatch)

    %{
      "versions" => versions,
      "metadata" => metadata,
      "binary_hashes" => hashes
    }
  end

  defp parse_hashes(output) do
    output
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [hash, name] = String.split(line, ~r/\s+/, parts: 2)
      unless Regex.match?(~r/\A[0-9a-f]{64}\z/, hash), do: fail(:native_hash_mismatch)
      {name, hash}
    end)
  end

  defp file_hashes(workspace) do
    names =
      [
        "source.tar.gz",
        "bacstack.tar",
        "bacstack-source.json",
        "command",
        "compiler.json",
        "native-toolchain.json",
        "context/source.tar.gz"
      ] ++ Enum.map(@fixture_files, &("context/" <> &1))

    Map.new(names, &{&1, SoftwareManifest.digest(Path.join(workspace, &1))})
  end

  defp verify(context, manifest) do
    SoftwareManifest.verify_local(context.root, context.workspace, manifest)

    unless manifest["container_base"] == @base and manifest["build_options"] == @build_options,
      do: fail(:build_options_mismatch)

    unless manifest["build_source"] == context.source, do: fail(:build_source_mismatch)

    unless manifest["native_cases"] ==
             ["WBA-CP01-control-boundaries", "WBA-CP10-property-boundaries"],
           do: fail(:native_case_mismatch)

    package =
      SoftwarePackage.verify(
        File.read!(Path.join(context.workspace, "bacstack.tar")),
        Mix.Dep.Lock.read()[:bacstack],
        Mix.Project.deps_paths()[:bacstack],
        context.sources
      )

    unless package == manifest["runtime_dependency"], do: fail(:bacstack_installed_mismatch)
    compiler = executable(System.get_env("CC", "cc"))

    unless manifest["compiler"]["sha256"] == SoftwareManifest.digest(compiler),
      do: fail(:compiler_changed)

    docker = executable("docker")
    image_id = manifest["image_id"]

    unless is_binary(image_id) and Regex.match?(~r/\Asha256:[a-f0-9]{64}\z/, image_id),
      do: fail(:invalid_image_id)

    identity = capture(context, docker, ["image", "inspect", image_id, "--format", "{{.Id}}"])
    unless String.trim(identity) == image_id, do: fail(:image_identity_mismatch)

    unless native_info(context, docker, image_id) == manifest["native"],
      do: fail(:native_hash_mismatch)

    unless SoftwareManifest.inputs(context.root) == context.inputs,
      do: fail(:source_changed_during_build)

    manifest
  end

  defp capture(context, executable, arguments, options \\ []) do
    options = Keyword.merge([cd: context.root], options)
    result = SoftwareCommand.run(context.guardian, executable, arguments, options)

    {output, status} =
      case result do
        {:ok, output, status} -> {output, status}
        _ -> {"", "unverified"}
      end

    name = "command-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    File.write!(Path.join(context.workspace, name <> ".output"), output)

    SoftwareManifest.write(Path.join(context.workspace, name <> ".json"), %{
      "executable" => executable,
      "executable_sha256" => SoftwareManifest.digest(executable),
      "arguments" => arguments,
      "exit_code" => status,
      "output_bytes" => byte_size(output),
      "output_sha256" => SoftwareManifest.hash(output)
    })

    if status == 0, do: output, else: fail(:fixture_command_failed)
  end

  defp executable(name) do
    System.find_executable(name) || fail(:required_tool_missing)
  end

  defp failure_code(%Mix.Error{message: message}), do: message
  defp failure_code(_), do: "fixture_io_failure"
  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
