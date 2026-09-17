# Archive-consumer gate: a fresh, unrelated Mix application resolves the base
# Lab profile from admitted archives only, with Git absent from the executable
# PATH, and runs Thing Description and Nx positive and negative cases through
# public APIs. Runs through Mix: `mix run --no-start bin/check_archive_consumer.exs`.

Code.require_file("support/work_directory.exs", __DIR__)
Code.require_file("support/archive_repository.exs", __DIR__)

defmodule Wotex.Lab.Check.ArchiveConsumer do
  @moduledoc false

  alias Wotex.Lab.Evidence.{Digest, Record}
  alias Wotex.Lab.Check.ArchiveRepository

  @base_packages [{:wotex, "wotex"}, {:wotex_nx, "wotex-nx"}, {:wotex_lab, "wotex-lab"}]
  @profile_packages ~w(wotex_runtime wotex_directory wotex_binding_http wotex_binding_mqtt wotex_conformance wotex_continuum exqlite req emqtt axon polaris exla fine xla explorer aws_signature table table_rex kino kino_explorer)a
  @cohort ~w(lib/**/* priv/fixtures/**/* priv/provenance/**/*
             bin/check_archive_consumer.exs bin/support/archive_repository.exs
             bin/support/work_directory.exs mix.exs mix.lock)
  @deadline_ms 900_000

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)

    work = Wotex.Lab.Check.WorkDirectory.create!(root, :archive_consumer)
    tarballs = Path.join(work, "tarballs")
    File.mkdir!(tarballs)
    started = System.monotonic_time()

    local = ArchiveRepository.build_archives!(root, @base_packages, tarballs)
    local_names = MapSet.new(local, & &1.name)

    admitted =
      local ++
        ArchiveRepository.copy_public_archives!(
          [Path.join(root, "mix.lock")],
          tarballs,
          local_names
        )

    IO.puts("admitted archives: #{length(admitted)}")

    public = ArchiveRepository.build_registry!(work, tarballs)
    {httpd, port} = ArchiveRepository.serve!(work, public)

    try do
      consumer = write_consumer(work)
      bin = ArchiveRepository.restricted_path!(work)
      env = ArchiveRepository.environment(work, port, bin)

      run!(consumer, env, ["deps.get"], "dependency resolution")
      resolved = inspect_graph(consumer, admitted)
      compiled = run!(consumer, env, ["compile", "--warnings-as-errors"], "consumer compilation")
      apps = Regex.scan(~r/Generated (\w+) app/, compiled) |> Enum.map(&List.last/1)
      IO.puts("consumer compiled: " <> Enum.join(apps, ", "))
      checks = smoke(consumer, env)
      elapsed = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
      evidence = record(root, work, admitted, resolved, checks, elapsed)
      cleanup(work, tarballs, consumer, public)

      IO.puts(
        "archive consumer: base profile resolved from #{length(resolved)} admitted archives without Git"
      )

      IO.puts("evidence retained at #{evidence}")
    after
      :inets.stop(:httpd, httpd)
    end
  end

  defp write_consumer(work) do
    consumer = Path.join(work, "consumer")
    File.mkdir_p!(Path.join(consumer, "lib"))

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule ArchiveConsumer.MixProject do
      use Mix.Project

      def project do
        [app: :archive_consumer, version: "0.1.0", elixir: "~> 1.18", deps: deps()]
      end

      def application, do: [extra_applications: [:logger]]

      defp deps, do: [{:wotex_lab, "0.1.0"}]
    end
    """)

    File.write!(Path.join(consumer, "lib/archive_consumer.ex"), """
    defmodule ArchiveConsumer do
      @moduledoc false
      def profile, do: :base
    end
    """)

    File.write!(Path.join(consumer, "smoke.exs"), smoke_script())
    consumer
  end

  defp smoke_script do
    ~S'''
    valid = ~s({"@context":"https://www.w3.org/2022/wot/td/v1.1","id":"urn:wotex:archive:1","title":"Archive","security":["nosec_sc"],"securityDefinitions":{"nosec_sc":{"scheme":"nosec"}},"properties":{"temperature":{"type":"number","forms":[{"href":"loopback://archive/temperature"}]}}})

    checks = %{
      git_absent: System.find_executable("git") == nil,
      td_parse: match?({:ok, _}, Wotex.ThingDescription.parse(valid)),
      td_reject: match?({:error, [%{code: :schema_violation} | _]}, Wotex.ThingDescription.parse(~s({"title":"no context"}))),
      td_malformed: match?({:error, %{code: _}}, Wotex.ThingDescription.parse("{")),
      nx_run: match?({:ok, %{proposal: %Wotex.Nx.ActionProposal{}}}, Wotex.Lab.Examples.Thermal.run()),
      nx_reject:
        (fn ->
           {:ok, data_schema} = Wotex.DataSchema.new(%{"type" => "number", "minimum" => 5, "maximum" => 35})

           {:ok, schema} =
             Wotex.Nx.OutputSchema.new(
               kind: :action_proposal,
               thing_id: "urn:wotex:archive:1",
               affordance_type: :action,
               affordance_name: "setTarget",
               data_schema: data_schema,
               dtype: :f32
             )

           match?({:error, _}, Wotex.Nx.Decoder.decode(Nx.tensor(99.0, type: :f32), schema, id: "p", proposed_at: 1))
         end).(),
      profile_modules_absent:
        not Code.ensure_loaded?(Wotex.Runtime.Transport) and
          not Code.ensure_loaded?(Wotex.Lab.Adapters.Runtime.Loopback) and
          not Code.ensure_loaded?(Wotex.Lab.Adapters.Directory.EtsRepository) and
          not Code.ensure_loaded?(Wotex.Lab.SmartRoom.Scenario) and
          not Code.ensure_loaded?(Wotex.Lab.Analytics) and
          not Code.ensure_loaded?(Explorer.DataFrame) and
          not Code.ensure_loaded?(Exqlite.Sqlite3),
      base_modules_present:
        Code.ensure_loaded?(Wotex.Lab) and Code.ensure_loaded?(Wotex.Lab.Telemetry) and
          Code.ensure_loaded?(Wotex.Lab.DesignSystem) and Code.ensure_loaded?(Wotex.Nx.Encoder)
    }

    IO.puts("ARCHIVE_CONSUMER_CHECKS " <> Enum.map_join(Enum.sort(checks), ",", fn {k, v} -> "#{k}=#{v}" end))
    '''
  end

  defp run!(consumer, env, args, label) do
    ArchiveRepository.run!(consumer, env, args, label, @deadline_ms)
  end

  # The resolved graph is inspected recursively through the consumer lock: every
  # package must be an admitted archive and no profile package may appear.
  defp inspect_graph(consumer, admitted) do
    lock = ArchiveRepository.read_lock!(Path.join(consumer, "mix.lock"))
    names = Map.new(admitted, &{{&1.name, &1.version}, &1})

    Enum.map(lock, fn {name, entry} ->
      (is_tuple(entry) and elem(entry, 0) == :hex) ||
        abort("#{name} did not resolve to a Hex archive")

      version = elem(entry, 2)
      name in @profile_packages && abort("profile package #{name} entered the base closure")

      Map.has_key?(names, {Atom.to_string(name), version}) ||
        abort("#{name} #{version} is not an admitted archive")

      %{
        name: Atom.to_string(name),
        version: version,
        archive: Digest.file!(names[{Atom.to_string(name), version}].path)
      }
    end)
  end

  defp smoke(consumer, env) do
    output = run!(consumer, env, ["run", "smoke.exs"], "archive consumer smoke")

    case Regex.run(~r/ARCHIVE_CONSUMER_CHECKS (\S+)/, output) do
      [_line, checks] ->
        checks
        |> String.split(",")
        |> Map.new(fn pair ->
          [key, value] = String.split(pair, "=")
          {key, value == "true"}
        end)
        |> tap(fn map ->
          Enum.all?(map, fn {_key, ok?} -> ok? end) ||
            abort("archive consumer checks failed: #{inspect(map)}")
        end)

      nil ->
        abort("smoke produced no checks:\n#{output}")
    end
  end

  defp record(root, work, admitted, resolved, checks, elapsed) do
    {:ok, source_tree_digest} = Digest.tree(root, @cohort)
    {:ok, lock_digest} = Digest.file(Path.join(root, "mix.lock"))
    fixture = Path.join(root, "priv/fixtures/thermal/thing-description.json")
    {:ok, fixture_digest} = Digest.file(fixture)

    {:ok, record} =
      Record.new(
        scenario_id: "archive-consumer:base",
        revision: ArchiveRepository.revision(root),
        attempt: 1,
        source_tree_digest: source_tree_digest,
        lock_digest: lock_digest,
        dependencies: resolved,
        fixtures: %{"thermal/thing-description.json" => fixture_digest},
        seed: 0,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{deadline_ms: @deadline_ms},
        inputs: Enum.map(admitted, &"archive:#{&1.name}-#{&1.version}:#{&1.origin}"),
        assertions:
          Enum.map(checks, fn {key, ok?} ->
            %{id: "WLB-C10:archive-consumer:#{key}", status: if(ok?, do: :pass, else: :fail)}
          end),
        outcomes: %{profile: :base, git_on_path: false, resolved_packages: length(resolved)},
        durations: %{gate_ms: elapsed},
        cleanup: %{status: :ok, details: %{retained: "evidence.json"}}
      )

    {:ok, bytes} = Record.encode(record)
    path = Path.join(work, "evidence.json")
    File.write!(path, bytes)
    path
  end

  defp cleanup(work, tarballs, consumer, public) do
    String.contains?(work, ".archive-check.consumer-") ||
      abort("refusing unsafe archive-check cleanup")

    Enum.each(
      [tarballs, consumer, public, Path.join(work, "bin"), Path.join(work, "hex_home")],
      &File.rm_rf!/1
    )

    File.rm(Path.join(work, "registry_key.pem"))
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ArchiveConsumer.run()
