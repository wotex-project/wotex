# Builds the Hex archive without sibling path dependencies and verifies
# that it ships code, README.md, usage-rules.md, CHANGELOG.md, LICENSE and
# NOTICE only.
# Runs in the full gate: `mix run --no-start bin/check_archive.exs`.

defmodule Wotex.Routines.Check.Archive do
  @moduledoc false

  @required ~w(mix.exs README.md usage-rules.md CHANGELOG.md LICENSE NOTICE)
  @forbidden ~w(docs test bin config .check.exs .credo.exs .doctor.exs coveralls.json .agents .claude .codex AGENTS.md CLAUDE.md)

  @spec main() :: :ok
  def main do
    {opts, rest, invalid} = OptionParser.parse(System.argv(), strict: [occurrence_archive: :string])
    if rest != [] or invalid != [], do: throw({:archive, "unsupported archive arguments"})
    version = Mix.Project.config()[:version]
    suffix = Integer.to_string(System.unique_integer([:positive]))
    temporary = Path.join(System.tmp_dir!(), "wotex_routines-archive-" <> suffix)
    File.mkdir_p!(temporary)
    archive = Path.join(temporary, "wotex_routines-#{version}.tar")

    result =
      try do
        build!(archive)
        verify!(files(archive, temporary))
        maybe_consumer!(opts[:occurrence_archive], archive, temporary)
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

  defp maybe_consumer!(nil, _, _), do: :ok

  defp maybe_consumer!(producer, archive, temporary) do
    producer = Path.expand(producer)
    unless File.regular?(producer), do: throw({:archive, "missing supplied producer archive"})
    artifacts = Path.join(temporary, "artifacts")
    File.mkdir_p!(artifacts)

    roots = [
      {:wotex_routines, archive},
      {:wotex, build_sibling!("wotex", temporary)},
      {:wotex_continuum, build_sibling!("wotex-continuum", temporary)},
      {:ex_booking, producer}
    ]

    paths =
      Enum.map(roots, fn {app, archive} ->
        destination = Path.join(artifacts, Atom.to_string(app))
        unpack!(archive, destination)
        IO.puts("#{app} archive sha256: #{sha256(archive)}")
        {app, destination}
      end)

    consumer = Path.join(temporary, "consumer")
    test_root = Path.join(consumer, "test")
    File.mkdir_p!(test_root)

    dependencies =
      Enum.map(paths, fn {app, path} ->
        {app, [path: path, env: :prod, override: true]}
      end)

    File.write!(Path.join(consumer, "mix.exs"), consumer_project(dependencies))
    File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")
    source = Path.expand("../test/support/archive/calendar_consumer.exs", __DIR__)
    File.cp!(source, Path.join(test_root, "calendar_consumer_test.exs"))

    environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "test"},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil},
      {"WOTEX_ROUTINES_CONSUMER_ROOT", consumer},
      {"WOTEX_ROUTINES_PRODUCER_BASIS", "sha256:" <> sha256(producer)},
      {"WOTEX_ROUTINES_COMPILER_BASIS", "sha256:" <> sha256(archive)}
    ]

    run!(["deps.get"], consumer, environment)
    run!(["compile", "--warnings-as-errors"], consumer, environment)
    run!(["test", "--warnings-as-errors"], consumer, environment)
    IO.puts("consumer lock sha256: #{sha256(Path.join(consumer, "mix.lock"))}")
  end

  defp build_sibling!(name, temporary) do
    root = Path.expand("../../#{name}", __DIR__)
    archive = Path.join(temporary, name <> ".tar")
    run!(["hex.build", "--output", archive], root, [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}])
    archive
  end

  defp consumer_project(dependencies) do
    """
    defmodule OccurrenceArchiveConsumer.MixProject do
      use Mix.Project
      def project, do: [app: :occurrence_archive_consumer, version: "0.0.0",
        elixir: "~> 1.18", deps: #{inspect(dependencies, limit: :infinity)}]
      def application, do: [extra_applications: []]
    end
    """
  end

  defp unpack!(archive, destination) do
    File.mkdir_p!(destination)
    {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    {_, contents} = Enum.find(outer, fn {name, _} -> to_string(name) == "contents.tar.gz" end)
    {:ok, members} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])

    Enum.each(members, fn {name, bytes} ->
      name = to_string(name)
      parts = Path.split(name)

      if Path.type(name) != :relative or ".." in parts,
        do: throw({:archive, "unsafe archive member"})

      path = Path.join(destination, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
    end)
  end

  defp run!(arguments, directory, environment) do
    {output, status} =
      System.cmd("mix", arguments, cd: directory, env: environment, stderr_to_stdout: true)

    IO.write(output)
    if status != 0, do: throw({:archive, "consumer/build command failed with #{status}"})
    :ok
  end

  defp build!(archive) do
    {output, status} =
      System.cmd("mix", ["hex.build", "--output", archive],
        env: [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}],
        stderr_to_stdout: true
      )

    IO.write(output)
    if status != 0, do: throw({:archive, "mix hex.build exited with #{status}"})
  end

  defp files(archive, temporary) do
    :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(temporary))
    contents = String.to_charlist(Path.join(temporary, "contents.tar.gz"))
    {:ok, entries} = :erl_tar.table(contents, [:compressed])
    Enum.map(entries, &to_string/1)
  end

  defp verify!(files) do
    missing = Enum.reject(@required, &(&1 in files))
    shipped = Enum.filter(files, &forbidden?/1)
    if missing != [], do: throw({:archive, "archive lacks " <> Enum.join(missing, ", ")})
    if shipped != [], do: throw({:archive, "archive ships " <> Enum.join(shipped, ", ")})
    :ok
  end

  defp forbidden?(file) do
    Enum.any?(@forbidden, &(file == &1 or String.starts_with?(file, &1 <> "/")))
  end

  defp sha256(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
end

Wotex.Routines.Check.Archive.main()
