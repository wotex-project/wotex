defmodule Wotex.Runtime.Check.Package do
  @moduledoc false

  @present ["mix.exs", "README.md", "LICENSE", "NOTICE"]
  @absent ["CLAUDE.md", ".claude"]

  @beams [
    "Elixir.Wotex.Runtime.ConsumedThing.beam",
    "Elixir.Wotex.Runtime.ExposedThing.beam"
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    package_root = Path.join(System.tmp_dir!(), "wotex-runtime-package.#{unique()}")

    result =
      try do
        verify(project_root, package_root)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(package_root)
      end

    report(result)
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp verify(project_root, package_root) do
    unpacked = Path.join(package_root, "unpacked")
    ebin = Path.join(package_root, "ebin")

    build!(project_root, unpacked)

    Enum.each(@present, &present!(unpacked, &1))
    Enum.each(@absent, &absent!(unpacked, &1))

    run!("elixir", [Path.join(project_root, "bin/check_boundary.exs")], unpacked, [])

    dependencies =
      Enum.map(~w(wotex telemetry), &Path.join(project_root, "_build/test/lib/#{&1}/ebin"))

    Enum.each(dependencies, fn dependency ->
      unless File.dir?(dependency) do
        violation("compiled package dependency is missing: #{dependency}")
      end
    end)

    File.mkdir_p!(ebin)
    compile!(project_root, unpacked, ebin, dependencies)

    Enum.each(@beams, &beam!(ebin, &1))

    IO.puts("unpacked archive compiled out of tree")

    :ok
  end

  defp build!(project_root, unpacked) do
    arguments = ["hex.build", "--unpack", "--output", unpacked]
    run!("mix", arguments, project_root, [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}])
  end

  defp compile!(project_root, unpacked, ebin, dependencies) do
    sources =
      unpacked
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    code_paths = Enum.flat_map(dependencies, &["-pa", &1])
    arguments = ["--warnings-as-errors"] ++ code_paths ++ ["-o", ebin] ++ sources
    run!("elixirc", arguments, project_root, [])
  end

  defp present!(unpacked, entry) do
    unless File.regular?(Path.join(unpacked, entry)) do
      violation("packaged archive is missing #{entry}")
    end
  end

  defp absent!(unpacked, entry) do
    if File.exists?(Path.join(unpacked, entry)) do
      violation("packaged archive contains #{entry}")
    end
  end

  defp beam!(ebin, name) do
    unless File.regular?(Path.join(ebin, name)) do
      violation("out-of-tree compilation did not produce #{name}")
    end
  end

  defp run!(command, arguments, directory, environment) do
    options = [
      cd: directory,
      env: environment,
      into: IO.stream(),
      stderr_to_stdout: true
    ]

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

Wotex.Runtime.Check.Package.main()
