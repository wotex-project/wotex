# Archive-consumer gate: a fresh, unrelated Mix application resolves the base
# Lab profile from admitted archives only, with Git absent from the executable
# PATH, and runs Thing Description and Nx positive and negative cases through
# public APIs. Runs through Mix: `mix run --no-start bin/check_archive_consumer.exs`.

defmodule Wotex.Lab.Check.ArchiveConsumer do
  @moduledoc false

  alias Wotex.Lab.Evidence.{Digest, Record}

  @base_packages [{:wotex, "wotex"}, {:wotex_nx, "wotex-nx"}, {:wotex_lab, "wotex-lab"}]
  @profile_packages ~w(wotex_runtime wotex_directory wotex_binding_http wotex_binding_mqtt wotex_conformance wotex_continuum exqlite req emqtt)a
  @cohort ~w(lib/**/* priv/fixtures/**/* docs/specs/**/* mix.exs mix.lock)
  @deadline_ms 900_000

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)
    root |> Path.join(".archive-check.consumer-*") |> Path.wildcard() |> Enum.each(&File.rm_rf!/1)
    work = Path.join(root, ".archive-check.consumer-#{System.unique_integer([:positive])}")
    tarballs = Path.join(work, "tarballs")
    File.mkdir_p!(tarballs)
    started = System.monotonic_time()

    admitted = build_archives(root, tarballs) ++ copy_public_archives(root, tarballs)
    IO.puts("admitted archives: #{length(admitted)}")

    public = build_registry(work, tarballs)
    {httpd, port} = serve(work, public)

    try do
      consumer = write_consumer(work)
      bin = restricted_path(work)
      env = consumer_env(work, port, bin)

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

  defp build_archives(root, tarballs) do
    Enum.map(@base_packages, fn {app, directory} ->
      dir = Path.expand("../#{directory}", root)
      File.dir?(dir) || abort("missing sibling checkout for #{app} at ../#{directory}")
      env = [{"WOTEX_PATH_DEPS", nil}, {"MIX_ENV", "prod"}]

      {version, 0} =
        System.cmd(
          "mix",
          [
            "run",
            "--no-start",
            "--no-deps-check",
            "--no-compile",
            "-e",
            "IO.write(Mix.Project.config()[:version])"
          ],
          cd: dir,
          env: env,
          stderr_to_stdout: true
        )

      version = version |> String.split("\n") |> List.last() |> String.trim()

      Regex.match?(~r/\A\d+\.\d+\.\d+\z/, version) ||
        abort("cannot read #{app} version: #{version}")

      output = Path.join(tarballs, "#{app}-#{version}.tar")

      {log, status} =
        System.cmd("mix", ["hex.build", "--output", output],
          cd: dir,
          env: env,
          stderr_to_stdout: true
        )

      status == 0 || abort("hex.build failed for #{app}:\n#{log}")
      File.regular?(output) || abort("hex.build produced no archive for #{app}")
      %{name: Atom.to_string(app), version: version, path: output, origin: :built}
    end)
  end

  # Public dependencies are admitted only at the exact versions in the Lab lock,
  # from the local Hex cache; nothing is fetched from the network.
  defp copy_public_archives(root, tarballs) do
    lock = read_lock(Path.join(root, "mix.lock"))
    cache = Path.join([hex_home(), "packages", "hexpm"])

    lock
    |> Enum.flat_map(fn
      {name, entry} when is_tuple(entry) and elem(entry, 0) == :hex ->
        version = elem(entry, 2)
        file = "#{name}-#{version}.tar"
        source = Path.join(cache, file)

        if File.regular?(source) do
          target = Path.join(tarballs, file)
          File.cp!(source, target)
          [%{name: Atom.to_string(name), version: version, path: target, origin: :hex_cache}]
        else
          []
        end

      _other ->
        []
    end)
  end

  # Lock files use quoted keywords, which the compiler reports as style
  # diagnostics; they are collected here instead of printed.
  defp read_lock(path) do
    {{lock, _binding}, _diagnostics} = Code.with_diagnostics(fn -> Code.eval_file(path) end)
    lock
  end

  defp hex_home, do: System.get_env("HEX_HOME") || Path.join(System.user_home!(), ".hex")

  defp build_registry(work, tarballs) do
    public = Path.join(work, "public")
    key = Path.join(work, "registry_key.pem")
    private = :public_key.generate_key({:rsa, 2048, 65_537})

    File.write!(
      key,
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private)])
    )

    File.mkdir_p!(Path.join(public, "tarballs"))

    tarballs
    |> File.ls!()
    |> Enum.each(&File.cp!(Path.join(tarballs, &1), Path.join([public, "tarballs", &1])))

    {log, status} =
      System.cmd("mix", ["hex.registry", "build", public, "--name=hexpm", "--private-key=#{key}"],
        stderr_to_stdout: true
      )

    status == 0 || abort("registry build failed:\n#{log}")
    public
  end

  defp serve(work, public) do
    {:ok, _apps} = Application.ensure_all_started(:inets)

    {:ok, httpd} =
      :inets.start(:httpd,
        port: 0,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"wotex-archive-registry",
        server_root: String.to_charlist(work),
        document_root: String.to_charlist(public),
        mime_types: [{~c"tar", ~c"application/octet-stream"}]
      )

    port = httpd |> :httpd.info() |> Keyword.fetch!(:port)
    {httpd, port}
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
          not Code.ensure_loaded?(Exqlite.Sqlite3),
      base_modules_present:
        Code.ensure_loaded?(Wotex.Lab) and Code.ensure_loaded?(Wotex.Lab.Telemetry) and
          Code.ensure_loaded?(Wotex.Lab.DesignSystem) and Code.ensure_loaded?(Wotex.Nx.Encoder)
    }

    IO.puts("ARCHIVE_CONSUMER_CHECKS " <> Enum.map_join(Enum.sort(checks), ",", fn {k, v} -> "#{k}=#{v}" end))
    '''
  end

  # Every executable on the current PATH except Git is linked into one directory;
  # the consumer sees only that directory.
  defp restricted_path(work) do
    bin = Path.join(work, "bin")
    File.mkdir_p!(bin)

    System.get_env("PATH", "")
    |> String.split(":", trim: true)
    |> Enum.filter(&File.dir?/1)
    # The running VM prepends its private erts directory; its launcher depends on
    # variables a symlink would lose, so the public bin directory serves instead.
    |> Enum.reject(&Regex.match?(~r{/erts-\d}, &1))
    |> Enum.each(fn dir ->
      dir
      |> File.ls!()
      |> Enum.reject(&(&1 == "git" or String.starts_with?(&1, "git-")))
      |> Enum.each(fn name ->
        source = Path.join(dir, name)
        target = Path.join(bin, name)

        if executable?(source) and not File.exists?(target) do
          File.ln_s!(source, target)
        end
      end)
    end)

    File.exists?(Path.join(bin, "git")) && abort("git leaked into the restricted PATH")
    bin
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      {:ok, %File.Stat{type: :symlink}} -> File.regular?(path)
      _other -> false
    end
  end

  defp consumer_env(work, port, bin) do
    [
      {"PATH", bin},
      # The erl launcher locates its root from its own path; a link elsewhere
      # needs the root stated explicitly.
      {"ERL_ROOTDIR", List.to_string(:code.root_dir())},
      {"HEX_HOME", Path.join(work, "hex_home")},
      {"HEX_MIRROR", "http://127.0.0.1:#{port}"},
      {"HEX_UNSAFE_REGISTRY", "1"},
      {"HEX_OFFLINE", nil},
      {"WOTEX_PATH_DEPS", nil},
      {"MIX_ENV", "prod"}
    ]
  end

  defp run!(consumer, env, args, label) do
    task =
      Task.async(fn -> System.cmd("mix", args, cd: consumer, env: env, stderr_to_stdout: true) end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> output
      {:ok, {output, status}} -> abort("#{label} failed (#{status}):\n#{output}")
      nil -> abort("#{label} exceeded #{@deadline_ms} ms")
    end
  end

  # The resolved graph is inspected recursively through the consumer lock: every
  # package must be an admitted archive and no profile package may appear.
  defp inspect_graph(consumer, admitted) do
    lock = read_lock(Path.join(consumer, "mix.lock"))
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
        revision: revision(root),
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

  defp revision(root) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _other -> "unknown"
    end
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
