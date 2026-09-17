defmodule Wotex.BLE.Check.Archive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged [
    "mix.exs",
    "LICENSE",
    "NOTICE",
    "README.md",
    "lib",
    "docs",
    "priv/bluez/native/frame.hpp",
    "priv/bluez/native/bytes.hpp",
    "priv/bluez/native/agent.hpp",
    "priv/bluez/native/failure.hpp",
    "priv/bluez/native/pairing.hpp",
    "priv/bluez/native/address.hpp",
    "priv/bluez/native/procedures.hpp",
    "priv/bluez/native/notify_value.hpp",
    "priv/bluez/native/notifications.hpp",
    "priv/bluez/native/output.hpp",
    "priv/bluez/native/reports.hpp",
    "priv/bluez/native/report_queue.hpp",
    "priv/bluez/native/error_value.hpp",
    "priv/bluez/native/custody.c",
    "priv/bluez/native/build_command.c",
    "priv/bluez/native/runtime-guardian.md",
    "priv/bluez/native/credit.hpp",
    "priv/bluez/native/bus.hpp",
    "priv/bluez/native/service.hpp",
    "priv/bluez/native/objects.hpp",
    "priv/bluez/native/discovery.hpp",
    "priv/bluez/native/vendor/json.hpp",
    "priv/bluez/native/vendor/LICENSE.MIT"
  ]
  @development [".git", "deps", "_build"]
  @dependencies ["wotex", "wotex_runtime", "jason", "telemetry"]
  @transport "Elixir.Wotex.BLE.Error.beam"

  @identities [
    ~r/\{:wotex, "~> 0\.1\.0"\}/,
    ~r/\{:wotex_runtime, "~> 0\.1\.0"\}/
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    temporary = Path.join(System.tmp_dir!(), "wotex-ble-archive.#{unique()}")
    archive = Path.join(temporary, "wotex_ble-#{Mix.Project.config()[:version]}.tar")

    File.mkdir!(temporary)

    result =
      try do
        run!("mix", ["hex.build", "--output", archive], project_root,
          env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}]
        )

        verify(project_root, archive, temporary)
      catch
        :throw, {:violation, message} -> {:violation, message}
      after
        File.rm_rf!(Path.join(temporary, "package"))
        File.rm_rf!(Path.join(temporary, "ebin"))
      end

    report(result)
  end

  defp unique, do: "#{System.pid()}-#{System.unique_integer([:positive])}"

  defp verify(project_root, archive, temporary) do
    unless File.regular?(archive) do
      violation("expected current wotex_ble archive: #{archive}")
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
    interpreters!(package)
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
    IO.puts("archive artifacts: #{temporary}")

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

  # WBL-B01: the production package carries no interpreter program or pin.
  defp interpreters!(package) do
    files =
      package
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&(Path.extname(&1) == ".py" or Path.basename(&1) == "requirements.txt"))

    unless files == [] do
      violation("archive contains Python runtime files")
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

Wotex.BLE.Check.Archive.main()
