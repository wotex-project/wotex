# Reference-consumer gate: runs every Lab scenario suite against the same
# source cohort with each optional lane enabled where its dependency is present
# (a Docker daemon for the broker and GreptimeDB lanes, a pinned Maude engine
# for the formal lane) and records the outcome as an evidence record. A lane
# whose dependency is absent is recorded as not run, never as passed.
# Runs through Mix: `mix run --no-start bin/check_reference_consumer.exs`.

Code.require_file("support/reference_summary.exs", __DIR__)
Code.require_file("support/reference_inputs.exs", __DIR__)
Code.require_file("support/work_directory.exs", __DIR__)
Code.require_file("support/child_environment.exs", __DIR__)

defmodule Wotex.Lab.Check.ReferenceConsumer do
  @moduledoc false

  alias Wotex.Lab.Check.{ChildEnvironment, ReferenceInputs, ReferenceSummary}
  alias Wotex.Lab.Evidence.{Digest, Record}

  @deadline_ms 1_800_000
  @images %{broker: "eclipse-mosquitto:2", greptime: "greptime/greptimedb:v1.1.4"}
  @seed 1

  @spec run() :: :ok
  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)

    System.get_env("WOTEX_PATH_DEPS") == "1" ||
      abort("reference source suites require explicit WOTEX_PATH_DEPS=1")

    source_cohort?() || abort("reference preflight refused unreviewed workspace source drift")

    work = Wotex.Lab.Check.WorkDirectory.create!(root, :reference)
    started = System.monotonic_time()
    {:ok, source_digest} = ReferenceInputs.digest(root)
    docker = docker?()

    lanes = %{
      broker: docker and image?(@images.broker),
      greptime: docker and image?(@images.greptime),
      maude: maude_path() != nil
    }

    IO.puts("lanes: " <> Enum.map_join(lanes, ", ", fn {lane, on?} -> "#{lane}=#{on?}" end))

    env =
      [{"MIX_ENV", "test"}, {"WOTEX_PATH_DEPS", System.get_env("WOTEX_PATH_DEPS")}] ++
        if(lanes.broker, do: [{"WOTEX_LAB_BROKER", "1"}], else: [{"WOTEX_LAB_BROKER", nil}]) ++
        if(lanes.greptime, do: [{"WOTEX_LAB_GREPTIME", "1"}], else: [{"WOTEX_LAB_GREPTIME", nil}]) ++
        if(lanes.maude, do: [{"WOTEX_LAB_MAUDE", maude_path()}], else: [{"WOTEX_LAB_MAUDE", nil}])

    {output, status} = bounded_test(env)
    File.write!(Path.join(work, "test-output.txt"), output)
    summary = ReferenceSummary.parse(output)
    IO.puts("suite: #{inspect(summary)} (exit #{status})")
    elapsed = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    unchanged? = ReferenceInputs.digest(root) == {:ok, source_digest} and source_cohort?()
    evidence = record(root, work, lanes, summary, status, elapsed, {source_digest, unchanged?})
    IO.puts("evidence retained at #{evidence}")

    (unchanged? and ReferenceSummary.successful?(status, summary)) ||
      abort("reference suite failed, summary is invalid or source changed during execution")

    IO.puts(
      "reference consumer: enabled source suites passed; absent lanes are not run. This is not full reference/artifact or runner-containment acceptance."
    )
  end

  defp bounded_test(env) do
    task =
      Task.async(fn ->
        System.cmd("mix", ["test", "--no-color", "--seed", Integer.to_string(@seed)],
          env: env,
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> abort("reference suite exceeded #{@deadline_ms} ms")
    end
  end

  defp docker? do
    case System.find_executable("docker") do
      nil ->
        false

      _ ->
        match?(
          {_out, 0},
          System.cmd("docker", ["info"], env: ChildEnvironment.scrubbed(), stderr_to_stdout: true)
        )
    end
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

  defp image?(image) do
    match?(
      {_out, 0},
      System.cmd("docker", ["image", "inspect", image],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )
    )
  end

  defp maude_path do
    case System.get_env("WOTEX_LAB_MAUDE") do
      path when is_binary(path) -> if File.regular?(path), do: path, else: nil
      nil -> nil
    end
  end

  defp record(root, work, lanes, summary, status, elapsed, {source_tree_digest, unchanged?}) do
    {:ok, lock_digest} = Digest.file(Path.join(root, "mix.lock"))
    passed? = unchanged? and ReferenceSummary.successful?(status, summary)

    {summary_valid?, counts} =
      case summary do
        {:ok, counts} -> {true, counts}
        {:error, _} -> {false, %{tests: 0, failures: 0, excluded: 0}}
      end

    lane_assertions =
      Enum.map(lanes, fn {lane, on?} ->
        %{
          id: "WLB-C10:reference-consumer:lane:#{lane}",
          status: if(on?, do: suite_status(passed?), else: :not_run)
        }
      end)

    {:ok, record} =
      Record.new(
        scenario_id: "reference-consumer:workspace",
        revision: revision(root),
        attempt: 1,
        source_tree_digest: source_tree_digest,
        lock_digest: lock_digest,
        dependencies: [%{name: "wotex_lab", version: version(), archive: :missing}],
        fixtures: %{},
        seed: @seed,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{deadline_ms: @deadline_ms},
        inputs:
          ["workspace:WOTEX_PATH_DEPS"] ++
            Enum.map(@images, fn {_, image} -> "image:" <> image end),
        assertions: [
          %{id: "WLB-C10:reference-consumer:suite", status: suite_status(passed?)},
          %{id: "WLB-C10:reference-consumer:unchanged-source", status: suite_status(unchanged?)},
          %{id: "WLB-C10:reference-consumer:runner-containment", status: :not_run},
          %{id: "WLB-C10:reference-consumer:complete-reference-programme", status: :not_run}
          | lane_assertions
        ],
        outcomes: %{
          tests: counts.tests,
          failures: counts.failures,
          excluded: counts.excluded,
          summary_valid: summary_valid?,
          exit_status: status
        },
        durations: %{gate_ms: elapsed},
        cleanup: %{
          status: :failed,
          details: %{
            retained: "evidence.json and test-output.txt",
            reason: "outer runner descendant cleanup is not independently verified"
          }
        }
      )

    {:ok, bytes} = Record.encode(record)
    path = Path.join(work, "evidence.json")
    File.write!(path, bytes)
    path
  end

  defp suite_status(true), do: :pass
  defp suite_status(_), do: :fail

  defp version, do: Mix.Project.config()[:version]

  defp revision(root) do
    case System.cmd("git", ["rev-parse", "HEAD"],
           cd: root,
           env: ChildEnvironment.scrubbed(),
           stderr_to_stdout: true
         ) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ReferenceConsumer.run()
