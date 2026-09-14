defmodule Wotex.Binding.MQTT.Check.Archive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged ["mix.exs", "LICENSE", "NOTICE", "README.md", "lib", "docs"]
  @development [
    ".check.exs",
    ".claude",
    ".credo.exs",
    ".doctor.exs",
    ".git",
    ".github",
    ".gitignore",
    ".tool-versions",
    "AGENTS.md",
    "CLAUDE.md",
    "_build",
    "bin",
    "config",
    "cover",
    "coveralls.json",
    "deps",
    "doc",
    "docs/tasks",
    "mix.lock",
    "priv",
    "test"
  ]
  @dependencies ["wotex", "wotex_runtime", "jason"]
  @transport "Elixir.Wotex.Binding.MQTT.Transport.beam"

  @identities [
    ~r/\{:wotex, "~> 0\.1\.0"\}/,
    ~r/\{:wotex_runtime, "~> 0\.1\.0"\}/
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    temporary = Path.join(System.tmp_dir!(), "wotex-binding-mqtt-archive.#{unique()}")
    archive = Path.join(temporary, "wotex_binding_mqtt-#{Mix.Project.config()[:version]}.tar")

    result =
      try do
        File.mkdir_p!(temporary)
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
    run!("mix", ["hex.build", "--output", archive], project_root, [
      {"MIX_ENV", "dev"},
      {"WOTEX_PATH_DEPS", nil}
    ])

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

    boundary!(project_root, package)
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
    Enum.each(@development, fn entry ->
      if File.exists?(Path.join(package, entry)) do
        violation("archive contains development input: #{entry}")
      end
    end)
  end

  defp identities!(package) do
    manifest = File.read!(Path.join(package, "mix.exs"))

    unless Enum.all?(@identities, &Regex.match?(&1, manifest)) do
      violation("archive does not preserve normal Hex dependency identity")
    end
  end

  defp boundary!(project_root, package) do
    script = Path.join(project_root, "bin/check_boundary.exs")
    run!("elixir", [script, package], project_root)
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

  defp run!(command, arguments, directory, overrides \\ []) do
    environment =
      %{"ERL_LIBS" => "", "MIX_PATH" => "", "WOTEX_PATH_DEPS" => nil}
      |> Map.merge(Map.new(overrides))
      |> Map.to_list()

    options = [cd: directory, env: environment, into: IO.stream(), stderr_to_stdout: true]
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

Wotex.Binding.MQTT.Check.Archive.main()
