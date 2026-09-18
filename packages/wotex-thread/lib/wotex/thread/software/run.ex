defmodule Wotex.Thread.Software.Run do
  @moduledoc """
  Runs the Thread software acceptance lanes against a verified fixture workspace.

  The runner requires Linux and an already completed `Wotex.Thread.Software.Build`
  workspace; it never builds. It first executes the sanitizer native test
  executables, then two ExUnit lanes through the owned command guardian: the
  complete suite with the normal host and `--include interop --include software
  --exclude hardware --seed 0`, and the software and native-contract tests with
  the sanitizer host. Each lane sets `WOTEX_REQUIRE_SOFTWARE=1`, so missing
  fixture configuration fails instead of skipping.

  `test/software/acceptance.json` names every required case per lane. A lane
  passes only when its command exits zero, every required case passed exactly
  once and no recorded case failed, skipped or was invalid. After the lanes the
  runner counts and kills any surviving process whose executable lies inside the
  workspace; a survivor fails the run. The bounded `software-run/result.json`
  binds source, manifest, corpus, toolchain, commands, case outcomes, log digests
  and cleanup counts. A run directory is terminal: another run requires a fresh
  software workspace.
  """

  alias Wotex.Thread.Native.{Command, Source}
  alias Wotex.Thread.Software.Build

  @project_root Path.expand("../../../..", __DIR__)
  @suite_timeout 1_200_000
  @native_timeout 120_000
  @output_limit 16_777_216
  @normal_arguments ~w(test --include interop --include software --exclude hardware --seed 0)
  @sanitizer_options [
    {"ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1:abort_on_error=0"},
    {"UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1"}
  ]

  @typedoc "Observed case outcomes for one lane."
  @type evaluation :: %{String.t() => term()}

  @doc "Validates exactly one absolute `--workspace` argument."
  @spec arguments(term()) :: {:ok, Path.t()} | {:error, :invalid_software_run_arguments}
  def arguments(args) do
    case Build.arguments(args) do
      {:ok, workspace} -> {:ok, workspace}
      _ -> {:error, :invalid_software_run_arguments}
    end
  end

  @typedoc """
  The explicit outside world of one software run.

  `platform` is the running operating system, `project_root` the package
  directory whose suite and inventory are used, `build` the fixture-workspace verification,
  `mix` the suite runner and `proc` the process table consulted for survivors.
  """
  @type environment :: %{
          platform: {atom(), atom()},
          project_root: Path.t(),
          build: (Path.t() -> {:ok, map()} | {:error, term()}),
          mix: Path.t() | nil,
          proc: Path.t()
        }

  @doc "Returns the production software run environment."
  @spec environment() :: environment()
  def environment do
    %{
      platform: :os.type(),
      project_root: @project_root,
      build: &Build.run/1,
      mix: nil,
      proc: "/proc"
    }
  end

  @doc "Runs all software lanes and writes `software-run/result.json`."
  @spec run(term(), environment()) ::
          {:ok, %{result: map(), path: Path.t()}} | {:error, term()}
  def run(workspace, environment \\ environment())

  def run(workspace, environment) when is_binary(workspace) and is_map(environment) do
    with :ok <- platform(environment),
         {:ok, ^workspace} <- arguments(["--workspace", workspace]),
         :ok <- built(workspace),
         {:ok, %{reused: true, manifest: manifest}} <- environment.build.(workspace),
         {:ok, inventory} <- inventory(environment),
         {:ok, mix} <- executable(environment),
         {:ok, output} <- output_directory(workspace) do
      result = execute(workspace, output, manifest, inventory, mix, environment)
      path = Path.join(output, "result.json")
      :ok = File.write(path, Jason.encode_to_iodata!(result, pretty: true), [:exclusive, :sync])

      if result["status"] == "passed",
        do: {:ok, %{result: result, path: path}},
        else: {:error, {:software_run_failed, path}}
    end
  end

  def run(_, _), do: {:error, :invalid_software_run_arguments}

  defp built(workspace) do
    if File.regular?(Path.join(workspace, "software-manifest.json")),
      do: :ok,
      else: {:error, :software_workspace_not_built}
  end

  @doc """
  Compares recorded ExUnit case lines with one lane inventory.

  Each line is a JSON object with exactly `module`, `name` and `state`. The
  result lists required cases that are missing or not passed, duplicated cases,
  cases outside the inventory that did not pass and malformed lines.
  """
  @spec evaluate([map()], binary()) :: evaluation()
  def evaluate(required, lines) when is_list(required) and is_binary(lines) do
    decoded = Enum.map(String.split(lines, "\n", trim: true), &case_line/1)
    malformed = Enum.count(decoded, &(&1 == :error))
    cases = Enum.reject(decoded, &(&1 == :error))
    keys = Enum.map(required, &{&1["module"], &1["name"]})
    frequencies = Enum.frequencies_by(cases, &{&1["module"], &1["name"]})

    missing =
      for {module, name} = key <- keys,
          Enum.count(cases, &({&1["module"], &1["name"]} == key and &1["state"] == "passed")) != 1,
          do: %{"module" => module, "name" => name}

    failures =
      for item <- cases, item["state"] != "passed", do: item

    duplicates =
      for {{module, name}, count} <- frequencies,
          count > 1,
          do: %{"module" => module, "name" => name}

    %{
      "cases" => length(cases),
      "passed" => Enum.count(cases, &(&1["state"] == "passed")),
      "missing_or_not_passed" => missing,
      "not_passed" => failures,
      "duplicates" => duplicates,
      "malformed_lines" => malformed,
      "accepted" =>
        cases != [] and required != [] and missing == [] and failures == [] and duplicates == [] and
          malformed == 0
    }
  end

  defp case_line(line) do
    case Jason.decode(line) do
      {:ok, %{"module" => module, "name" => name, "state" => state} = item}
      when map_size(item) == 3 and is_binary(module) and is_binary(name) and
             state in ["passed", "failed", "skipped", "invalid"] ->
        item

      _ ->
        :error
    end
  end

  defp platform(%{platform: platform}) do
    if platform == {:unix, :linux}, do: :ok, else: {:error, :linux_required}
  end

  defp inventory(environment) do
    with {:ok, bytes} <-
           File.read(Path.join(environment.project_root, "test/software/acceptance.json")),
         {:ok,
          %{
            "format" => "wotex.thread.software-acceptance",
            "version" => 1,
            "lanes" => %{"normal" => normal, "sanitized" => sanitized} = lanes
          }}
         when map_size(lanes) == 2 <- Jason.decode(bytes),
         true <- Enum.all?([normal, sanitized], &lane?/1) do
      {:ok, lanes}
    else
      _ -> {:error, :invalid_software_inventory}
    end
  end

  defp lane?(%{"paths" => paths, "required" => [_ | _] = required} = lane) do
    map_size(lane) == 2 and is_list(paths) and Enum.all?(paths, &is_binary/1) and
      Enum.all?(
        required,
        &match?(%{"module" => m, "name" => n} when is_binary(m) and is_binary(n), &1)
      )
  end

  defp lane?(_), do: false

  defp executable(environment) do
    case environment.mix || System.find_executable("mix") do
      path when is_binary(path) -> {:ok, path}
      _ -> {:error, {:missing_software_tool, "mix"}}
    end
  end

  defp output_directory(workspace) do
    path = Path.join(workspace, "software-run")

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, :eexist} -> {:error, :software_run_exists}
      _ -> {:error, :software_run_unavailable}
    end
  end

  defp execute(workspace, output, manifest, inventory, mix, environment) do
    started = System.monotonic_time(:millisecond)
    source = source_identity(environment)
    guardian = Path.join(workspace, "bin/build-command")
    executables = Build.executables(workspace)
    native = Enum.map(executables.native_tests, &native_test(guardian, output, &1))

    lanes =
      for {lane, host, arguments, extra} <- [
            {"normal", executables.host, @normal_arguments, []},
            {"sanitized", executables.sanitized_host,
             ["test" | inventory["sanitized"]["paths"]] ++ ~w(--seed 0), @sanitizer_options}
          ] do
        suite(
          %{
            guardian: guardian,
            output: output,
            executables: executables,
            mix: mix,
            environment: environment
          },
          %{lane: lane, host: host, arguments: arguments, extra: extra, inventory: inventory[lane]}
        )
      end

    cleanup = cleanup(workspace, environment)
    source_after = source_identity(environment)

    passed =
      source == source_after and
        Enum.all?(native, &(&1["exit_status"] == 0)) and
        Enum.all?(lanes, &(&1["exit_status"] == 0 and &1["evaluation"]["accepted"])) and
        cleanup["survivors"] == 0

    %{
      "schema" => "wotex.thread.software-run",
      "version" => 1,
      "status" => if(passed, do: "passed", else: "failed"),
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "source" => source,
      "source_unchanged" => source == source_after,
      "software_manifest_sha256" => digest(Path.join(workspace, "software-manifest.json")),
      "binaries" => manifest["binaries"],
      "native_hosts" => %{
        "normal" => digest(executables.host),
        "sanitized" => digest(executables.sanitized_host)
      },
      "toolchain" => toolchain(),
      "erl_flags" => System.get_env("ERL_FLAGS"),
      "native_tests" => native,
      "lanes" => lanes,
      "cleanup" => cleanup
    }
  end

  defp native_test(guardian, output, executable) do
    name = Path.basename(executable)

    step = %{
      id: :native_test,
      executable: executable,
      cwd: output,
      args: [],
      env: [{"PATH", "/usr/bin:/bin"}, {"LC_ALL", "C"} | @sanitizer_options],
      timeout_ms: @native_timeout,
      output_bytes: 1_048_576,
      cleanup_ms: 1_000
    }

    {status, bytes} = command_result(Command.run(guardian, step))
    log = Path.join(output, "#{name}.log")
    :ok = File.write(log, bytes, [:exclusive])

    %{
      "name" => name,
      "sha256" => digest(executable),
      "exit_status" => status,
      "log_sha256" => digest(log)
    }
  end

  defp suite(context, %{lane: lane, host: host, arguments: arguments, extra: extra} = lane_spec) do
    %{
      guardian: guardian,
      output: output,
      executables: executables,
      mix: mix,
      environment: environment
    } =
      context

    inventory = lane_spec.inventory
    cases = Path.join(output, "#{lane}-cases.jsonl")
    tmp = Path.join(output, "tmp-#{lane}")
    :ok = File.mkdir(tmp)

    env =
      [
        {"PATH", System.get_env("PATH", "/usr/bin:/bin")},
        {"HOME", System.get_env("HOME", tmp)},
        {"LANG", "C.UTF-8"},
        {"LC_ALL", "C.UTF-8"},
        {"MIX_ENV", "test"},
        {"TMPDIR", tmp},
        {"WOTEX_REQUIRE_SOFTWARE", "1"},
        {"WOTEX_THREAD_HOST", host},
        {"WOTEX_THREAD_RCP", executables.rcp},
        {"WOTEX_THREAD_CONTRACT_DRIVER", executables.contract_driver},
        {"WOTEX_THREAD_DATASET_SEED", executables.dataset_seed},
        {"WOTEX_THREAD_FLOW_HOST", executables.flow_host},
        {"WOTEX_THREAD_CASE_RESULTS", cases}
      ] ++
        Enum.flat_map(~w(MIX_HOME HEX_HOME WOTEX_PATH_DEPS ERL_FLAGS), fn key ->
          case System.get_env(key) do
            nil -> []
            value -> [{key, value}]
          end
        end) ++ extra

    step = %{
      id: :software_suite,
      executable: mix,
      cwd: environment.project_root,
      args: arguments,
      env: env,
      timeout_ms: @suite_timeout,
      output_bytes: @output_limit,
      cleanup_ms: 5_000
    }

    {status, bytes} = command_result(Command.run(guardian, step))
    log = Path.join(output, "#{lane}.log")
    :ok = File.write(log, bytes, [:exclusive])
    lines = if File.regular?(cases), do: File.read!(cases), else: ""

    %{
      "lane" => lane,
      "command" => ["mix" | arguments],
      "seed" => 0,
      "exit_status" => status,
      "log_sha256" => digest(log),
      "cases_sha256" => if(File.regular?(cases), do: digest(cases), else: nil),
      "evaluation" => evaluate(inventory["required"], lines)
    }
  end

  defp command_result({:ok, %{output: bytes, exit_status: status}}), do: {status, bytes}
  defp command_result({:error, _, %{output: bytes, exit_status: status}}), do: {status, bytes}

  # Any process still executing a workspace binary after the lanes is an owned survivor.
  defp cleanup(workspace, environment) do
    prefix = workspace <> "/"
    proc = environment.proc

    survivors =
      for entry <- File.ls!(proc),
          entry =~ ~r/\A\d+\z/,
          {:ok, target} <- [File.read_link(Path.join([proc, entry, "exe"]))],
          String.starts_with?(target, prefix),
          do: String.to_integer(entry)

    Enum.each(
      survivors,
      &System.cmd("/bin/kill", ["-KILL", Integer.to_string(&1)],
        stderr_to_stdout: true,
        env: cleared_environment()
      )
    )

    %{"survivors" => length(survivors)}
  end

  defp cleared_environment, do: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)

  defp source_identity(environment) do
    root = environment.project_root

    trees =
      Map.new(~w(lib priv/openthread test priv/fixtures), fn path ->
        {:ok, hash} = Source.tree_digest(Path.join(root, path))
        {path, hash}
      end)

    Map.merge(trees, Map.new(~w(mix.exs mix.lock), &{&1, digest(Path.join(root, &1))}))
  end

  defp toolchain do
    release = System.otp_release()
    otp_file = Path.join([to_string(:code.root_dir()), "releases", release, "OTP_VERSION"])

    %{
      "elixir" => System.version(),
      "otp" => String.trim(File.read!(otp_file)),
      "architecture" => to_string(:erlang.system_info(:system_architecture))
    }
  end

  defp digest(path) do
    case Source.digest(path) do
      {:ok, hash} -> hash
      _ -> nil
    end
  end
end
