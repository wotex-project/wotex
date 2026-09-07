# Verifies the Hex archive contents and out-of-tree compilation using Elixir only.
#
#     mix run --no-start bin/check_archive.exs

defmodule CheckArchive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged ["mix.exs", "LICENSE", "NOTICE", "README.md", "CHANGELOG.md", "lib", "priv", "docs"]
  @development [".git", "deps", "_build"]
  @local_tasks "docs/tasks/local"
  @dependency_root "_build/test/lib"

  def run do
    version = Mix.Project.config()[:version]
    archive = "wotex_conformance-#{version}.tar"

    unless File.regular?(archive) do
      halt("expected current wotex_conformance archive: #{archive}")
    end

    temporary = temporary_directory()

    try do
      verify(archive, temporary)
    after
      File.rm_rf(temporary)
    end
  end

  defp verify(archive, temporary) do
    extract(temporary, archive, temporary, [])

    Enum.each(@outer, fn outer ->
      unless File.regular?(Path.join(temporary, outer)) do
        fail(temporary, "archive is missing #{outer}")
      end
    end)

    package = Path.join(temporary, "package")
    File.mkdir!(package)
    extract(temporary, Path.join(temporary, "contents.tar.gz"), package, [:compressed])

    Enum.each(@packaged, fn packaged ->
      unless File.exists?(Path.join(package, packaged)) do
        fail(temporary, "package contents are missing #{packaged}")
      end
    end)

    if File.exists?(Path.join(package, @local_tasks)) do
      fail(temporary, "archive contains local task state")
    end

    unless development_state(package) == [] do
      fail(temporary, "archive contains development state")
    end

    if File.exists?(Path.join(package, "priv/plts")) do
      fail(temporary, "archive contains local Dialyzer state")
    end

    run!(temporary, "elixir", ["bin/check_boundary.exs", package])

    dependency = Path.join(@dependency_root, "jason/ebin")

    unless File.dir?(dependency) do
      fail(temporary, "compiled jason dependency is missing; run the test compile first")
    end

    ebin = Path.join(temporary, "ebin")
    File.mkdir!(ebin)
    sources = Enum.sort(Path.wildcard(Path.join(package, "lib/**/*.ex")))
    run!(temporary, "elixirc", ["--warnings-as-errors", "-pa", dependency, "-o", ebin] ++ sources)

    unless File.regular?(Path.join(ebin, "Elixir.Wotex.Conformance.beam")) do
      fail(temporary, "out-of-tree archive compilation did not produce Wotex.Conformance")
    end

    digest = :sha256 |> :crypto.hash(File.read!(archive)) |> Base.encode16(case: :lower)

    IO.puts("archive contents passed")
    IO.puts("out-of-tree archive compilation passed")
    IO.puts("archive sha256: #{digest}")
  end

  defp development_state(root) do
    root
    |> directories()
    |> Enum.filter(&(Path.basename(&1) in @development))
  end

  defp directories(root) do
    root
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn entry ->
      path = Path.join(root, entry)

      case File.lstat(path) do
        {:ok, %File.Stat{type: :directory}} -> [path | directories(path)]
        _other -> []
      end
    end)
  end

  defp extract(temporary, archive, directory, options) do
    case :erl_tar.extract(to_charlist(archive), options ++ [{:cwd, to_charlist(directory)}]) do
      :ok -> :ok
      {:error, reason} -> fail(temporary, "cannot extract #{archive}: #{inspect(reason)}")
    end
  end

  defp run!(temporary, command, arguments) do
    {_output, status} = System.cmd(command, arguments, into: IO.stream(), stderr_to_stdout: true)

    unless status == 0 do
      fail(temporary, "#{command} failed with status #{status}")
    end
  end

  defp temporary_directory do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    directory = Path.join(System.tmp_dir!(), "wotex-conformance-archive-#{suffix}")
    File.mkdir_p!(directory)
    directory
  end

  defp fail(temporary, message) do
    File.rm_rf(temporary)
    halt(message)
  end

  defp halt(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

CheckArchive.run()
