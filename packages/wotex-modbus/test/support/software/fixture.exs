Code.require_file("command.exs", __DIR__)
Code.require_file("manifest.exs", __DIR__)
Code.require_file("run.exs", __DIR__)

defmodule Wotex.Modbus.SoftwareFixture do
  @moduledoc false

  alias Wotex.Modbus.{SoftwareCommand, SoftwareManifest}

  @spec main(:build | :run, [String.t()]) :: :ok
  def main(operation, arguments) do
    root = File.cwd!()
    workspace = SoftwareManifest.arguments(arguments, root)
    prepare(operation, workspace)
    context = %{root: root, workspace: workspace, guardian: Path.join(workspace, "command")}
    lease = lease(context)

    try do
      result = dispatch(operation, context)
      Mix.shell().info("software fixture #{operation} completed: #{workspace}")
      result
    after
      release(lease)
    end
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
              File.rmdir(path)

            {:DOWN, ^monitor, :process, ^owner, _} ->
              File.rmdir(path)
          end
        end)

      {:bootstrap, watcher, path}
    end
  end

  defp release({:native, port}) do
    case SoftwareCommand.release_lease(port) do
      :ok -> :ok
      {:error, code} -> fail(code)
    end
  end

  defp release({:bootstrap, watcher, path}) do
    File.rmdir(path)
    send(watcher, :release)
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

    Wotex.Modbus.SoftwareRun.run(context, manifest)
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
      archive = download(context, curl)
      build_context = Path.join(context.workspace, "context")
      File.mkdir!(build_context)
      File.write!(Path.join(build_context, "source.tar.gz"), archive)

      for name <- ["server.c", "Dockerfile"] do
        File.cp!(
          Path.join([context.root, "test/interop/libmodbus", name]),
          Path.join(build_context, name)
        )
      end

      image_file = Path.join(context.workspace, "image.id")

      log =
        capture(
          context,
          docker,
          ["build", "--progress=plain", "--iidfile", image_file, build_context],
          timeout: 600_000
        )

      File.write!(Path.join(context.workspace, "build.log"), log)
      image_id = File.read!(image_file) |> String.trim()
      unless Regex.match?(~r/\Asha256:[a-f0-9]{64}\z/, image_id), do: fail(:invalid_image_id)
      [image] = Jason.decode!(capture(context, docker, ["image", "inspect", image_id]))
      unless image["Id"] == image_id and image["Os"] == "linux", do: fail(:image_identity_mismatch)
      native = native_info(context, docker, image_id)
      SoftwareManifest.write(Path.join(context.workspace, "native-toolchain.json"), native)

      manifest = %{
        "schema" => "wotex.modbus.native-peer@1",
        "status" => "ready",
        "source_url" => SoftwareManifest.source_url(),
        "source_commit" => SoftwareManifest.pin(),
        "source_archive_sha256" => SoftwareManifest.archive_sha(),
        "inputs" => SoftwareManifest.inputs(context.root),
        "image_id" => image_id,
        "operating_system" => image["Os"],
        "architecture" => image["Architecture"],
        "compiler" => compiler_info,
        "native" => native,
        "configure_options" => ["--prefix=/opt/libmodbus", "--disable-shared", "--enable-static"],
        "compiler_options" => [
          "-O1",
          "-g",
          "-fsanitize=address,undefined",
          "-fno-omit-frame-pointer"
        ],
        "linker_options" => ["-fsanitize=address,undefined"],
        "sanitizers" => ["address", "undefined", "leak"],
        "files" => file_hashes(context.workspace)
      }

      SoftwareManifest.write(manifest_path, manifest)
      :ok
    rescue
      error ->
        SoftwareManifest.write(Path.join(context.workspace, "build-result.json"), %{
          "schema" => "wotex.modbus.build@1",
          "status" => "failed",
          "failure" => failure_code(error),
          "cleanup" => "unverified"
        })

        reraise error, __STACKTRACE__
    end
  end

  defp download(context, curl) do
    archive =
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
          SoftwareManifest.source_url()
        ],
        timeout: 30_000,
        limit: 8_388_608
      )

    unless SoftwareManifest.hash(archive) == SoftwareManifest.archive_sha(),
      do: fail(:archive_hash_mismatch)

    path = Path.join(context.workspace, "source.tar.gz")
    File.write!(path, archive)
    # The pinned GitHub archive has one global PAX comment containing its commit.
    # Validate that exact record before omitting it from filesystem member checks.
    expanded = :zlib.gunzip(archive)
    expected_comment = "52 comment=" <> SoftwareManifest.pin() <> "\n"

    unless binary_part(expanded, 156, 1) == "g" and
             binary_part(expanded, 512, 52) == expected_comment,
           do: fail(:unsafe_archive)

    {:ok, [{~c"pax_global_header", :unknown, 52, _, _, _, _} | entries]} =
      :erl_tar.table(String.to_charlist(path), [:compressed, :verbose])

    :ok = SoftwareManifest.archive_members(entries)
    archive
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

    version = command.("/usr/local/bin/fixture", ["--version"])
    unless String.trim(version) == "3.1.12", do: fail(:native_version_mismatch)

    hashes =
      command.("/usr/bin/sha256sum", ["/usr/local/bin/fixture", "/opt/libmodbus/lib/libmodbus.a"])

    %{
      "version" => String.trim(version),
      "compiler" => command.("/usr/bin/cc", ["--version"]),
      "binary_hashes" => parse_hashes(hashes)
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
    names = [
      "source.tar.gz",
      "command",
      "compiler.json",
      "native-toolchain.json",
      "context/source.tar.gz",
      "context/server.c",
      "context/Dockerfile"
    ]

    Map.new(names, &{&1, SoftwareManifest.digest(Path.join(workspace, &1))})
  end

  defp verify(context, manifest) do
    SoftwareManifest.verify_local(context.root, context.workspace, manifest)
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

    manifest
  end

  defp capture(context, executable, arguments, options \\ []) do
    options = Keyword.merge([cd: context.root], options)

    case SoftwareCommand.run(context.guardian, executable, arguments, options) do
      {:ok, output, 0} -> output
      _ -> fail(:fixture_command_failed)
    end
  end

  defp executable(name) do
    System.find_executable(name) || fail(:required_tool_missing)
  end

  defp failure_code(%Mix.Error{message: message}), do: message
  defp failure_code(_), do: "fixture_io_failure"
  defp fail(code), do: Mix.raise(Atom.to_string(code))
end
