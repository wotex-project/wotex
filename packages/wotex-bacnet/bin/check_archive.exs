defmodule Wotex.BACnet.Check.Archive do
  @moduledoc false

  @prefix "wotex-bacnet-archive."
  @version "0.1.0"
  @consumer_fixture "test/fixtures/archive_reference_consumer.exs"
  @mutable_source ~r/{<<"repository">>,<<"(?:git|path)">>|{<<"path">>/
  # Documentation lives in the monorepo `docs/` tree and reaches consumers through
  # HexDocs; no `docs` or `tasks` path may ship in the archive.
  @machinery ~r{(^|/)(\.check\.exs|\.claude|\.credo\.exs|\.doctor\.exs|\.git|\.github|\.tool-versions|AGENTS\.md|CLAUDE\.md|bin|config|cover|deps|doc|docs|mix\.lock|priv/plts|test|_build)(/|$)|^tasks(/|$)}
  @required_content ~w(
    .formatter.exs
    CHANGELOG.md
    LICENSE
    NOTICE
    README.md
    mix.exs
  )
  # Machine-read fixtures ship only in this package's archive; the exact core
  # and Runtime archives carry their own `priv/` content.
  @required_fixtures ~w(
    priv/fixtures/contract-v1.json
    priv/fixtures/ingress-v1.json
    priv/fixtures/software-sources-v1.json
    priv/fixtures/wotex-integration-v1.json
  )

  @packages [
    %{app: :wotex, directory: "wotex", archive: "wotex-0.1.0.tar", requires: []},
    %{
      app: :wotex_runtime,
      directory: "wotex-runtime",
      archive: "wotex_runtime-0.1.0.tar",
      requires: [:wotex]
    },
    %{
      app: :wotex_bacnet,
      directory: "wotex-bacnet",
      archive: "wotex_bacnet-0.1.0.tar",
      requires: [:wotex, :wotex_runtime]
    }
  ]

  @spec main() :: :ok
  def main do
    root = File.cwd!()
    workspace = Path.dirname(root)
    work = Path.join(System.tmp_dir!(), "#{@prefix}#{unique()}")

    result =
      try do
        verify(root, workspace, work)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        cleanup(work)
      end

    report(result)
  end

  defp verify(root, workspace, work) do
    archive_directory = Path.join(work, "archives")
    package_directory = Path.join(work, "packages")
    snapshot_directory = Path.join(work, "sources")
    consumer = Path.join(work, "reference_consumer")
    File.mkdir_p!(archive_directory)
    File.mkdir_p!(package_directory)
    File.mkdir_p!(snapshot_directory)

    packages =
      Enum.map(@packages, fn package ->
        repository = source_repository(package, root, workspace)
        source = source_tree(package, repository, snapshot_directory)
        archive = Path.join(archive_directory, package.archive)
        extracted = Path.join(package_directory, Atom.to_string(package.app))

        source_project!(source, package.app)
        build_once!(source, archive)
        inspect_archive!(archive, package)
        extract_archive!(archive, extracted)

        Map.merge(package, %{
          archive_path: archive,
          digest: digest(archive),
          extracted: extracted,
          repository: repository,
          revision: revision(repository)
        })
      end)

    write_consumer!(consumer, packages)
    exercise_consumer!(consumer, packages)
    report_evidence(packages, consumer)
    :ok
  end

  defp source_repository(%{app: :wotex_bacnet}, root, _workspace), do: root

  defp source_repository(%{directory: directory}, _root, workspace),
    do: Path.join(workspace, directory)

  defp source_tree(%{app: :wotex_bacnet}, repository, _snapshots), do: repository

  defp source_tree(package, repository, snapshots) do
    destination = Path.join(snapshots, Atom.to_string(package.app))
    archive = Path.join(snapshots, "#{package.app}.tar")
    File.mkdir_p!(destination)
    run!("git", ["archive", "--format=tar", "--output", archive, "HEAD"], repository)
    extract_tar!(archive, destination, [])
    destination
  end

  defp source_project!(source, app) do
    mix_file = Path.join(source, "mix.exs")

    unless File.regular?(mix_file) do
      violation("missing #{app} source project at #{mix_file}")
    end
  end

  # Every exact archive is built once. Inspection and consumer setup reuse those
  # bytes rather than asking Hex to construct a second package tree.
  defp build_once!(source, archive) do
    run!("mix", ["hex.build", "--output", archive], source, release_environment())
    unless File.regular?(archive), do: violation("Hex did not create #{archive}")
  end

  defp inspect_archive!(archive, package) do
    members = outer_members!(archive)
    metadata = member!(members, ~c"metadata.config", archive)
    contents = member!(members, ~c"contents.tar.gz", archive)

    require_metadata!(metadata, ~s({<<"name">>,<<"#{package.app}">>}), archive)
    require_metadata!(metadata, ~s({<<"version">>,<<"#{@version}">>}), archive)
    require_metadata!(metadata, ~s({<<"elixir">>,<<"~> 1.18">>}), archive)
    require_metadata!(metadata, ~s({<<"licenses">>,[<<"Apache-2.0">>]}), archive)
    require_metadata!(metadata, ~s({<<"build_tools">>,[<<"mix">>]}), archive)

    Enum.each(package.requires, fn dependency ->
      requirement =
        ~r/{<<"app">>,<<"#{dependency}">>}.*?{<<"requirement">>,<<"~> 0\.1\.0">>}/s

      unless Regex.match?(requirement, metadata) do
        violation("#{archive} does not pin #{dependency} to ~> 0.1.0")
      end
    end)

    if Regex.match?(@mutable_source, metadata) or String.contains?(metadata, "WOTEX_PATH_DEPS") do
      violation("#{archive} metadata contains a mutable dependency source")
    end

    content_members = content_members!(contents, archive)
    safe_members!(content_members, archive)

    if Enum.any?(content_members, &Regex.match?(@machinery, &1)) do
      violation("#{archive} contains development, local-task, or agent machinery")
    end

    Enum.each(required_content(package.app), fn file ->
      unless file in content_members, do: violation("#{archive} is missing #{file}")
    end)

    unless Enum.any?(content_members, &String.starts_with?(&1, "lib/")) do
      violation("#{archive} is missing library sources")
    end

    verify_package_metadata!(metadata, package.app, archive)
  end

  defp required_content(:wotex_bacnet), do: @required_content ++ @required_fixtures
  defp required_content(_app), do: @required_content

  defp verify_package_metadata!(metadata, :wotex_bacnet, archive) do
    for value <- [
          "Consumer-neutral BACnet protocol values, operations and Web of Things Form mapping",
          "https://hexdocs.pm/wotex_bacnet",
          "https://github.com/wotex-project/wotex",
          "https://github.com/wotex-project/wotex/tree/main/docs/packages/wotex-bacnet",
          "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
          "https://wotex.io"
        ] do
      require_metadata!(metadata, value, archive)
    end
  end

  defp verify_package_metadata!(_metadata, _app, _archive), do: :ok

  defp outer_members!(archive) do
    case :erl_tar.extract(String.to_charlist(archive), [:memory]) do
      {:ok, members} -> members
      {:error, reason} -> violation("cannot inspect #{archive}: #{inspect(reason)}")
    end
  end

  defp member!(members, name, archive) do
    case List.keyfind(members, name, 0) do
      {^name, content} -> content
      nil -> violation("#{archive} is missing #{List.to_string(name)}")
    end
  end

  defp content_members!(contents, archive) do
    case :erl_tar.extract({:binary, contents}, [:compressed, :memory]) do
      {:ok, members} -> Enum.map(members, fn {name, _} -> List.to_string(name) end)
      {:error, reason} -> violation("cannot inspect #{archive} contents: #{inspect(reason)}")
    end
  end

  defp safe_members!(members, archive) do
    if Enum.any?(members, fn member ->
         Path.type(member) == :absolute or ".." in Path.split(member)
       end) do
      violation("#{archive} contains an unsafe archive member")
    end
  end

  defp require_metadata!(metadata, term, archive) do
    unless String.contains?(metadata, term) do
      violation("#{archive} metadata does not contain #{term}")
    end
  end

  defp extract_archive!(archive, destination) do
    File.mkdir_p!(destination)
    members = outer_members!(archive)
    contents = member!(members, ~c"contents.tar.gz", archive)

    case :erl_tar.extract(
           {:binary, contents},
           [:compressed, {:cwd, String.to_charlist(destination)}]
         ) do
      :ok -> :ok
      {:error, reason} -> violation("cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp extract_tar!(archive, destination, options) do
    case :erl_tar.extract(
           String.to_charlist(archive),
           options ++ [{:cwd, String.to_charlist(destination)}]
         ) do
      :ok -> :ok
      {:error, reason} -> violation("cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp write_consumer!(consumer, packages) do
    File.mkdir_p!(Path.join(consumer, "test"))
    paths = Map.new(packages, &{&1.app, &1.extracted})

    File.write!(Path.join(consumer, "mix.exs"), consumer_mix(paths))
    File.write!(Path.join(consumer, "test/test_helper.exs"), "ExUnit.start()\n")

    case File.cp(
           Path.expand(@consumer_fixture),
           Path.join(consumer, "test/archive_reference_consumer_test.exs")
         ) do
      :ok -> :ok
      {:error, reason} -> violation("cannot isolate archive consumer fixture: #{inspect(reason)}")
    end
  end

  defp consumer_mix(paths) do
    """
    defmodule WotexBACnetArchiveConsumer.MixProject do
      use Mix.Project

      def project do
        [
          app: :wotex_bacnet_archive_consumer,
          version: "0.0.0",
          elixir: "~> 1.18",
          deps: deps()
        ]
      end

      def application, do: [extra_applications: []]

      defp deps do
        [
          {:wotex, path: #{inspect(paths.wotex)}, override: true},
          {:wotex_runtime, path: #{inspect(paths.wotex_runtime)}, override: true},
          {:wotex_bacnet, path: #{inspect(paths.wotex_bacnet)}, override: true}
        ]
      end
    end
    """
  end

  defp exercise_consumer!(consumer, packages) do
    paths = Map.new(packages, &{&1.app, &1.extracted})
    live_roots = Enum.map(packages, & &1.repository)

    environment =
      isolated_environment() ++
        [
          {"WOTEX_ARCHIVE_ROOTS", Enum.join(Map.values(paths), "\n")},
          {"WOTEX_LIVE_ROOTS", Enum.join(live_roots, "\n")}
        ]

    run!("mix", ["deps.get"], consumer, environment)
    run!("mix", ["deps.get", "--check-locked"], consumer, environment)
    run!("mix", ["test", "--no-start", "--warnings-as-errors"], consumer, environment)
  end

  defp report_evidence(packages, consumer) do
    Enum.each(packages, fn package ->
      IO.puts("exact archive #{package.app} #{package.revision}: sha256=#{package.digest}")
    end)

    IO.puts("isolated consumer lock: sha256=#{digest(Path.join(consumer, "mix.lock"))}")
    IO.puts("archive/reference vectors: WBA-A01..WBA-A04")
    IO.puts("live Wotex source/code paths in isolated consumer: none")
    IO.puts("application callbacks in exact Wotex archives: none")
  end

  defp revision(repository) do
    {output, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repository, stderr_to_stdout: true)
    String.trim(output)
  end

  defp release_environment do
    [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "dev"},
      {"ERL_LIBS", nil},
      {"MIX_PATH", nil}
    ]
  end

  defp isolated_environment do
    [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "test"},
      {"ERL_LIBS", nil},
      {"MIX_PATH", nil},
      {"MIX_BUILD_PATH", nil},
      {"MIX_DEPS_PATH", nil}
    ]
  end

  defp run!(command, arguments, directory, environment \\ []) do
    options = [cd: directory, env: environment, into: IO.stream(), stderr_to_stdout: true]
    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed")
    end
  end

  defp digest(path) do
    :sha256
    |> :crypto.hash(File.read!(path))
    |> Base.encode16(case: :lower)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp cleanup(work) do
    if String.starts_with?(work, Path.join(System.tmp_dir!(), @prefix)) do
      File.rm_rf!(work)
    else
      IO.puts(:stderr, "refusing unsafe archive-check cleanup")
      System.halt(1)
    end
  end

  defp violation(message), do: throw({:violation, message})
  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.BACnet.Check.Archive.main()
