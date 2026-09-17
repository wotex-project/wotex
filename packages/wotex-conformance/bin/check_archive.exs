# Verifies the Hex archive contents and out-of-tree compilation using Elixir only.
#
#     mix run --no-start bin/check_archive.exs

defmodule CheckArchive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged ["mix.exs", "LICENSE", "NOTICE", "README.md", "CHANGELOG.md", "lib", "priv"]
  @development [".git", "deps", "_build"]
  # Markdown documentation reaches consumers through HexDocs; no `docs/` tree
  # and no task-tracker path may travel inside the archive.
  @forbidden_segments ["docs", "tasks"]
  @consumer_fixture "test/fixtures/archive_consumer.exs"
  @target_fixture "test/fixtures/external_target.exs"

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

    package
    |> entries()
    |> Enum.each(fn path ->
      relative = Path.relative_to(path, package)

      if Enum.any?(Path.split(relative), &(&1 in @forbidden_segments)) do
        fail(temporary, "archive contains documentation or task path #{relative}")
      end
    end)

    unless development_state(package) == [] do
      fail(temporary, "archive contains development state")
    end

    if File.exists?(Path.join(package, "priv/plts")) do
      fail(temporary, "archive contains local Dialyzer state")
    end

    run!(temporary, "elixir", ["bin/check_boundary.exs", package])

    dependency = dependency_ebin()

    unless File.dir?(dependency) do
      fail(temporary, "compiled jason dependency is missing; run the test compile first")
    end

    isolated_dependency = Path.join(temporary, "jason-ebin")

    case File.cp_r(dependency, isolated_dependency) do
      {:ok, _} -> :ok
      {:error, reason, _} -> fail(temporary, "cannot isolate jason dependency: #{inspect(reason)}")
    end

    ebin = Path.join(temporary, "ebin")
    File.mkdir!(ebin)
    sources = Enum.sort(Path.wildcard(Path.join(package, "lib/**/*.ex")))

    run!(
      temporary,
      "elixirc",
      ["--warnings-as-errors", "-pa", isolated_dependency, "-o", ebin] ++ sources
    )

    unless File.regular?(Path.join(ebin, "Elixir.Wotex.Conformance.beam")) do
      fail(temporary, "out-of-tree archive compilation did not produce Wotex.Conformance")
    end

    run_archive_consumer!(temporary, package, ebin, isolated_dependency)

    digest = :sha256 |> :crypto.hash(File.read!(archive)) |> Base.encode16(case: :lower)

    IO.puts("archive contents passed")
    IO.puts("out-of-tree archive compilation passed")
    IO.puts("archive-only consumer passed")
    IO.puts("archive sha256: #{digest}")
  end

  defp dependency_ebin do
    Application.app_dir(:jason, "ebin")
  end

  defp run_archive_consumer!(temporary, package, ebin, dependency) do
    consumer = isolated_fixture!(temporary, @consumer_fixture, "archive_consumer.exs")
    target = isolated_fixture!(temporary, @target_fixture, "independent_target.exs")
    subject = Path.join(temporary, "subject.tar.gz")

    :ok =
      :erl_tar.create(
        to_charlist(subject),
        [{~c"manifest.json", ~s({"interface_revision":"1","subject":"synthetic"})}],
        [:compressed]
      )

    executable = System.find_executable("elixir") || fail(temporary, "elixir executable is missing")
    erl = System.find_executable("erl") || fail(temporary, "erl executable is missing")

    arguments = [
      "-pa",
      dependency,
      "-pa",
      ebin,
      consumer,
      "--package",
      package,
      "--target",
      target,
      "--subject",
      subject,
      "--elixir",
      executable,
      "--erl",
      erl,
      "--forbid",
      File.cwd!()
    ]

    run!(temporary, executable, arguments,
      cd: temporary,
      env: isolated_environment(executable, erl)
    )
  end

  defp isolated_fixture!(temporary, source, basename) do
    source = Path.expand(source)
    destination = Path.join(temporary, basename)

    case File.cp(source, destination) do
      :ok -> destination
      {:error, reason} -> fail(temporary, "cannot isolate #{source}: #{inspect(reason)}")
    end
  end

  defp isolated_environment(executable, erl) do
    cleared =
      System.get_env()
      |> Map.drop(["ELIXIR_ERL_OPTIONS", "PATH"])
      |> Map.keys()
      |> Enum.map(&{&1, nil})

    path =
      [Path.dirname(executable), Path.dirname(erl), "/usr/bin", "/bin"]
      |> Enum.uniq()
      |> Enum.join(":")

    [{"ELIXIR_ERL_OPTIONS", "+fnu"}, {"PATH", path} | cleared]
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

  defp entries(root) do
    root
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn entry ->
      path = Path.join(root, entry)

      case File.lstat(path) do
        {:ok, %File.Stat{type: :directory}} -> [path | entries(path)]
        {:ok, _stat} -> [path]
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

  defp run!(temporary, command, arguments, options \\ []) do
    options = Keyword.merge([into: IO.stream(), stderr_to_stdout: true], options)
    {_output, status} = System.cmd(command, arguments, options)

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
