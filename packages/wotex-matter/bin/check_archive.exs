defmodule Wotex.Matter.Check.Archive do
  @moduledoc false

  @outer ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @packaged [
    "mix.exs",
    # The shipped software run copies the lock into its dependency bootstrap.
    "mix.lock",
    "CHANGELOG.md",
    "LICENSE",
    "NOTICE",
    "README.md",
    "usage-rules.md",
    "lib",
    "native/src/host.cpp",
    "native/include/wotex_matter/bridge_storage.hpp",
    "native/src/bridge_storage.cpp",
    "native/testing/sdk_bridge_storage_test.cpp",
    "native/include/wotex_matter/bridge_server.hpp",
    "native/include/wotex_matter/bridge_control.hpp",
    "native/include/wotex_matter/bridge_observation.hpp",
    "native/src/bridge_observation.cpp",
    "native/testing/bridge_observation_test.cpp",
    "native/include/wotex_matter/bridge_credentials.hpp",
    "native/src/bridge_credentials.cpp",
    "native/include/wotex_matter/bridge_private_file.hpp",
    "native/include/wotex_matter/bridge_commissioning_input.hpp",
    "native/src/bridge_private_file.cpp",
    "native/include/wotex_matter/bridge_configuration.hpp",
    "native/src/bridge_configuration.cpp",
    "native/testing/bridge_configuration_test.cpp",
    "native/include/wotex_matter/bridge_bootstrap.hpp",
    "native/src/bridge_bootstrap.cpp",
    "native/src/bridge_logging.cpp",
    "native/testing/bridge_bootstrap_test.cpp",
    "native/include/wotex_matter/bridge_sdk_bootstrap.hpp",
    "native/include/wotex_matter/bridge_device_info.hpp",
    "native/include/wotex_matter/bridge_ethernet.hpp",
    "native/testing/sdk_bridge_bootstrap_test.cpp",
    "native/testing/bridge_sdk_bootstrap_fixture.hpp",
    "test/native/bridge_private_file_test.cpp",
    "test/native/bridge_private_file_fault_test.cpp",
    "test/native/bridge_commissioning_input_test.cpp",
    "native/testing/sdk_bridge_credentials_test.cpp",
    "native/testing/sdk_bridge_credentials_test.hpp",
    "native/include/wotex_matter/bridge_handoff.hpp",
    "native/include/wotex_matter/bridge_handoff_owner.hpp",
    "native/include/wotex_matter/bridge_input.hpp",
    "native/src/bridge_input.cpp",
    "test/native/bridge_input_test.cpp",
    "native/include/wotex_matter/bridge_output.hpp",
    "native/src/bridge_output.cpp",
    "test/native/bridge_output_test.cpp",
    "native/include/wotex_matter/bridge_requests.hpp",
    "native/include/wotex_matter/bridge_request_frame.hpp",
    "native/src/bridge_request_frame.cpp",
    "native/testing/bridge_request_frame_test.cpp",
    "native/src/bridge_requests.cpp",
    "native/include/wotex_matter/bridge_guard.hpp",
    "native/src/bridge_guard.cpp",
    "native/testing/sdk_bridge_guard_test.cpp",
    "native/testing/sdk_bridge_guard_test.hpp",
    "native/testing/sdk_bridge_fixture_guard.hpp",
    "native/include/wotex_matter/bridge_writes.hpp",
    "native/src/bridge_writes.cpp",
    "native/include/wotex_matter/bridge_replies.hpp",
    "native/include/wotex_matter/bridge_provider.hpp",
    "native/src/bridge_replies.cpp",
    "native/src/bridge_handoff.cpp",
    "native/src/bridge_handoff_owner.cpp",
    "test/native/bridge_handoff_test.cpp",
    "test/native/bridge_handoff_owner_test.cpp",
    "native/include/wotex_matter/bridge_resources.hpp",
    "native/include/wotex_matter/bridge_endpoint_model.hpp",
    "native/include/wotex_matter/bridge_endpoints.hpp",
    "native/src/bridge_endpoint_model.cpp",
    "native/src/bridge_endpoints.cpp",
    "native/src/bridge_resources.cpp",
    "native/src/bridge_server.cpp",
    "native/testing/sdk_bridge_server_test.cpp",
    "native/testing/sdk_bridge_endpoints_test.cpp",
    "native/testing/sdk_bridge_endpoints_test.hpp",
    "native/testing/sdk_bridge_requests_test.cpp",
    "native/testing/sdk_bridge_requests_test.hpp",
    "native/testing/sdk_bridge_replies_test.cpp",
    "native/testing/sdk_bridge_replies_test.hpp",
    "native/testing/sdk_bridge_provider_test.cpp",
    "native/testing/sdk_bridge_provider_test.hpp",
    "native/testing/sdk_bridge_wait_test.cpp",
    "native/testing/sdk_bridge_wait_test.hpp",
    "native/testing/sdk_bridge_writes_test.cpp",
    "native/testing/sdk_bridge_writes_test.hpp",
    "priv/fixtures/contract-v1.json",
    "priv/fixtures/native-port-v1.json",
    "priv/fixtures/wotex-integration-v1.json",
    "test/native/interaction_test.cpp",
    "test/native/bridge_storage_test.cpp",
    "test/support/software/build.exs",
    "test/support/software/bridge_model.exs",
    "test/support/software/bridge_build.exs",
    "test/support/software/bridge-model.json",
    "test/support/software/bridge-model-zap.json",
    "test/support/software/sources.json",
    "test/support/software/acceptance.json",
    "test/support/software/acceptance.exs",
    "test/support/software/case_formatter.exs",
    "test/support/software/peer.exs",
    "test/test_helper.exs",
    "test/support/runtime_credentials.ex"
  ]
  @development [".git", "deps", "_build", "doc", "cover", "__pycache__"]
  @excluded ~r{(^|/)(\.check\.exs|\.agents|\.claude|\.codex|\.credo\.exs|AGENTS\.md|CLAUDE\.md|CODE_OF_CONDUCT\.md|CONTRIBUTING\.md|GOVERNANCE\.md|SECURITY\.md|bin|coveralls\.json|docs)(/|$)|^tasks(/|$)}
  @dependencies ["wotex", "wotex_runtime", "jason", "telemetry"]
  @transport "Elixir.Wotex.Matter.Error.beam"

  @identities [
    ~r/\{:wotex, "~> 0\.1\.0"\}/,
    ~r/\{:wotex_runtime, "~> 0\.1\.0"\}/
  ]

  @spec main() :: :ok
  def main do
    project_root = File.cwd!()
    temporary = Path.join(System.tmp_dir!(), "wotex-matter-archive.#{unique()}")
    archive = Path.join(temporary, "wotex_matter-#{Mix.Project.config()[:version]}.tar")

    result =
      try do
        # The exact archive is built once into the disposable directory with the
        # normal Hex dependency identity, never from sibling path checkouts.
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
      violation("expected current wotex_matter archive: #{archive}")
    end

    package = Path.join(temporary, "package")
    ebin = Path.join(temporary, "ebin")

    File.mkdir_p!(temporary)
    extract!(archive, temporary, [])

    Enum.each(@outer, &outer!(temporary, &1))

    File.mkdir_p!(package)
    extract!(Path.join(temporary, "contents.tar.gz"), package, [:compressed])

    Enum.each(@packaged, &packaged!(package, &1))
    acceptance!(package)

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

  defp development!(package) do
    directories =
      package
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&(File.dir?(&1) and Path.basename(&1) in @development))

    unless directories == [] do
      violation("archive contains development state")
    end

    excluded =
      package
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.map(&Path.relative_to(&1, package))
      |> Enum.filter(&Regex.match?(@excluded, &1))

    unless excluded == [] do
      violation("archive contains documentation, governance or development files")
    end
  end

  defp acceptance!(package) do
    inventory =
      package
      |> Path.join("test/support/software/acceptance.json")
      |> File.read!()
      |> Jason.decode!()

    unless inventory["schema"] == "wotex.matter.software-cases@1" and
             is_list(inventory["cases"]) and inventory["cases"] != [],
           do: violation("archive has no required software case inventory")

    for item <- inventory["cases"], do: packaged!(package, Map.fetch!(item, "file"))
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

Wotex.Matter.Check.Archive.main()
