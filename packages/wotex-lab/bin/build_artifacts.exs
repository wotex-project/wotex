# Builds local candidate artifacts without publishing them. The output path
# must be new and absolute. The default build creates every artifact that needs
# no external runtime; `--workbench-release` also builds the clone-free release.
#
#   mix run --no-start bin/build_artifacts.exs --output /absolute/new/directory
#

Code.require_file("support/archive_repository.exs", __DIR__)
Code.require_file("support/child_environment.exs", __DIR__)
Code.require_file("support/distribution.exs", __DIR__)
Code.require_file("support/reference_inputs.exs", __DIR__)

defmodule Wotex.Lab.BuildArtifacts do
  @moduledoc false

  alias Wotex.Lab.Check.{ArchiveRepository, ChildEnvironment, Distribution, ReferenceInputs}
  alias Wotex.Lab.Evidence.Digest

  @packages [
    {:wotex, "wotex"},
    {:wotex_runtime, "wotex-runtime"},
    {:wotex_binding_http, "wotex-binding-http"},
    {:wotex_binding_mqtt, "wotex-binding-mqtt"},
    {:wotex_modbus, "wotex-modbus"},
    {:wotex_coap, "wotex-coap"},
    {:wotex_bacnet, "wotex-bacnet"},
    {:wotex_opcua, "wotex-opcua"},
    {:wotex_ble, "wotex-ble"},
    {:wotex_matter, "wotex-matter"},
    {:wotex_thread, "wotex-thread"},
    {:wotex_directory, "wotex-directory"},
    {:wotex_continuum, "wotex-continuum"},
    {:wotex_nx, "wotex-nx"},
    {:wotex_conformance, "wotex-conformance"},
    {:wotex_lab, "wotex-lab"}
  ]
  @workbench_patterns ~w(.check.exs .credo.exs .dockerignore .formatter.exs Dockerfile
                          README.md bin/**/* config/**/* lib/**/* mix_tasks/**/*
                          priv/static/**/* test/**/* mix.exs mix.lock assets/**/*)
  @nerves_patterns ~w(.check.exs .credo.exs .formatter.exs README.md config/**/* lib/**/*
                       test/**/* mix.exs mix.lock)
  @oci_patterns ~w(.dockerignore Dockerfile README.md config/**/* lib/**/* mix_tasks/**/*
                    priv/static/**/* mix.exs mix.lock assets/**/*)

  @spec run([String.t()]) :: :ok
  def run(argv) do
    {output, workbench_release?} = parse!(argv)
    create_output!(output)
    root = Path.expand("..", __DIR__)
    hex = Path.join(output, "hex")
    npm = Path.join(output, "npm")
    source = Path.join(output, "source")
    Enum.each([hex, npm, source], &File.mkdir!/1)

    ArchiveRepository.build_archives!(root, @packages, hex)

    archive!(
      Path.join(root, "hosts/workbench"),
      @workbench_patterns,
      Path.join(source, "wotex-lab-workbench.tar")
    )

    archive!(
      Path.join(root, "hosts/workbench"),
      @oci_patterns,
      Path.join(source, "wotex-lab-oci-context.tar")
    )

    archive!(
      Path.join(root, "hosts/nerves"),
      @nerves_patterns,
      Path.join(source, "wotex-lab-nerves-rpi4.tar")
    )

    npm!(root, npm)
    if workbench_release?, do: workbench_release!(root, output)
    {:ok, lab_digest} = ReferenceInputs.digest(root)
    source_digest = combined_source_digest(root, lab_digest)
    revision = ArchiveRepository.revision(root)
    {:ok, manifest} = Distribution.build_manifest(output, revision, source_digest)
    {:ok, encoded} = Distribution.encode(manifest)
    File.write!(Path.join(output, "manifest.json"), encoded)
    :ok = Distribution.validate_manifest(manifest, output)

    IO.puts("candidate artifacts: #{length(manifest["artifacts"])} files written to #{output}")
  end

  defp parse!(["--output", output | options]) when options in [[], ["--workbench-release"]] do
    (Path.type(output) == :absolute and Path.basename(output) not in ["", ".", ".."] and
       not File.exists?(output)) ||
      abort("--output must name a new absolute directory")

    {Path.expand(output), options == ["--workbench-release"]}
  end

  defp parse!(_) do
    abort(
      "usage: mix run --no-start bin/build_artifacts.exs --output ABSOLUTE_PATH [--workbench-release]"
    )
  end

  defp create_output!(output) do
    File.mkdir_p!(Path.dirname(output))

    case File.mkdir(output) do
      :ok -> File.chmod!(output, 0o700)
      {:error, reason} -> abort("cannot create artifact output: #{:file.format_error(reason)}")
    end
  end

  defp archive!(root, patterns, output) do
    files = source_files(root, patterns)
    relative = Enum.map(files, &Path.relative_to(&1, root))

    {log, status} =
      System.cmd("tar", ["-cf", output, "-C", root | relative],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    status == 0 || abort("source artifact failed (#{status}):\n#{log}")
    File.regular?(output) || abort("source artifact was not created")
  end

  defp source_files(root, patterns) do
    files =
      patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()

    files == [] && abort("source artifact would be empty")

    Enum.each(files, fn path ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path)) &&
        abort("source artifact refuses symlink #{Path.relative_to(path, root)}")
    end)

    files
  end

  defp npm!(root, output) do
    client = Path.join(root, "clients/typescript")
    npm = System.find_executable("npm") || abort("npm is required to build the generated client")

    run!(npm, ["test", "--ignore-scripts"], client, "TypeScript client tests")
    run!(npm, ["pack", "--dry-run", "--json", "--ignore-scripts"], client, "npm dry run")
    run!(npm, ["pack", "--pack-destination", output, "--ignore-scripts"], client, "npm package")

    case Path.wildcard(Path.join(output, "*.tgz")) do
      [_] -> :ok
      files -> abort("npm package produced #{length(files)} archives")
    end
  end

  defp run!(executable, args, directory, label) do
    case System.cmd(executable, args,
           cd: directory,
           env: ChildEnvironment.scrubbed(),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, status} -> abort("#{label} failed (#{status}):\n#{output}")
    end
  end

  defp workbench_release!(root, output) do
    release = Path.join(output, "release")

    case System.cmd(
           "mix",
           [
             "run",
             "--no-start",
             "bin/check_workbench_archive.exs",
             "--output",
             release
           ],
           cd: root,
           env: [{"WOTEX_PATH_DEPS", "1"} | ChildEnvironment.scrubbed()],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {log, status} -> abort("Workbench release build failed (#{status}):\n#{log}")
    end
  end

  defp combined_source_digest(root, lab_digest) do
    {:ok, workbench} = Digest.tree(Path.join(root, "hosts/workbench"), @workbench_patterns)
    {:ok, nerves} = Digest.tree(Path.join(root, "hosts/nerves"), @nerves_patterns)
    Digest.bytes(Enum.join([lab_digest, workbench, nerves], "\n"))
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.BuildArtifacts.run(System.argv())
