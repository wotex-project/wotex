# Builds one exact Hex archive and verifies an isolated public-API consumer.
#
#     WOTEX_PATH_DEPS=1 mix package
#     WOTEX_CORE_ARCHIVE=/absolute/archive.tar mix package
#     WOTEX_DIRECTORY_ARCHIVE=/absolute/directory.tar WOTEX_CORE_ARCHIVE=/absolute/core.tar mix package

Code.require_file("evidence.exs", __DIR__)
Code.require_file("package_mirror.exs", __DIR__)

defmodule CheckArchive do
  @moduledoc false

  @runtime_dependencies [:decimal, :ex_json_schema, :jason]
  @support ~w(fixtures memory_repository scoped_memory_repository table_repository repository_probe repository_contract repository_barrier public_operation_contract reference_consumer_contract reference_authorization reference_clock reference_identifier test_authorization test_clock test_identifier)
  @forbidden ~w(.claude .codex .agents .git .github AGENTS.md CLAUDE.md _build deps doc cover test bin docs tasks priv/plts)

  def run do
    source = File.cwd!()
    root = System.get_env("WOTEX_EVIDENCE_ROOT") || temporary_directory()
    DirectoryEvidence.external_root!(root)

    unless Enum.all?(File.ls!(root), &(&1 in ["inputs.etf", "compiler.exit"])),
      do: raise("archive verification requires a fresh external evidence directory")

    unless File.regular?(Path.join(root, "inputs.etf")), do: DirectoryEvidence.inputs!(root)
    archive = Path.join(root, "wotex_directory-#{Mix.Project.config()[:version]}.tar")

    try do
      verify(source, root, archive)
      IO.puts("archive artifacts: #{root}")
    after
      File.rm_rf!(Path.join(root, "consumer"))
      File.rm_rf!(Path.join(root, "package-source"))
    end
  end

  defp verify(source, root, archive) do
    core_archive = core_archive(root)
    mirror = directory_archive!(source, root, archive)
    consumer = Path.join(root, "consumer")
    directory = Path.join(consumer, "packages/wotex_directory")
    core = Path.join(consumer, "packages/wotex")
    metadata = unpack!(archive, directory)
    core_metadata = unpack!(core_archive, core)
    validate_metadata!(metadata, "wotex_directory")
    validate_metadata!(core_metadata, "wotex")
    inspect_directory!(directory, metadata)
    metadata_bytes = File.read!(Path.join(consumer, "packages/wotex_directory.metadata"))
    package_proof = package_proof!(mirror, directory, metadata_bytes)
    run!("elixir", [Path.join(source, "bin/check_boundary.exs"), directory], root)

    lock = Mix.Dep.Lock.read() |> Map.take(@runtime_dependencies)
    unless map_size(lock) == 3, do: raise("expected the complete core runtime lock cohort")
    prepare_consumer!(source, consumer, lock)
    run!("mix", ["deps.get", "--check-locked"], consumer)
    original_lock = File.read!(Path.join(consumer, "mix.lock"))
    run!("mix", ["run", "--no-start", "--no-compile", "--no-deps-check", "verify.exs"], consumer)

    unless File.read!(Path.join(consumer, "mix.lock")) == original_lock,
      do: raise("consumer changed its dependency lock")

    File.cp!(Path.join(consumer, "mix.lock"), Path.join(root, "consumer.mix.lock"))

    consumer_result =
      consumer |> Path.join("consumer-results.json") |> File.read!() |> Jason.decode!()

    DirectoryEvidence.archive!(root, %{
      "directory_version" => metadata["version"],
      "core_version" => core_metadata["version"],
      "directory_input" =>
        if(System.get_env("WOTEX_DIRECTORY_ARCHIVE"),
          do: "supplied_archive",
          else: "source_build"
        ),
      "core_input" =>
        if(System.get_env("WOTEX_CORE_ARCHIVE"),
          do: "supplied_archive",
          else: "explicit_dependency_source"
        ),
      "files" => %{
        Path.basename(archive) => digest(archive),
        Path.basename(core_archive) => digest(core_archive),
        "consumer.mix.lock" => digest(Path.join(root, "consumer.mix.lock"))
      },
      "hex_cohort" =>
        for(
          {name, {:hex, _, version, checksum, _, _, _, outer}} <- lock,
          into: %{},
          do:
            {Atom.to_string(name),
             %{"version" => version, "checksum" => checksum, "outer_checksum" => outer}}
        ),
      "consumer_result" => consumer_result,
      "consumer_commands" => [
        "mix deps.get --check-locked",
        "mix run --no-start --no-compile --no-deps-check verify.exs"
      ],
      "warnings_as_errors" => true,
      "package_exclusion" => package_proof,
      "source_checkout_fallback" => false
    })

    IO.puts("directory archive sha256: #{digest(archive)}")
    IO.puts("core archive sha256: #{digest(core_archive)}")
    IO.puts("consumer lock sha256: #{digest(Path.join(root, "consumer.mix.lock"))}")
    IO.puts("consumer Hex cohort: #{inspect(lock, limit: :infinity, printable_limit: :infinity)}")

    IO.puts(
      "archive-only repository, interleaving and reference contracts passed with both consumers"
    )
  end

  defp directory_archive!(source, root, target) do
    case System.get_env("WOTEX_DIRECTORY_ARCHIVE") do
      nil ->
        mirror =
          DirectoryPackageMirror.prepare!(source, root, Mix.Project.config()[:package][:files])

        run!("mix", ["hex.build", "--output", target], mirror.directory)
        mirror

      supplied ->
        copy_archive!(supplied, target, "WOTEX_DIRECTORY_ARCHIVE")
        nil
    end
  end

  defp package_proof!(nil, _directory, _metadata),
    do: %{"sentinel_build" => false, "directory_build_count" => 0}

  defp package_proof!(mirror, directory, metadata) do
    proof = DirectoryPackageMirror.verify!(mirror, directory, metadata)

    IO.puts(
      "package mirror: #{map_size(mirror.inputs)} exact public files; #{map_size(mirror.sentinels)} excluded sentinels; one Directory build"
    )

    Map.merge(proof, %{"sentinel_build" => true, "directory_build_count" => 1})
  end

  defp core_archive(root) do
    target = Path.join(root, "wotex.tar")

    case System.get_env("WOTEX_CORE_ARCHIVE") do
      nil ->
        unless System.get_env("WOTEX_PATH_DEPS") == "1",
          do: raise("supply WOTEX_CORE_ARCHIVE or explicitly select WOTEX_PATH_DEPS=1")

        {:wotex, options} = Enum.find(Mix.Project.config()[:deps], &match?({:wotex, _}, &1))
        source = Keyword.fetch!(options, :path)
        run!("mix", ["hex.build", "--output", target], source)

      supplied ->
        copy_archive!(supplied, target, "WOTEX_CORE_ARCHIVE")
    end

    target
  end

  defp copy_archive!(supplied, target, variable) do
    unless File.regular?(supplied), do: raise("#{variable} must name a regular archive")
    File.cp!(supplied, target)
  end

  defp unpack!(archive, destination) do
    {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    outer = Map.new(outer, fn {name, bytes} -> {List.to_string(name), bytes} end)

    unless Enum.sort(Map.keys(outer)) == ~w(CHECKSUM VERSION contents.tar.gz metadata.config),
      do: raise("invalid Hex archive envelope")

    unless outer["VERSION"] == "3", do: raise("unsupported Hex archive version")

    checksum =
      :crypto.hash(
        :sha256,
        outer["VERSION"] <> outer["metadata.config"] <> outer["contents.tar.gz"]
      )

    unless Base.encode16(checksum) == String.upcase(outer["CHECKSUM"]),
      do: raise("Hex archive checksum mismatch")

    {:ok, entries} = :erl_tar.extract({:binary, outer["contents.tar.gz"]}, [:compressed, :memory])
    File.mkdir_p!(destination)

    Enum.each(entries, fn {name, bytes} ->
      relative = List.to_string(name)
      validate_relative!(relative)
      path = Path.join(destination, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
    end)

    metadata_file =
      Path.join(Path.dirname(destination), Path.basename(destination) <> ".metadata")

    File.write!(metadata_file, outer["metadata.config"])
    {:ok, metadata} = :file.consult(String.to_charlist(metadata_file))
    Map.new(metadata)
  end

  defp validate_relative!(path) do
    if Path.type(path) != :relative or Enum.any?(Path.split(path), &(&1 in ["..", "."])) or
         String.contains?(path, "\\"),
       do: raise("unsafe archive member path")
  end

  defp validate_metadata!(metadata, name) do
    unless metadata["name"] == name and metadata["app"] == name,
      do: raise("unexpected archive package identity")

    unless Version.match?(metadata["version"], "~> 0.1.0"),
      do: raise("archive version does not satisfy the directory dependency contract")
  end

  defp inspect_directory!(directory, metadata) do
    files = metadata["files"] |> Enum.sort()

    Enum.each(files, fn path ->
      validate_relative!(path)

      unless File.exists?(Path.join(directory, path)),
        do: raise("archive metadata names a missing member: #{path}")
    end)

    actual = Path.wildcard(Path.join(directory, "**/*"), match_dot: true)

    actual =
      actual
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, directory))
      |> Enum.sort()

    unless actual == Enum.sort(Enum.filter(files, &File.regular?(Path.join(directory, &1)))),
      do: raise("archive metadata does not match its files")

    expected = Mix.Project.config()[:package][:files]
    allowed = Enum.reject(expected, &(&1 == "lib"))

    Enum.each(actual, fn path ->
      unless path in allowed or
               (String.starts_with?(path, "lib/") and Path.extname(path) == ".ex"),
             do: raise("undeclared package file: #{path}")
    end)

    Enum.each(allowed, fn path ->
      unless path in actual, do: raise("missing package file: #{path}")
    end)

    Enum.each(@forbidden, fn path ->
      if File.exists?(Path.join(directory, path)),
        do: raise("development state in archive: #{path}")
    end)

    Enum.each(actual, fn path ->
      if Enum.any?(~w(docs tasks), &(&1 in Path.split(path))),
        do: raise("repository documentation or task state in archive: #{path}")
    end)

    requirements = Enum.map(metadata["requirements"], &Map.new/1)

    unless requirements == [
             %{
               "app" => "wotex",
               "name" => "wotex",
               "optional" => false,
               "repository" => "hexpm",
               "requirement" => "~> 0.1.0"
             }
           ],
           do: raise("Directory archive must depend only on the normal wotex Hex package")
  end

  defp prepare_consumer!(source, consumer, lock) do
    File.cp!(Path.join(source, "bin/archive_consumer.exs"), Path.join(consumer, "verify.exs"))
    support = Path.join(consumer, "support")
    File.mkdir!(support)

    for name <- @support,
        do:
          File.cp!(
            Path.join(source, "test/support/wotex/directory/#{name}.ex"),
            Path.join(support, "#{name}.ex")
          )

    File.cp!(
      Path.join(source, "bin/archive_consumer_test.exs"),
      Path.join(consumer, "archive_consumer_test.exs")
    )

    File.cp!(
      Path.join(source, "test/wotex/directory/table_repository_contract_test.exs"),
      Path.join(consumer, "table_repository_contract_test.exs")
    )

    File.cp!(
      Path.join(source, "test/wotex/directory/compatibility_test.exs"),
      Path.join(consumer, "compatibility_test.exs")
    )

    File.write!(
      Path.join(consumer, "mix.lock"),
      inspect(lock, limit: :infinity, printable_limit: :infinity) <> "\n"
    )

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule ArchiveConsumer.MixProject do
      use Mix.Project
      def project do
        [app: :archive_consumer, version: "0.0.0", elixir: "~> 1.18",
         elixirc_paths: ["support"], deps: [
           {:wotex_directory, path: "packages/wotex_directory"},
           {:wotex, path: "packages/wotex", override: true}
         ]]
      end
      def application, do: [extra_applications: []]
    end
    """)
  end

  defp run!(command, arguments, directory) do
    environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"WOTEX_EVIDENCE_ROOT", nil},
      {"MIX_ENV", "prod"},
      {"MIX_PATH", ""},
      {"ERL_LIBS", ""},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil},
      {"ERL_FLAGS", nil},
      {"ELIXIR_ERL_OPTIONS", nil}
    ]

    {_output, status} =
      System.cmd(command, arguments,
        cd: directory,
        env: environment,
        into: IO.stream(),
        stderr_to_stdout: true
      )

    unless status == 0, do: raise("#{command} #{Enum.join(arguments, " ")} failed: #{status}")
  end

  defp temporary_directory do
    {directory, 0} =
      System.cmd("mktemp", ["-d", Path.join(System.tmp_dir!(), "wotex-directory-archive.XXXXXX")])

    String.trim(directory)
  end

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
end

CheckArchive.run()
