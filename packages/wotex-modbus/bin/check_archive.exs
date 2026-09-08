defmodule Wotex.Modbus.Check.Archive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged ["mix.exs", "LICENSE", "NOTICE", "README.md", "lib", "docs"]
  @development [".git", "deps", "_build"]
  @dependencies ["wotex", "wotex_runtime", "jason", "telemetry"]
  @transport "Elixir.Wotex.Modbus.Error.beam"

  @identities [
    ~r/\{:wotex, "~> 0\.1\.0"\}/,
    ~r/\{:wotex_runtime, "~> 0\.1\.0"\}/
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    archive = "wotex_modbus-#{Mix.Project.config()[:version]}.tar"
    temporary = Path.join(System.tmp_dir!(), "wotex-modbus-archive.#{unique()}")

    result =
      try do
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
      violation("expected current wotex_modbus archive: #{archive}")
    end

    package = Path.join(temporary, "package")
    ebin = Path.join(temporary, "ebin")

    File.mkdir_p!(temporary)
    extract!(archive, temporary, [])

    Enum.each(@outer, &outer!(temporary, &1))

    File.mkdir_p!(package)
    extract!(Path.join(temporary, "contents.tar.gz"), package, [:compressed])

    Enum.each(@packaged, &packaged!(package, &1))

    development!(package)
    identities!(package)

    dependencies!(project_root)

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

  defp development!(package) do
    directories =
      package
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&(File.dir?(&1) and Path.basename(&1) in @development))

    unless directories == [] do
      violation("archive contains development state")
    end
  end

  defp identities!(package) do
    manifest = File.read!(Path.join(package, "mix.exs"))

    unless Enum.all?(@identities, &Regex.match?(&1, manifest)) do
      violation("archive does not preserve normal Hex dependency identity")
    end
  end

  defp dependencies!(project_root) do
    Enum.each(@dependencies, fn dependency ->
      path = Path.join([project_root, "_build/test/lib", dependency, "ebin"])

      unless File.dir?(path) do
        violation("compiled dependency is missing; run the test compile before the archive check")
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
        ["-pa", Path.join([project_root, "_build/test/lib", dependency, "ebin"])]
      end)

    run!("elixirc", ["--warnings-as-errors"] ++ load ++ ["-o", ebin] ++ sources, project_root)
  end

  defp digest(archive) do
    :sha256
    |> :crypto.hash(File.read!(archive))
    |> Base.encode16(case: :lower)
  end

  defp run!(command, arguments, directory) do
    options = [cd: directory, into: IO.stream(), stderr_to_stdout: true]
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

Wotex.Modbus.Check.Archive.main()
