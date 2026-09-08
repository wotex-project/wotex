# Reference-consumer gate: runs every Lab scenario suite against the same
# source cohort with each optional lane enabled where its dependency is present
# (a Docker daemon for the broker and GreptimeDB lanes, a pinned Maude engine
# for the formal lane) and records the outcome as an evidence record. A lane
# whose dependency is absent is recorded as not run, never as passed.
# Runs through Mix: `mix run --no-start bin/check_reference_consumer.exs`.

defmodule Wotex.Lab.Check.ReferenceConsumer do
  @moduledoc false

  alias Wotex.Lab.Evidence.{Digest, Record}

  @cohort ~w(lib/**/* test/**/* priv/fixtures/**/* priv/models/**/* docs/specs/**/* mix.exs mix.lock)
  @deadline_ms 1_800_000
  @images ["eclipse-mosquitto:2", "greptime/greptimedb:v1.1.4"]

  def run do
    root = Path.expand("..", __DIR__)
    File.cd!(root)

    root
    |> Path.join(".archive-check.reference-*")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(&File.rm_rf!/1)

    work = Path.join(root, ".archive-check.reference-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)
    started = System.monotonic_time()

    lanes = %{
      broker: docker?() and images?(),
      greptime: docker?(),
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
    summary = summary(output)
    IO.puts("suite: #{inspect(summary)} (exit #{status})")
    elapsed = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    evidence = record(root, work, lanes, summary, status, elapsed)
    IO.puts("evidence retained at #{evidence}")
    status == 0 || abort("reference consumer suite failed")

    IO.puts(
      "reference consumer: every enabled lane passed against the workspace cohort; absent lanes recorded as not run"
    )
  end

  defp bounded_test(env) do
    task =
      Task.async(fn ->
        System.cmd("mix", ["test", "--no-color"], env: env, stderr_to_stdout: true)
      end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> abort("reference suite exceeded #{@deadline_ms} ms")
    end
  end

  # ExUnit prints either "N tests, F failures[, E excluded]" or the newer
  # "Result: P/N passed[, E excluded]" plus "Failed: F tests" summary.
  defp summary(output) do
    cond do
      match = Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) excluded)?/, output) ->
        [_all, tests, failures | excluded] = match

        %{
          tests: String.to_integer(tests),
          failures: String.to_integer(failures),
          excluded: excluded(excluded)
        }

      match = Regex.run(~r/Result: (\d+)(?:\/(\d+))? passed(?:, (\d+) excluded)?/, output) ->
        [_all, passed | more] = match
        total = if Enum.at(more, 0) in [nil, ""], do: passed, else: Enum.at(more, 0)

        %{
          tests: String.to_integer(total),
          failures: String.to_integer(total) - String.to_integer(passed),
          excluded: excluded(Enum.drop(more, 1))
        }

      true ->
        %{tests: 0, failures: -1, excluded: 0}
    end
  end

  defp excluded([value]) when is_binary(value) and value != "", do: String.to_integer(value)
  defp excluded(_none), do: 0

  defp docker? do
    case System.find_executable("docker") do
      nil -> false
      _path -> match?({_out, 0}, System.cmd("docker", ["info"], stderr_to_stdout: true))
    end
  end

  defp images? do
    Enum.all?(@images, fn image ->
      match?({_out, 0}, System.cmd("docker", ["image", "inspect", image], stderr_to_stdout: true))
    end)
  end

  defp maude_path do
    case System.get_env("WOTEX_LAB_MAUDE") do
      path when is_binary(path) -> if File.regular?(path), do: path, else: nil
      nil -> nil
    end
  end

  defp record(root, work, lanes, summary, status, elapsed) do
    {:ok, source_tree_digest} = Digest.tree(root, @cohort)
    {:ok, lock_digest} = Digest.file(Path.join(root, "mix.lock"))

    lane_assertions =
      Enum.map(lanes, fn {lane, on?} ->
        %{
          id: "WLB-C10:reference-consumer:lane:#{lane}",
          status: if(on?, do: suite_status(status), else: :not_run)
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
        seed: 0,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{deadline_ms: @deadline_ms},
        inputs: ["workspace:WOTEX_PATH_DEPS"] ++ Enum.map(@images, &("image:" <> &1)),
        assertions: [
          %{id: "WLB-C10:reference-consumer:suite", status: suite_status(status)} | lane_assertions
        ],
        outcomes: %{
          tests: summary.tests,
          failures: summary.failures,
          excluded: summary.excluded,
          exit_status: status
        },
        durations: %{gate_ms: elapsed},
        cleanup: %{status: :ok, details: %{retained: "evidence.json and test-output.txt"}}
      )

    {:ok, bytes} = Record.encode(record)
    path = Path.join(work, "evidence.json")
    File.write!(path, bytes)
    path
  end

  defp suite_status(0), do: :pass
  defp suite_status(_status), do: :fail

  defp version, do: Mix.Project.config()[:version]

  defp revision(root) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _other -> "unknown"
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.ReferenceConsumer.run()
