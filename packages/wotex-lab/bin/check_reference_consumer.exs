# Full reference-consumer gate. It builds the selected WoTEx packages as Hex
# archives, resolves the Lab and Workbench test artifacts from a private local
# registry with Git absent, and runs both suites through a bounded native
# process-group supervisor. Optional service lanes run only when their exact
# prerequisites are already provisioned; an absent lane is recorded as not run.
#
# Run from this package with:
# `WOTEX_PATH_DEPS=1 mix run --no-start bin/check_reference_consumer.exs`.

Code.require_file("support/archive_repository.exs", __DIR__)
Code.require_file("support/reference_summary.exs", __DIR__)
Code.require_file("support/reference_inputs.exs", __DIR__)
Code.require_file("support/reference_runner.exs", __DIR__)
Code.require_file("support/work_directory.exs", __DIR__)
Code.require_file("support/child_environment.exs", __DIR__)

defmodule Wotex.Lab.Check.ReferenceConsumer do
  @moduledoc false

  alias Wotex.Lab.Check.{
    ArchiveRepository,
    ChildEnvironment,
    ReferenceInputs,
    ReferenceRunner,
    ReferenceSummary
  }

  alias Wotex.Lab.Evidence.{Digest, Record}

  @deadline_ms 1_800_000
  @output_bytes 8_388_608
  @seed 1
  @images %{
    broker: "eclipse-mosquitto:2",
    grafana: "grafana/grafana:13.2.2",
    greptime: "greptime/greptimedb:v1.1.4"
  }
  @packages [
    {:wotex, "wotex"},
    {:wotex_nx, "wotex-nx"},
    {:wotex_runtime, "wotex-runtime"},
    {:wotex_directory, "wotex-directory"},
    {:wotex_continuum, "wotex-continuum"},
    {:wotex_binding_http, "wotex-binding-http"},
    {:wotex_binding_mqtt, "wotex-binding-mqtt"},
    {:wotex_conformance, "wotex-conformance"},
    {:wotex_lab, "wotex-lab"}
  ]
  @native_packages ~w(baml_elixir ex_maude explorer)a
  @workbench_patterns ~w(.check.exs .credo.exs .formatter.exs coveralls.json
                          config/**/* lib/**/* mix_tasks/**/* priv/static/**/* test/**/*
                          bin/**/* Dockerfile README.md mix.exs mix.lock)

  @spec run() :: :ok
  def run do
    root = Path.expand("..", __DIR__)
    host_source = Path.join(root, "hosts/workbench")
    File.cd!(root)

    System.get_env("WOTEX_PATH_DEPS") == "1" ||
      abort("reference source admission requires explicit WOTEX_PATH_DEPS=1")

    source_cohort?() || abort("reference preflight refused unreviewed workspace source drift")

    work = Wotex.Lab.Check.WorkDirectory.create!(root, :reference)
    started = System.monotonic_time()
    identities = source_identities(root, host_source)
    lanes = lanes()
    IO.puts("lanes: " <> Enum.map_join(lanes, ", ", fn {lane, on?} -> "#{lane}=#{on?}" end))

    tarballs = Path.join(work, "tarballs")
    File.mkdir!(tarballs)
    local = ArchiveRepository.build_archives!(root, @packages, tarballs)
    local_names = MapSet.new(local, & &1.name)

    public =
      ArchiveRepository.copy_public_archives!(
        [Path.join(root, "mix.lock"), Path.join(host_source, "mix.lock")],
        tarballs,
        local_names
      )

    admitted = local ++ public
    native = admit_native_artifacts(work, host_source)
    lab_consumer = lab_consumer!(work, root, local)
    {workbench_archive, workbench_consumer} = workbench_consumer!(work, host_source)
    registry = ArchiveRepository.build_registry!(work, tarballs)
    {httpd, port} = ArchiveRepository.serve!(work, registry)

    try do
      runner = ReferenceRunner.build!(root, work)
      bin = ArchiveRepository.restricted_path!(work)
      environment = environment(work, port, bin)
      assert_git_absent!(bin, environment)

      lab_graph = resolve!(lab_consumer, environment, "Lab")
      lab_resolved = inspect_graph!(lab_consumer, admitted, lab_graph, local_names)
      lab_result = suite!(runner, lab_consumer, environment ++ lab_lane_env(lanes), work)
      File.write!(Path.join(work, "lab-test-output.txt"), lab_result.output)

      workbench_graph = resolve!(workbench_consumer, environment, "Workbench")

      workbench_resolved =
        inspect_graph!(workbench_consumer, admitted, workbench_graph, local_names)

      workbench_result =
        suite!(runner, workbench_consumer, environment ++ workbench_lane_env(lanes), work)

      File.write!(Path.join(work, "workbench-test-output.txt"), workbench_result.output)

      lab_summary = ReferenceSummary.parse(lab_result.output)
      workbench_summary = ReferenceSummary.parse(workbench_result.output)
      unchanged? = identities == source_identities(root, host_source) and source_cohort?()
      elapsed = elapsed_ms(started)

      evidence =
        record(
          root,
          work,
          %{
            lanes: lanes,
            admitted: admitted,
            native: native,
            runner: runner,
            workbench_archive: workbench_archive,
            lab_result: lab_result,
            workbench_result: workbench_result,
            lab_summary: lab_summary,
            workbench_summary: workbench_summary,
            lab_resolved: lab_resolved,
            workbench_resolved: workbench_resolved,
            identities: identities,
            unchanged?: unchanged?,
            elapsed: elapsed
          }
        )

      cleanup(work, tarballs, lab_consumer, workbench_consumer, registry)
      IO.puts("evidence retained at #{evidence}")

      (successful?(lab_result, lab_summary) and
         successful?(workbench_result, workbench_summary) and unchanged?) ||
        abort("reference programme failed, emitted an invalid summary or changed source")

      IO.puts(
        "reference consumer: Lab and Workbench artifact cohorts passed with bounded output, verified descendant cleanup and Git absent"
      )
    after
      :inets.stop(:httpd, httpd)
    end
  end

  defp environment(work, port, bin) do
    [
      {"RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH", Path.join(work, "native_cache")}
      | ChildEnvironment.scrubbed() ++ ArchiveRepository.environment(work, port, bin, "test")
    ]
  end

  defp lab_consumer!(work, root, local) do
    archive = Enum.find_value(local, fn item -> if item.name == "wotex_lab", do: item.path end)
    archive || abort("the Lab archive is absent")
    consumer = Path.join(work, "lab-consumer")
    unpack_hex!(archive, consumer, work)

    harness =
      ReferenceInputs.files(root)
      |> Enum.filter(fn path ->
        relative = Path.relative_to(path, root)
        String.starts_with?(relative, ["test/", "config/", "bin/"]) or relative == "mix.lock"
      end)

    copy_files!(root, consumer, harness)
    consumer
  end

  defp unpack_hex!(archive, consumer, work) do
    outer = Path.join(work, "lab-package")
    File.mkdir!(outer)
    File.mkdir!(consumer)

    case :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(outer)) do
      :ok -> :ok
      {:error, reason} -> abort("Lab archive extraction failed: #{inspect(reason)}")
    end

    contents = Path.join(outer, "contents.tar.gz")
    File.regular?(contents) || abort("Lab archive has no contents payload")

    case :erl_tar.extract(String.to_charlist(contents), [
           :compressed,
           cwd: String.to_charlist(consumer)
         ]) do
      :ok -> :ok
      {:error, reason} -> abort("Lab contents extraction failed: #{inspect(reason)}")
    end

    reject_symlinks!(consumer)
  end

  defp workbench_consumer!(work, source) do
    files = source_files(source, @workbench_patterns)
    archive = Path.join(work, "wotex-lab-workbench-reference.tar")
    relative = Enum.map(files, &Path.relative_to(&1, source))

    {output, status} =
      System.cmd("tar", ["-cf", archive, "-C", source | relative],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    status == 0 || abort("Workbench reference artifact failed (#{status}):\n#{output}")
    consumer = Path.join(work, "workbench-consumer")
    File.mkdir!(consumer)

    case :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(consumer)) do
      :ok -> :ok
      {:error, reason} -> abort("Workbench reference extraction failed: #{inspect(reason)}")
    end

    reject_symlinks!(consumer)
    {archive, consumer}
  end

  defp copy_files!(root, target, files) do
    Enum.each(files, fn source ->
      symlink?(source) && abort("reference harness contains a symlink")
      destination = Path.join(target, Path.relative_to(source, root))
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source, destination)
    end)
  end

  defp source_files(root, patterns) do
    files =
      patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()

    files == [] && abort("reference source artifact is empty")
    files
  end

  defp reject_symlinks!(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      symlink?(path) &&
        abort("reference artifact contains a symlink: #{Path.relative_to(path, root)}")
    end)
  end

  defp symlink?(path), do: match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path))

  defp assert_git_absent!(bin, env) do
    shell = Path.join(bin, "sh")
    File.regular?(shell) || abort("restricted reference PATH has no shell for its Git sentinel")

    case System.cmd(shell, ["-c", "command -v git >/dev/null 2>&1"],
           env: env,
           stderr_to_stdout: true
         ) do
      {_, 1} -> :ok
      {_, status} -> abort("Git sentinel failed closed with status #{status}")
    end
  end

  defp resolve!(consumer, env, label) do
    ArchiveRepository.run!(
      consumer,
      env,
      ["deps.get", "--check-locked"],
      "#{label} artifact dependency resolution",
      @deadline_ms
    )

    tree =
      ArchiveRepository.run!(
        consumer,
        env,
        ["deps.tree"],
        "#{label} artifact dependency graph",
        @deadline_ms
      )

    String.contains?(tree, "path:") && abort("#{label} dependency graph contains a path")
    String.contains?(tree, "git:") && abort("#{label} dependency graph contains Git")
    tree
  end

  defp inspect_graph!(consumer, admitted, tree, local_names) do
    lock = ArchiveRepository.read_lock!(Path.join(consumer, "mix.lock"))
    by_name = Map.new(lock, fn {name, entry} -> {Atom.to_string(name), entry} end)
    archives = Map.new(admitted, &{{&1.name, &1.version}, &1})

    resolved =
      tree
      |> active_packages()
      |> Enum.map(fn name ->
        entry = Map.fetch!(by_name, name)

        (is_tuple(entry) and elem(entry, 0) == :hex) ||
          abort("#{name} did not resolve from a Hex archive")

        version = elem(entry, 2)
        archive = Map.get(archives, {name, version}) || abort("#{name} #{version} was not admitted")
        %{name: name, version: version, archive: Digest.file!(archive.path)}
      end)

    resolved_names = MapSet.new(resolved, & &1.name)

    local_names
    |> MapSet.intersection(MapSet.new(Map.keys(by_name)))
    |> Enum.each(fn name ->
      MapSet.member?(resolved_names, name) || abort("artifact graph omitted local package #{name}")
    end)

    resolved
  end

  defp active_packages(tree) do
    tree
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(fn line ->
      case Regex.run(~r/([a-z][a-z0-9_]*)\s+(?:==|~>|>=|<=|>|<|\d)/, line) do
        [_, name] -> name
        nil -> abort("dependency tree line is malformed: #{inspect(line)}")
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp suite!(runner, consumer, env, work) do
    bin = env |> Enum.find_value(fn {key, value} -> if key == "PATH", do: value end)
    restricted_mix = Path.join(bin, "mix")
    File.regular?(restricted_mix) || abort("restricted reference PATH has no Mix executable")

    ReferenceRunner.run!(
      runner,
      consumer,
      restricted_mix,
      ["test", "--no-color", "--seed", Integer.to_string(@seed)],
      deadline_ms: @deadline_ms,
      output_bytes: @output_bytes,
      env: env,
      temp_dir: work
    )
  end

  defp successful?(result, summary) do
    result.cleanup == :ok and result.outcome == "exit" and
      ReferenceSummary.successful?(result.status, summary)
  end

  defp lanes do
    docker = docker?()
    greptime = docker and image?(@images.greptime)

    %{
      broker: docker and image?(@images.broker),
      grafana: greptime and image?(@images.grafana),
      greptime: greptime,
      maude: maude_path() != nil
    }
  end

  defp lab_lane_env(lanes) do
    if(lanes.broker, do: [{"WOTEX_LAB_BROKER", "1"}], else: [{"WOTEX_LAB_BROKER", nil}]) ++
      if(lanes.greptime,
        do: [{"WOTEX_LAB_GREPTIME", "1"}],
        else: [{"WOTEX_LAB_GREPTIME", nil}]
      ) ++
      if(lanes.maude,
        do: [{"WOTEX_LAB_MAUDE", maude_path()}],
        else: [{"WOTEX_LAB_MAUDE", nil}]
      )
  end

  defp workbench_lane_env(lanes) do
    if(lanes.greptime,
      do: [{"WOTEX_LAB_GREPTIME", "1"}],
      else: [{"WOTEX_LAB_GREPTIME", nil}]
    ) ++
      if(lanes.grafana,
        do: [{"WOTEX_LAB_GRAFANA", "1"}],
        else: [{"WOTEX_LAB_GRAFANA", nil}]
      )
  end

  defp docker? do
    case System.find_executable("docker") do
      nil ->
        false

      _ ->
        match?(
          {_, 0},
          System.cmd("docker", ["info"],
            env: ChildEnvironment.scrubbed(),
            stderr_to_stdout: true
          )
        )
    end
  end

  defp image?(image) do
    match?(
      {_, 0},
      System.cmd("docker", ["image", "inspect", image],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )
    )
  end

  defp maude_path do
    case System.get_env("WOTEX_LAB_MAUDE") do
      path when is_binary(path) -> if File.regular?(path), do: path
      _ -> nil
    end
  end

  defp admit_native_artifacts(work, host_source) do
    lock = ArchiveRepository.read_lock!(Path.join(host_source, "mix.lock"))
    source = native_cache()
    target = Path.join(work, "native_cache")
    File.mkdir!(target)

    Enum.map(@native_packages, fn package ->
      version =
        case Map.fetch!(lock, package) do
          {:hex, _, version, _, _, _, "hexpm", _} -> version
          other -> abort("unsupported native package lock entry for #{package}: #{inspect(other)}")
        end

      architecture = List.to_string(:erlang.system_info(:system_architecture))

      matches =
        Path.wildcard(Path.join(source, "*#{package}*-v#{version}-*-#{architecture}.*.tar.gz"))

      case matches do
        [path] ->
          copy = Path.join(target, Path.basename(path))
          File.cp!(path, copy)
          %{name: Atom.to_string(package), version: version, path: copy}

        [] ->
          abort("precompiled artifact for #{package} #{version} is absent from the local cache")

        many ->
          abort("ambiguous precompiled artifacts for #{package} #{version}: #{inspect(many)}")
      end
    end)
  end

  defp native_cache do
    System.get_env("RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH") ||
      :user_cache
      |> :filename.basedir("rustler_precompiled/precompiled_nifs")
      |> to_string()
  end

  defp source_identities(root, host_source) do
    {:ok, lab} = ReferenceInputs.digest(root)
    {:ok, workbench} = Digest.tree(host_source, @workbench_patterns)
    %{lab: lab, workbench: workbench}
  end

  defp source_cohort? do
    case System.cmd("elixir", ["bin/check_source_cohort.exs"],
           env: ChildEnvironment.scrubbed(),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        true

      {output, _} ->
        IO.puts(:stderr, output)
        false
    end
  end

  defp record(root, work, result) do
    %{
      lanes: lanes,
      admitted: admitted,
      native: native,
      runner: runner,
      workbench_archive: workbench_archive,
      lab_result: lab_result,
      workbench_result: workbench_result,
      lab_summary: lab_summary,
      workbench_summary: workbench_summary,
      lab_resolved: lab_resolved,
      workbench_resolved: workbench_resolved,
      identities: identities,
      unchanged?: unchanged?,
      elapsed: elapsed
    } = result

    source_tree_digest = Digest.bytes(identities.lab <> "\n" <> identities.workbench)
    {:ok, lock_digest} = Digest.tree(root, ["mix.lock", "hosts/workbench/mix.lock"])
    lab_passed? = successful?(lab_result, lab_summary)
    workbench_passed? = successful?(workbench_result, workbench_summary)
    passed? = lab_passed? and workbench_passed? and unchanged?

    dependencies =
      admitted
      |> Enum.map(&%{name: &1.name, version: &1.version, archive: Digest.file!(&1.path)})
      |> Kernel.++(
        Enum.map(
          native,
          &%{
            name: "native:#{&1.name}",
            version: &1.version,
            archive: Digest.file!(&1.path)
          }
        )
      )
      |> Enum.uniq_by(&{&1.name, &1.version, &1.archive})
      |> Enum.sort_by(&{&1.name, &1.version})

    assertions = [
      %{id: "WLB-C10:reference-consumer:lab-suite", status: suite_status(lab_passed?)},
      %{
        id: "WLB-C10:reference-consumer:workbench-suite",
        status: suite_status(workbench_passed?)
      },
      %{id: "WLB-C10:reference-consumer:unchanged-source", status: suite_status(unchanged?)},
      %{id: "WLB-C10:reference-consumer:runner-containment", status: suite_status(passed?)},
      %{
        id: "WLB-C10:reference-consumer:complete-reference-programme",
        status: suite_status(passed?)
      }
      | Enum.map(lanes, fn {lane, on?} ->
          %{
            id: "WLB-C10:reference-consumer:lane:#{lane}",
            status: if(on?, do: suite_status(passed?), else: :not_run)
          }
        end)
    ]

    {:ok, evidence} =
      Record.new(
        scenario_id: "reference-consumer:artifact-cohort",
        revision: ArchiveRepository.revision(root),
        attempt: 1,
        source_tree_digest: source_tree_digest,
        lock_digest: lock_digest,
        dependencies: dependencies,
        fixtures: %{},
        seed: @seed,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{deadline_ms: @deadline_ms, output_bytes: @output_bytes},
        inputs: [
          "runner:#{runner.digest}",
          "workbench-source:#{Digest.file!(workbench_archive)}",
          "lab-resolved:#{length(lab_resolved)}",
          "workbench-resolved:#{length(workbench_resolved)}"
        ],
        assertions: assertions,
        outcomes: %{
          lab: counts(lab_summary, lab_result),
          workbench: counts(workbench_summary, workbench_result),
          git_on_path: false,
          source_artifacts: true,
          archive_only_dependencies: true
        },
        durations: %{gate_ms: elapsed},
        cleanup: %{
          status: if(passed?, do: :ok, else: :failed),
          details: %{
            runner: "native process group",
            retained: "evidence.json and bounded suite outputs"
          }
        }
      )

    {:ok, bytes} = Record.encode(evidence)
    path = Path.join(work, "evidence.json")
    File.write!(path, bytes)
    path
  end

  defp counts({:ok, counts}, result),
    do: Map.merge(counts, %{exit_status: result.status, output_bytes: result.output_bytes})

  defp counts({:error, _}, result) do
    %{
      tests: 0,
      failures: 0,
      excluded: 0,
      exit_status: result.status,
      output_bytes: result.output_bytes
    }
  end

  defp cleanup(work, tarballs, lab_consumer, workbench_consumer, registry) do
    String.contains?(work, ".archive-check.reference-") ||
      abort("refusing unsafe reference cleanup")

    Enum.each(
      [
        tarballs,
        lab_consumer,
        workbench_consumer,
        registry,
        Path.join(work, "lab-package"),
        Path.join(work, "bin"),
        Path.join(work, "hex_home"),
        Path.join(work, "native_cache"),
        Path.join(work, "reference-runner-target"),
        Path.join(work, "wotex-lab-workbench-reference.tar")
      ],
      &File.rm_rf!/1
    )

    File.rm(Path.join(work, "registry_key.pem"))
  end

  defp suite_status(true), do: :pass
  defp suite_status(_), do: :fail

  defp elapsed_ms(started) do
    System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ReferenceConsumer.run()
