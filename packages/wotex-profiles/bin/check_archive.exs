# Builds the Hex archive without sibling path dependencies and verifies
# that it ships code, README.md, usage-rules.md, CHANGELOG.md, LICENSE and
# NOTICE plus the frozen offline schemas/vectors/contracts.
# Runs in the full gate: `mix run --no-start bin/check_archive.exs`.

defmodule Wotex.Profiles.Check.Archive do
  @moduledoc false

  @required ~w(mix.exs README.md usage-rules.md CHANGELOG.md LICENSE NOTICE)
  @forbidden ~w(docs test bin config .check.exs .credo.exs .doctor.exs coveralls.json .agents .claude .codex AGENTS.md CLAUDE.md)

  @spec main() :: :ok
  def main do
    version = Mix.Project.config()[:version]
    suffix = Integer.to_string(System.unique_integer([:positive]))
    temporary = Path.join(System.tmp_dir!(), "wotex_profiles-archive-" <> suffix)
    File.mkdir_p!(temporary)
    archive = Path.join(temporary, "wotex_profiles-#{version}.tar")

    result =
      try do
        build!(archive)
        verify!(files(archive, temporary), temporary)
        consumers!(temporary, archive)
        {:ok, sha256(archive)}
      catch
        :throw, {:archive, message} -> {:error, message}
      after
        File.rm_rf!(temporary)
      end

    case result do
      {:ok, digest} ->
        IO.puts("archive sha256: #{digest}")
        IO.puts("archive check passed")
        :ok

      {:error, message} ->
        IO.puts(:stderr, "archive check failed: " <> message)
        System.halt(1)
    end
  end

  defp build!(archive, directory \\ File.cwd!()) do
    {output, status} =
      System.cmd("mix", ["hex.build", "--output", archive],
        env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
        cd: directory,
        stderr_to_stdout: true
      )

    IO.write(output)
    if status != 0, do: throw({:archive, "mix hex.build exited with #{status}"})
  end

  defp files(archive, temporary) do
    :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(temporary))
    contents = String.to_charlist(Path.join(temporary, "contents.tar.gz"))
    {:ok, entries} = :erl_tar.table(contents, [:compressed])
    :ok = :erl_tar.extract(contents, [:compressed, {:cwd, String.to_charlist(temporary)}])
    Enum.map(entries, &to_string/1)
  end

  defp verify!(files, temporary) do
    missing = Enum.reject(@required, &(&1 in files))
    shipped = Enum.filter(files, &forbidden?/1)
    if missing != [], do: throw({:archive, "archive lacks " <> Enum.join(missing, ", ")})
    if shipped != [], do: throw({:archive, "archive ships " <> Enum.join(shipped, ", ")})
    unexpected = Enum.reject(files, &allowed?/1)
    if unexpected != [], do: throw({:archive, "archive has unexpected members"})

    unless Enum.all?(files, &(File.read!(&1) == File.read!(Path.join(temporary, &1)))) do
      throw({:archive, "archive member differs from selected source"})
    end

    :ok
  end

  defp allowed?(file) do
    file in (@required ++ [".formatter.exs"]) or
      Enum.any?(
        ~w(lib/ priv/schemas/ priv/vectors/ priv/contracts/),
        &String.starts_with?(file, &1)
      )
  end

  defp consumers!(temporary, archive) do
    cohort = Path.join(temporary, "cohort")
    File.mkdir_p!(cohort)

    for name <- ~w(wotex wotex-runtime wotex-profiles) do
      target = Path.join(cohort, name)
      File.mkdir_p!(target)

      selected =
        if name == "wotex-profiles",
          do: archive,
          else: Path.join(temporary, name <> ".tar")

      if name != "wotex-profiles", do: build!(selected, Path.expand("../" <> name))
      files(selected, target)
      IO.puts(name <> " selected archive sha256: " <> sha256(selected))
    end

    for family <- ~w(industrial research) do
      consumer = Path.join(temporary, family)
      File.mkdir_p!(Path.join(consumer, "test"))
      File.write!(Path.join(consumer, "mix.exs"), consumer_project(cohort, family))
      File.write!(Path.join(consumer, "test/test_helper.exs"), "ExUnit.start()\n")

      File.cp!(
        "test/support/archive_consumer.exs",
        Path.join(consumer, "test/consumer_test.exs")
      )

      for suffix <- ~w(profile definition) do
        File.cp!(
          "priv/vectors/" <> family <> "-" <> suffix <> ".json",
          Path.join(consumer, suffix <> ".json")
        )
      end

      File.cp!("priv/vectors/limits.json", Path.join(consumer, "limits.json"))

      File.write!(
        Path.join(consumer, "identities.json"),
        Jason.encode!(
          Jason.decode!(File.read!("priv/vectors/identities.json"))
          |> Map.take([family <> "-profile", family <> "-definition"])
        )
      )

      for arguments <- [["deps.get"], ["deps.get", "--check-locked"], ["test"]] do
        run_consumer!(consumer, arguments, family)
      end

      IO.puts(family <> " consumer lock sha256: " <> sha256(Path.join(consumer, "mix.lock")))
    end
  end

  defp consumer_project(cohort, family) do
    dependencies =
      for name <- ~w(wotex wotex-runtime wotex-profiles) do
        app = String.replace(name, "-", "_")
        "{:#{app}, path: #{inspect(Path.join(cohort, name))}, env: :dev, override: true}"
      end

    """
    defmodule ArchiveConsumer.MixProject do
      use Mix.Project
      def project, do: [app: :#{family}_consumer, version: "0.0.0", elixir: "~> 1.18",
        deps: [#{Enum.join(dependencies, ",")}]]
      def application, do: []
    end
    """
  end

  defp run_consumer!(directory, arguments, family) do
    {output, status} =
      System.cmd("mix", arguments,
        cd: directory,
        stderr_to_stdout: true,
        env: [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "test"}, {"PROFILE_FAMILY", family}]
      )

    IO.write(output)
    if status != 0, do: throw({:archive, "isolated consumer failed"})
  end

  defp forbidden?(file) do
    Enum.any?(@forbidden, &(file == &1 or String.starts_with?(file, &1 <> "/")))
  end

  defp sha256(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end

Wotex.Profiles.Check.Archive.main()
