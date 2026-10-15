# Builds the Hex archive without sibling path dependencies and verifies
# that it ships code, README.md, usage-rules.md, CHANGELOG.md, LICENSE and
# NOTICE only.
# Runs in the full gate: `mix run --no-start bin/check_archive.exs`.

defmodule Wotex.Routines.Check.Archive do
  @moduledoc false

  @required ~w(mix.exs README.md usage-rules.md CHANGELOG.md LICENSE NOTICE)
  @forbidden ~w(docs test bin config priv/plts .check.exs .credo.exs .doctor.exs coveralls.json .agents .claude .codex AGENTS.md CLAUDE.md)

  @spec main() :: :ok
  def main do
    {opts, rest, invalid} =
      OptionParser.parse(System.argv(),
        strict: [
          occurrence_archive: :string,
          civil_consumer: :boolean,
          composition_consumers: :boolean,
          profile_consumers: :boolean,
          model_consumer: :boolean,
          maude_path: :string
        ]
      )

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
        consumers!(opts, archive, temporary)
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

  defp consumers!(opts, archive, temporary) do
    producer = opts[:occurrence_archive]

    if opts[:civil_consumer] == true and is_nil(producer),
      do: throw({:archive, "civil consumer requires an explicit producer archive"})

    if opts[:model_consumer] == true and not is_binary(opts[:maude_path]),
      do: throw({:archive, "model consumer requires an explicit interpreter path"})

    if producer || opts[:composition_consumers] || opts[:model_consumer] || opts[:profile_consumers] do
      paths = artifacts!(producer, archive, temporary, opts[:profile_consumers])

      if producer,
        do: calendar_consumer!(producer, archive, paths, temporary, opts[:civil_consumer])

      if opts[:composition_consumers], do: composition_consumers!(archive, paths, temporary)
      if opts[:model_consumer], do: model_consumer!(archive, paths, temporary, opts[:maude_path])
      if opts[:profile_consumers], do: profile_consumers!(paths, temporary)
    end

    :ok
  end

  defp artifacts!(producer, archive, temporary, profiles) do
    if producer && not File.regular?(producer),
      do: throw({:archive, "missing supplied producer archive"})

    artifacts = Path.join(temporary, "artifacts")
    File.mkdir_p!(artifacts)

    roots = [
      {:wotex_routines, archive},
      {:wotex, build_sibling!("wotex", temporary)},
      {:wotex_continuum, build_sibling!("wotex-continuum", temporary)}
    ]

    roots = if producer, do: roots ++ [{:ex_booking, Path.expand(producer)}], else: roots

    roots =
      if profiles,
        do:
          roots ++
            [
              {:wotex_runtime, build_sibling!("wotex-runtime", temporary)},
              {:wotex_profiles, build_sibling!("wotex-profiles", temporary)}
            ],
        else: roots

    Enum.map(roots, fn {app, archive} ->
      destination = Path.join(artifacts, Atom.to_string(app))
      unpack!(archive, destination)
      IO.puts("#{app} archive sha256: #{sha256(archive)}")
      {app, destination}
    end)
  end

  defp profile_consumers!(paths, temporary) do
    for family <- ~w(industrial research absent) do
      consumer = Path.join(temporary, "consumer-profile-" <> family)
      test_root = Path.join(consumer, "test")
      File.mkdir_p!(test_root)

      selected =
        if family == "absent",
          do: Enum.reject(paths, fn {app, _} -> app in [:wotex_profiles, :wotex_runtime] end),
          else: paths

      dependencies =
        Enum.map(selected, fn {app, path} -> {app, [path: path, env: :prod, override: true]} end)

      File.write!(Path.join(consumer, "mix.exs"), consumer_project(dependencies))
      File.write!(Path.join(test_root, "test_helper.exs"), "ExUnit.start()\n")

      source =
        if family == "absent", do: "profile_absent_consumer.exs", else: "profile_consumer.exs"

      copy_fixture!(
        "test/support/archive/" <> source,
        Path.join(test_root, "profile_consumer_test.exs")
      )

      copy_fixture!("priv/vectors/wro-05-input.json", Path.join(consumer, "input.json"))

      copy_fixture!(
        "priv/vectors/wro-05-input-execution.json",
        Path.join(consumer, "input-execution.json")
      )

      environment = [
        {"WOTEX_PATH_DEPS", nil},
        {"MIX_ENV", "test"},
        {"MIX_BUILD_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"WOTEX_ROUTINES_INPUT_FAMILY", family}
      ]

      IO.puts("profile consumer: " <> family)
      run!(["deps.get"], consumer, environment)
      run!(["compile", "--warnings-as-errors"], consumer, environment)
      run!(["test", "--warnings-as-errors"], consumer, environment)

      IO.puts(
        family <> " profile consumer lock sha256: " <> sha256(Path.join(consumer, "mix.lock"))
      )

      if family != "absent", do: profile_mutations!(paths, consumer, environment, family)
    end
  end

  defp profile_mutations!(paths, consumer, environment, family) do
    script = Path.join(consumer, "profile_mutations.exs")
    copy_fixture!("test/support/archive/profile_mutation_consumer.exs", script)
    baseline = profile_mutation_run!(consumer, environment, script, "baseline")

    unless baseline.status == 0 and baseline.result["total"] == 5 and
             baseline.result["failures"] == 0,
           do: throw({:archive, "profile mutation baseline failed: " <> family})

    mutations = [
      {"profile_identity", "observation_view.ex",
       "fact[\"profile_digest\"] == expected[\"profile_digest\"] and", "true and"},
      {"signed_floor", "input.ex", "Integer.floor_div(delta, 1000)", "div(delta, 1000)"}
    ]

    for {name, filename, from, to} <- mutations do
      source =
        paths
        |> Keyword.fetch!(:wotex_routines)
        |> Path.join("lib/wotex/routines/" <> filename)
        |> File.read!()

      unless length(String.split(source, from)) == 2,
        do: throw({:archive, "profile mutation site changed: " <> name})

      replacement = Path.join(consumer, "mutant-" <> filename)
      File.write!(replacement, String.replace(source, from, to, global: false))
      result = profile_mutation_run!(consumer, environment, script, replacement)

      unless result.status == 1 and result.result["total"] == baseline.result["total"] and
               result.result["failures"] > 0 and result.assertions["assertions"] > 0 and
               result.assertions["errors"] == 0,
             do:
               throw(
                 {:archive,
                  "profile mutation survived or harness failed: " <> family <> "/" <> name}
               )

      IO.puts(
        family <> "/" <> name <> ": #{result.result["failures"]} behavioral assertion failures"
      )
    end
  end

  defp profile_mutation_run!(consumer, environment, script, replacement) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", script, replacement],
        cd: consumer,
        env: environment,
        stderr_to_stdout: true
      )

    result = profile_marker!(output, "PROFILE_RESULT=")
    assertions = profile_marker!(output, "PROFILE_ASSERTIONS=")
    %{status: status, result: result, assertions: assertions}
  end

  defp profile_marker!(output, prefix) do
    case output
         |> String.split("\n")
         |> Enum.find(&String.starts_with?(&1, prefix)) do
      nil ->
        IO.write(output)
        throw({:archive, "profile mutation process/formatter failed"})

      line ->
        line
        |> String.replace_prefix(prefix, "")
        |> JSON.decode!()
    end
  end

  defp calendar_consumer!(producer, archive, paths, temporary, civil?) do
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

    if civil? do
      copy_fixture!(
        "test/support/archive/civil_consumer.exs",
        Path.join(test_root, "civil_consumer_test.exs")
      )

      copy_fixture!("test/support/civil_fixtures.exs", Path.join(consumer, "civil_fixtures.exs"))

      File.write!(Path.join(consumer, "civil_without_start.exs"), """
      false = Enum.any?(Application.started_applications(), fn {app, _, _} -> app in [:wotex_routines, :ex_booking, :tz] end)
      priv = :wotex_routines |> :code.priv_dir() |> List.to_string()
      corpus = priv |> Path.join("vectors/wro-01.json") |> File.read!() |> JSON.decode!()
      vector = priv |> Path.join("vectors/wro-03-civil.json") |> File.read!() |> JSON.decode!()
      {:ok, limits} = Wotex.Routines.Limits.new(corpus["limits"])
      {:ok, request} = Wotex.Routines.CivilRequest.new(vector["schedule"], vector["query"], Calendar.UTCOnlyTimeZoneDatabase, limits)
      {:ok, %{occurrences: [point]}} = Wotex.Routines.Civil.page(request, vector["time"], limits)
      false = Map.has_key?(point, "ordinal")
      "2026-07-15T09:00:00Z" = point["starts_at"]
      false = Enum.any?(Application.started_applications(), fn {app, _, _} -> app in [:wotex_routines, :ex_booking, :tz] end)
      IO.puts("Civil archive query without application startup passed.")
      """)
    end

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

    if civil?,
      do:
        run!(
          ["run", "--no-start", "--no-compile", "civil_without_start.exs"],
          consumer,
          environment
        )

    run!(["test", "--warnings-as-errors"], consumer, environment)
    IO.puts("consumer lock sha256: #{sha256(Path.join(consumer, "mix.lock"))}")
  end

  defp composition_consumers!(archive, paths, temporary) do
    groups = [
      {"source-trace", ["test/wotex/routines/correspondence_test.exs"],
       ["test/support/source_truth_oracle.exs", "test/support/source_transition_oracle.exs"]},
      {"private-journal", ["test/support/archive/journal_consumer.exs"], []}
    ]

    Enum.each(groups, fn {name, tests, support} ->
      consumer = Path.join(temporary, "consumer-" <> name)
      test_root = Path.join(consumer, "test")
      File.mkdir_p!(test_root)

      dependencies =
        Enum.map(paths, fn {app, path} ->
          {app, [path: path, env: :prod, override: true]}
        end)

      File.write!(Path.join(consumer, "mix.exs"), consumer_project(dependencies))

      helper =
        Enum.map(support, fn relative ->
          support_root = Path.join(consumer, "support")
          File.mkdir_p!(support_root)
          copy_fixture!(relative, Path.join(support_root, Path.basename(relative)))
          "Code.require_file(#{inspect("../support/" <> Path.basename(relative))}, __DIR__)\n"
        end)

      File.write!(Path.join(test_root, "test_helper.exs"), ["ExUnit.start()\n" | helper])

      Enum.each(Enum.with_index(tests), fn {relative, index} ->
        copy_fixture!(relative, Path.join(test_root, "consumer_#{index}_test.exs"))
      end)

      copy_fixture!(
        "test/support/archive/identity_consumer.exs",
        Path.join(test_root, "identity_test.exs")
      )

      environment = [
        {"WOTEX_PATH_DEPS", nil},
        {"MIX_ENV", "test"},
        {"MIX_BUILD_PATH", nil},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_DEPS_PATH", nil},
        {"WOTEX_ROUTINES_CONSUMER_ROOT", consumer},
        {"WOTEX_ROUTINES_COMPILER_BASIS", "sha256:" <> sha256(archive)}
      ]

      IO.puts("composition consumer: #{name}")
      run!(["deps.get"], consumer, environment)
      run!(["compile", "--warnings-as-errors"], consumer, environment)
      run!(["test", "--warnings-as-errors"], consumer, environment)
      IO.puts("#{name} consumer lock sha256: #{sha256(Path.join(consumer, "mix.lock"))}")
    end)
  end

  defp copy_fixture!(relative, destination) do
    source = Path.expand("../" <> relative, __DIR__)
    File.cp!(source, destination)
    IO.puts("#{relative} consumer source sha256: #{sha256(source)}")
  end

  defp model_consumer!(archive, paths, temporary, maude_path) do
    consumer = Path.join(temporary, "consumer-model")
    tests = Path.join(consumer, "test")
    File.mkdir_p!(tests)

    dependencies =
      Enum.map(paths, fn {app, path} ->
        {app, [path: path, env: :prod, override: true]}
      end) ++ [{:ex_maude, "== 0.5.0"}]

    File.write!(Path.join(consumer, "mix.exs"), consumer_project(dependencies))
    File.write!(Path.join(tests, "test_helper.exs"), "ExUnit.start()\n")
    copy_fixture!("test/support/archive/model_consumer.exs", Path.join(tests, "model_test.exs"))

    copy_fixture!(
      "test/support/archive/identity_consumer.exs",
      Path.join(tests, "identity_test.exs")
    )

    environment = [
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "test"},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil},
      {"EX_MAUDE_BUILD_CNODE", "0"},
      {"WOTEX_ROUTINES_CONSUMER_ROOT", consumer},
      {"WOTEX_ROUTINES_COMPILER_BASIS", "sha256:" <> sha256(archive)},
      {"WOTEX_ROUTINES_MAUDE_PATH", Path.expand(maude_path)}
    ]

    run!(["deps.get"], consumer, environment)
    run!(["compile", "--warnings-as-errors"], consumer, environment)
    run!(["test", "--warnings-as-errors"], consumer, environment)
    IO.puts("model consumer lock sha256: #{sha256(Path.join(consumer, "mix.lock"))}")
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
