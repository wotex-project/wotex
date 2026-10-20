defmodule Wotex.OPCUA.Check.Archive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  # The files the native build hashes are derived from the build itself; see
  # native_build!/1.
  @packaged [
    "mix.exs",
    "CHANGELOG.md",
    "LICENSE",
    "NOTICE",
    "README.md",
    "usage-rules.md",
    "lib",
    "priv/fixtures/contract-v1.json",
    "priv/fixtures/wotex-integration-v1.json",
    "priv/fixtures/native-json-v1.json",
    "priv/fixtures/native-ready-v1.json",
    "priv/fixtures/custody-contract-v1.json"
  ]
  @development ~r{(^|/)(\.check\.exs|\.agents|\.claude|\.codex|\.credo\.exs|\.doctor\.exs|\.git|\.github|\.tool-versions|AGENTS\.md|CLAUDE\.md|CODE_OF_CONDUCT\.md|CONTRIBUTING\.md|GOVERNANCE\.md|SECURITY\.md|bin|cover|coveralls\.json|deps|doc|docs|mix\.lock|priv/plts|test|_build)(/|$)|^tasks(/|$)}
  @dependencies ["wotex", "wotex_runtime", "jason", "telemetry"]
  @transport "Elixir.Wotex.OPCUA.Error.beam"

  @identities [
    ~r/\{:wotex, "~> 0\.1\.0"\}/,
    ~r/\{:wotex_runtime, "~> 0\.1\.0"\}/
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    temporary = Path.join(System.tmp_dir!(), "wotex-opcua-archive.#{unique()}")
    archive = Path.join(temporary, "wotex_opcua-#{Mix.Project.config()[:version]}.tar")

    result =
      try do
        File.mkdir_p!(temporary)

        run!("mix", ["hex.build", "--output", archive], project_root,
          env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "dev"}]
        )

        verify(project_root, archive, temporary)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(temporary)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp verify(project_root, archive, temporary) do
    unless File.regular?(archive) do
      violation("expected current wotex_opcua archive: #{archive}")
    end

    package = Path.join(temporary, "package")
    ebin = Path.join(temporary, "ebin")

    File.mkdir_p!(temporary)
    extract!(archive, temporary, [])

    Enum.each(@outer, &outer!(temporary, &1))

    File.mkdir_p!(package)
    extract!(Path.join(temporary, "contents.tar.gz"), package, [:compressed])

    Enum.each(@packaged, &packaged!(package, &1))
    native_build!(package)

    development!(package)
    identities!(package)

    dependencies!()

    File.mkdir_p!(ebin)
    compile!(project_root, package, ebin)

    unless File.regular?(Path.join(ebin, @transport)) do
      violation("out-of-tree archive compilation did not produce the transport")
    end

    IO.puts("archive contents passed")
    IO.puts("out-of-tree archive compilation passed")
    IO.puts("archive sha256: #{digest(archive)}")

    :ok
  end

  defp extract!(archive, directory, options) do
    case :erl_tar.extract(String.to_charlist(archive), [{:cwd, directory} | options]) do
      :ok -> :ok
      {:error, reason} -> violation("cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp outer!(temporary, entry) do
    unless File.regular?(Path.join(temporary, entry)) do
      violation("archive is missing #{entry}")
    end
  end

  defp packaged!(package, entry) do
    unless File.exists?(Path.join(package, entry)) do
      violation("package contents are missing #{entry}")
    end
  end

  # The packaged `mix wotex.opcua.native.build` hashes these files into its
  # build identity and fails when one is missing; a file under `priv/native/`
  # outside that set could reach the build without being identified. The
  # archive therefore carries exactly the hashed set.
  defp native_build!(package) do
    inputs = Wotex.OPCUA.Native.Build.inputs()
    Enum.each(inputs, &packaged!(package, &1))

    expected = Enum.filter(inputs, &String.starts_with?(&1, "priv/native/"))

    shipped =
      package
      |> Path.join("priv/native/**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, package))
      |> Enum.sort()

    unless shipped == expected do
      violation(
        "archive priv/native differs from the native build inputs; " <>
          "unhashed: #{inspect(shipped -- expected)}, missing: #{inspect(expected -- shipped)}"
      )
    end
  end

  defp development!(package) do
    entries =
      package
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.map(&Path.relative_to(&1, package))
      |> Enum.filter(&Regex.match?(@development, &1))

    unless entries == [] do
      violation("archive contains development or agent state")
    end
  end

  defp identities!(package) do
    manifest = File.read!(Path.join(package, "mix.exs"))

    unless Enum.all?(@identities, &Regex.match?(&1, manifest)) do
      violation("archive does not preserve normal Hex dependency identity")
    end
  end

  defp dependencies! do
    Enum.each(@dependencies, fn dependency ->
      path = dependency_path(dependency)

      unless File.dir?(path) do
        violation("compiled dependency is missing from the selected Mix build")
      end
    end)
  end

  defp compile!(project_root, package, ebin) do
    sources =
      package
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    load =
      Enum.flat_map(@dependencies, fn dependency ->
        ["-pa", dependency_path(dependency)]
      end)

    run!("elixirc", ["--warnings-as-errors"] ++ load ++ ["-o", ebin] ++ sources, project_root)
  end

  defp dependency_path(dependency),
    do: Path.join([Mix.Project.build_path(), "lib", dependency, "ebin"])

  defp digest(archive) do
    :sha256
    |> :crypto.hash(File.read!(archive))
    |> Base.encode16(case: :lower)
  end

  defp run!(command, arguments, directory, extra \\ []) do
    options = [cd: directory, into: IO.stream(), stderr_to_stdout: true] ++ extra
    {_output, status} = System.cmd(command, arguments, options)

    unless status == 0 do
      violation("#{command} #{Enum.join(arguments, " ")} failed")
    end
  end

  defp violation(message), do: throw({:violation, message})

  defp report(:ok), do: :ok

  defp report({:violation, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.OPCUA.Check.Archive.main()
