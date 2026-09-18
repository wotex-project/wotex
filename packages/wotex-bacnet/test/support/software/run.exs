defmodule Wotex.BACnet.SoftwareRun do
  @moduledoc false

  alias Wotex.BACnet.{SoftwareCommand, SoftwareManifest}

  @test_argv [
    "test",
    "--include",
    "interop",
    "--include",
    "software",
    "--exclude",
    "hardware",
    "--seed",
    "470127"
  ]
  @limit 1_048_576

  @terminal_argv [
    "test",
    "test/interop/cstack/shutdown_test.exs",
    "--include",
    "peer_shutdown",
    "--seed",
    "470127"
  ]

  @spec run(map(), map()) :: :ok
  def run(context, manifest) do
    cohort = Path.join(context.workspace, "run-#{System.system_time(:nanosecond)}")
    File.mkdir!(cohort)

    lanes =
      for variant <- ["normal", "sanitizer"], suite <- [:shared, :terminal], into: %{} do
        name = variant <> "-" <> Atom.to_string(suite)

        selected =
          Map.merge(context, %{lane: Path.join(cohort, name), variant: variant, suite: suite})

        {name, run_case(selected, manifest)}
      end

    result = %{
      "schema" => "wotex.bacnet.software-cohort@1",
      "status" =>
        if(Enum.all?(lanes, fn {_, value} -> value["status"] == "passed" end),
          do: "passed",
          else: "failed"
        ),
      "lanes" => lanes
    }

    SoftwareManifest.write(Path.join(cohort, "result.json"), result)
    Mix.shell().info("software evidence: #{Path.join(cohort, "result.json")}")
    unless result["status"] == "passed", do: Mix.raise("software_fixture_failed")
    :ok
  end

  @spec run_case(map(), map()) :: map()
  def run_case(context, manifest) do
    File.mkdir!(context.lane)

    context = Map.put(context, :manifest, manifest)

    result =
      try do
        context =
          Map.merge(context, %{
            docker: tool("docker"),
            run_id:
              Map.get_lazy(context, :run_id, fn ->
                Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
              end)
          })

        result = execute(context, evidence(context))

        if SoftwareManifest.identity(context.root)["source_sha256"] ==
             result["subject"]["source_sha256"],
           do: result,
           else:
             Map.merge(result, %{"status" => "failed", "failure" => "source_changed_during_run"})
      rescue
        _ ->
          %{
            "schema" => "wotex.bacnet.software@1",
            "status" => "failed",
            "failure" => "software_initialization_failed",
            "cleanup" => "unverified",
            "owned_containers_after" => "unverified"
          }
      end

    SoftwareManifest.write(Path.join(context.lane, "result.json"), result)
    result
  end

  @spec start_peer(map()) :: port()
  def start_peer(context) do
    watcher = watch_peer(context)
    deadline = System.monotonic_time(:millisecond) + 10_000

    peer_options =
      case Map.fetch(context, :peer_command) do
        {:ok, {executable, _}} ->
          ["--entrypoint", executable]

        :error ->
          ["--entrypoint", "/" <> Map.get(context, :variant, "sanitizer") <> "/wotex-bacnet-peer"]
      end

    peer_arguments =
      case Map.fetch(context, :peer_command) do
        {:ok, {_, arguments}} -> arguments
        :error -> ["eth0", "47808", "47809", "600000"]
      end

    arguments =
      [
        "create",
        "--rm",
        "--pull=never",
        "--label",
        "wotex.bacnet.run=" <> context.run_id,
        "--cidfile",
        cid_path(context),
        "--read-only",
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges",
        "--pids-limit=32",
        "--memory=256m",
        "-p",
        "127.0.0.1::47808/udp",
        "-p",
        "127.0.0.1::47809/udp",
        "-e",
        "ASAN_OPTIONS=detect_leaks=1:abort_on_error=1",
        "-e",
        "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
      ] ++ peer_options ++ Enum.concat([context.manifest["image_id"]], peer_arguments)

    try do
      {:ok, _, 0} = command(context, arguments, 5000)
      cid = container(context)
      Process.put({__MODULE__, :cid, context.lane}, cid)
      if before_start = Map.get(context, :before_start), do: before_start.(cid)

      port =
        SoftwareCommand.open(context.guardian, context.docker, ["start", "--attach", cid],
          cd: context.root,
          timeout: 240_000,
          cleanup: 100,
          limit: @limit
        )

      Process.put({__MODULE__, :watcher, port}, watcher)
      Process.put({__MODULE__, :ready_deadline, port}, deadline)
      port
    rescue
      error ->
        cleanup_watcher(watcher, System.monotonic_time(:millisecond) + 1000)
        Process.delete({__MODULE__, :cid, context.lane})
        reraise error, __STACKTRACE__
    end
  end

  @spec watch_peer(map()) :: pid()
  def watch_peer(context) do
    owner = self()

    spawn(fn ->
      monitor = Process.monitor(owner)
      watch(context, owner, monitor, nil)
    end)
  end

  defp watch(context, owner, monitor, deadline) do
    receive do
      {:cleanup_deadline, deadline} ->
        watch(context, owner, monitor, deadline)

      :cleaned ->
        Process.demonitor(monitor, [:flush])

      :cleanup ->
        Process.demonitor(monitor, [:flush])
        recover_peer(context, deadline)

      {:cleanup, caller, reference, requested_deadline} ->
        Process.demonitor(monitor, [:flush])
        result = recover_peer(context, deadline || requested_deadline)
        send(caller, {:cleanup_finished, reference, result})

      {:DOWN, ^monitor, :process, ^owner, _} ->
        recover_peer(context, deadline)
    end
  end

  defp cleanup_watcher(watcher, deadline) do
    reference = make_ref()
    send(watcher, {:cleanup, self(), reference, deadline})

    receive do
      {:cleanup_finished, ^reference, result} -> result
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :unverified
    end
  end

  @spec ready(port(), pos_integer()) :: {:ok, binary()} | {:error, atom()}
  def ready(port, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    deadline = min(deadline, Process.delete({__MODULE__, :ready_deadline, port}) || deadline)
    ready_output(port, "", deadline)
  end

  @spec container(map()) :: String.t()
  def container(context) do
    case Process.get({__MODULE__, :cid, context.lane}) do
      nil -> verify_container(context)
      value -> value
    end
  end

  defp verify_container(context) do
    value = String.trim(File.read!(cid_path(context)))
    unless Regex.match?(~r/\A[0-9a-f]{64}\z/, value), do: Mix.raise("invalid_owned_container")

    {:ok, label, 0} =
      command(
        context,
        ["inspect", value, "--format", "{{index .Config.Labels \"wotex.bacnet.run\"}}"],
        1000
      )

    unless String.trim(label) == context.run_id, do: Mix.raise("invalid_owned_container")
    value
  end

  defp execute(context, evidence) do
    peer = start_peer(context)
    state_key = {__MODULE__, peer}
    Process.put(state_key, "")

    try do
      {:ok, initial} = ready(peer, Map.get(context, :ready_timeout, 10_000))
      Process.put(state_key, initial)
      cid = container(context)
      port = endpoint(context, cid, "47808/udp")
      control_port = endpoint(context, cid, "47809/udp")
      :ok = control_ready(control_port)

      env = [
        {"WOTEX_REQUIRE_SOFTWARE", "1"},
        {"WOTEX_BACNET_INTEROP_PORT", Integer.to_string(port)},
        {"WOTEX_BACNET_RESULTS_DIR", context.lane},
        {"WOTEX_BACNET_CONTROL_PORT", Integer.to_string(control_port)},
        {"WOTEX_BACNET_SOFTWARE_WORKSPACE", context.workspace}
      ]

      {test_executable, test_arguments, test_options} =
        Map.get_lazy(context, :test_command, fn -> {tool("mix"), test_arguments(context), []} end)

      options =
        Keyword.merge(
          [
            cd: context.root,
            timeout: 180_000,
            cleanup: 100,
            limit: @limit,
            env: env
          ],
          test_options
        )

      test = SoftwareCommand.run(context.guardian, test_executable, test_arguments, options)

      {output, status} = command_result(test)
      File.write!(Path.join(context.lane, "tests.log"), output)

      evidence =
        Map.merge(evidence, %{
          "test_exit_code" => status,
          "status" => if(status == 0, do: "passed", else: "failed")
        })

      evidence = if status == 0, do: measurements(context, evidence), else: evidence
      finish(context, peer, Process.get(state_key), evidence)
    rescue
      _ ->
        finish(
          context,
          peer,
          Process.get(state_key),
          Map.put(evidence, "failure", "software_setup_or_execution_failed")
        )
    after
      Process.delete(state_key)
      Process.delete({__MODULE__, :cid, context.lane})
      Process.delete({__MODULE__, :peer_exit, peer})

      try do
        Port.close(peer)
      rescue
        ArgumentError -> :ok
      end

      if watcher = Process.delete({__MODULE__, :watcher, peer}), do: send(watcher, :cleanup)
    end
  end

  defp finish(context, peer, initial, evidence) do
    started = System.monotonic_time(:millisecond)
    deadline = started + 1000

    if watcher = Process.get({__MODULE__, :watcher, peer}),
      do: send(watcher, {:cleanup_deadline, deadline})

    result = cleanup(context, peer, initial, evidence, deadline)
    result = Map.put(result, "local_cleanup_ms", System.monotonic_time(:millisecond) - started)

    logs =
      Path.wildcard(Path.join(context.lane, "*.log"))
      |> Map.new(&{Path.basename(&1), SoftwareManifest.digest(&1)})

    faults =
      Path.wildcard(Path.join(context.lane, "faults/**/*.{json,log}"))
      |> Map.new(&{Path.relative_to(&1, context.lane), SoftwareManifest.digest(&1)})

    Map.merge(result, %{"logs_sha256" => logs, "fault_artifacts_sha256" => faults})
  end

  defp cleanup(context, peer, initial, evidence, deadline) do
    context = Map.put(context, :docker, Map.get(context, :cleanup_docker, context.docker))
    cid = container(context)
    if before_stop = Map.get(context, :before_stop), do: before_stop.(cid)
    stop = command(context, ["kill", "--signal", "TERM", cid], budget(deadline))
    {stop_output, stop_code} = command_result(stop)
    File.write!(Path.join(context.lane, "stop.log"), stop_output)

    unless valid_readiness?(initial) do
      {forced, _} = command_result(command(context, ["rm", "--force", cid], budget(deadline)))
      File.write!(Path.join(context.lane, "forced-removal.log"), forced)
    end

    observation = observe_exit(context, peer, initial, cid, deadline)

    {output, code} = command_result(observation)

    File.write!(Path.join(context.lane, "peer.log"), output)
    cleanup = Enum.flat_map(String.split(output, "\n", trim: true), &cleanup_event/1)

    diagnostics = diagnostics_clean?(output)

    removed = removed?(context, cid, deadline)
    acknowledge_cleanup(peer, removed)
    clean = clean_cleanup?(code, cleanup, diagnostics, removed)

    Map.merge(evidence, %{
      "peer_exit_code" => code,
      "peer_observation" => observation_status(observation),
      "stop_exit_code" => stop_code,
      "peer_cleanup" => cleanup,
      "native_sanitizers" => sanitizer_result(context, diagnostics),
      "owned_containers_after" => if(removed, do: 0, else: "unverified"),
      "cleanup" => if(clean, do: "passed", else: "failed"),
      "status" => if(clean and evidence["status"] == "passed", do: "passed", else: "failed")
    })
  rescue
    _ ->
      try do
        Port.close(peer)
      rescue
        ArgumentError -> :ok
      end

      Map.merge(evidence, %{
        "status" => "failed",
        "cleanup" => "unverified",
        "owned_containers_after" => "unverified"
      })
  end

  defp diagnostics_clean?(output) do
    not String.contains?(output, [
      "ERROR: AddressSanitizer",
      "runtime error:",
      "LeakSanitizer",
      "DEADLYSIGNAL"
    ])
  end

  defp acknowledge_cleanup(peer, true) do
    if watcher = Process.delete({__MODULE__, :watcher, peer}), do: send(watcher, :cleaned)
  end

  defp acknowledge_cleanup(_, false), do: :ok

  defp clean_cleanup?(code, cleanup, diagnostics, removed),
    do: code == 0 and valid_cleanup?(cleanup) and diagnostics and removed

  defp sanitizer_result(context, diagnostics) do
    if Map.get(context, :variant, "sanitizer") == "sanitizer" and
         not Map.has_key?(context, :peer_command) do
      %{
        "instrumented" => true,
        "address" => diagnostics,
        "undefined" => diagnostics,
        "leak" => diagnostics
      }
    else
      %{"instrumented" => false}
    end
  end

  defp recover_peer(context, deadline) do
    deadline = deadline || System.monotonic_time(:millisecond) + 1000
    result = recover_until(context, deadline, false)

    SoftwareManifest.write(Path.join(context.lane, "owner-loss-cleanup.json"), %{
      "status" => if(result == :ok, do: "passed", else: "unverified"),
      "owned_containers_after" => if(result == :ok, do: 0, else: "unverified")
    })

    result
  end

  defp observe_exit(context, peer, initial, cid, deadline) do
    case Process.delete({__MODULE__, :peer_exit, peer}) do
      nil ->
        first =
          SoftwareCommand.poll(
            peer,
            max(deadline - 150 - System.monotonic_time(:millisecond), 0),
            @limit,
            initial
          )

        case first do
          {:ok, _, _} ->
            first

          {:error, reason, :unverified, output} ->
            events = Enum.flat_map(String.split(output, "\n", trim: true), &cleanup_event/1)

            if reason == :command_deadline and not valid_cleanup?(events) do
              {forced, _} =
                command_result(command(context, ["rm", "--force", cid], budget(deadline)))

              File.write!(Path.join(context.lane, "forced-removal.log"), forced)
            end

            SoftwareCommand.observe(
              peer,
              max(deadline - 200 - System.monotonic_time(:millisecond), 0),
              @limit,
              output
            )
        end

      status ->
        {:ok, initial, status}
    end
  end

  defp recover_until(context, deadline, observed) do
    result =
      command(
        context,
        [
          "ps",
          "--all",
          "--quiet",
          "--no-trunc",
          "--filter",
          "label=wotex.bacnet.run=" <> context.run_id
        ],
        budget(deadline)
      )

    case result do
      {:ok, bytes, 0} ->
        ids = String.split(bytes, "\n", trim: true)

        Enum.each(ids, &recover_container(context, &1, deadline))

        if observed and ids == [] do
          :ok
        else
          recover_again(context, deadline, observed or ids != [])
        end

      _ ->
        recover_again(context, deadline, observed)
    end
  rescue
    _ -> :unverified
  end

  defp recover_container(context, id, deadline) do
    with true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, id),
         {:ok, label, 0} <-
           command(
             context,
             ["inspect", id, "--format", "{{index .Config.Labels \"wotex.bacnet.run\"}}"],
             budget(deadline)
           ),
         true <- String.trim(label) == context.run_id do
      command(context, ["rm", "--force", id], budget(deadline))
    end
  end

  defp recover_again(context, deadline, observed) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(min(20, max(deadline - System.monotonic_time(:millisecond), 0)))
      recover_until(context, deadline, observed)
    else
      :unverified
    end
  end

  defp removed?(context, cid, deadline) do
    case command(
           context,
           ["ps", "--all", "--quiet", "--no-trunc", "--filter", "id=" <> cid],
           budget(deadline)
         ) do
      {:ok, output, 0} when output in ["", "\n"] ->
        true

      {:ok, _, 0} ->
        command(context, ["rm", "--force", cid], budget(deadline))

        match?(
          {:ok, "", 0},
          command(
            context,
            ["ps", "--all", "--quiet", "--no-trunc", "--filter", "id=" <> cid],
            budget(deadline)
          )
        )

      _ ->
        false
    end
  end

  defp endpoint(context, cid, service) do
    {:ok, value, 0} = command(context, ["port", cid, service], 1000)

    case Regex.run(~r/\A127\.0\.0\.1:([0-9]+)\n?\z/, value) do
      [_, port] ->
        port = String.to_integer(port)
        if port not in 1..65_535, do: Mix.raise("invalid_owned_endpoint")
        port

      _ ->
        Mix.raise("invalid_owned_endpoint")
    end
  end

  defp ready_output(port, output, deadline) do
    Process.put({__MODULE__, port}, output)

    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :peer_readiness_timeout}

      String.contains?(output, "\n") ->
        if valid_readiness?(output), do: {:ok, output}, else: {:error, :invalid_peer_readiness}

      byte_size(output) > 4096 ->
        {:error, :peer_output_limit}

      true ->
        receive do
          {^port, {:data, bytes}} when byte_size(bytes) + byte_size(output) <= @limit ->
            ready_output(port, output <> bytes, deadline)

          {^port, {:data, _}} ->
            {:error, :peer_output_limit}

          {^port, {:exit_status, status}} ->
            Process.put({__MODULE__, :peer_exit, port}, status)
            {:error, :peer_exit}
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            {:error, :peer_readiness_timeout}
        end
    end
  end

  defp control_ready(port) do
    nonce = rem(System.unique_integer([:positive]), 4_294_967_296)
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    try do
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, "stats #{nonce}\n")
      {:ok, {{127, 0, 0, 1}, ^port, bytes}} = :gen_udp.recv(socket, 0, 1000)
      true = byte_size(bytes) <= 2048

      %{
        "version" => 1,
        "nonce" => ^nonce,
        "pid" => pid,
        "active_subscribers" => 0,
        "active_invoke_ids" => 0
      } = Jason.decode!(bytes)

      true = is_integer(pid) and pid > 0
      :ok
    after
      :gen_udp.close(socket)
    end
  end

  defp valid_readiness?(output) do
    case String.split(output, "\n", parts: 2) do
      [line, _] when byte_size(line) <= 4096 ->
        match?(
          {:ok, %{"ready" => true, "pid" => pid, "device_instance" => 123} = value}
          when is_integer(pid) and pid > 0 and map_size(value) == 3,
          Jason.decode(line)
        )

      _ ->
        false
    end
  end

  defp evidence(context) do
    identity = source_identity(context, context.root)

    dependencies =
      Map.new(Mix.Project.deps_paths(), fn {name, path} ->
        {Atom.to_string(name), SoftwareManifest.identity(path)}
      end)

    command =
      case Map.fetch(context, :test_command) do
        {:ok, {executable, arguments, _}} -> [Path.basename(executable) | arguments]
        :error -> ["mix" | test_arguments(context)]
      end

    %{
      "schema" => "wotex.bacnet.software@1",
      "status" => "failed",
      "subject" => identity,
      "dependencies" => dependencies,
      "dependency_mode" =>
        if(System.get_env("WOTEX_PATH_DEPS") == "1", do: "path", else: "released"),
      "fixture_image" => context.manifest["image_id"],
      "manifest_sha256" =>
        SoftwareManifest.digest(Path.join(context.workspace, "peer-manifest.json")),
      "binary_hashes" => context.manifest["native"]["binary_hashes"],
      "native_cases" => %{
        "execution" => "verified_image_build",
        "names" => context.manifest["native_cases"]
      },
      "toolchain" => %{
        "elixir" => System.version(),
        "otp" => otp_version()
      },
      "command" => command,
      "seed" => 470_127,
      "lanes" => ["independent-stack", "malformed-peer", "injected-contract"],
      "variant" => Map.get(context, :variant, "sanitizer"),
      "suite" => Atom.to_string(Map.get(context, :suite, :shared)),
      "requirements" => [
        "WBA-C09",
        "WBA-S01",
        "WBA-S02",
        "WBA-S03",
        "WBA-S03a",
        "WBA-S04",
        "WBA-S05",
        "WBA-V13",
        "WBA-V14"
      ]
    }
  end

  defp measurements(context, evidence) do
    defaults =
      case Map.get(context, :suite, :shared) do
        :shared -> ["WBA-ST01", "WBA-ST02", "WBA-ST03", "test-results"]
        :terminal -> ["WBA-CP25", "test-results"]
      end

    measured =
      Enum.reduce(
        Map.get(context, :measurements, defaults),
        evidence,
        fn name, current ->
          Map.put(current, name, SoftwareManifest.read(Path.join(context.lane, name <> ".json")))
        end
      )

    if Map.has_key?(context, :measurements), do: measured, else: verify_cases(context, measured)
  end

  defp verify_cases(context, evidence) do
    %{"schema" => "wotex.bacnet.exunit@1", "cases" => cases} = evidence["test-results"]
    true = is_list(cases) and cases != []
    true = Enum.all?(cases, &(&1["outcome"] in ["passed", "excluded"]))
    files = evidence["subject"]["source_files_sha256"]
    true = Enum.all?(cases, &Map.has_key?(files, &1["source"]))

    executed =
      cases
      |> Enum.filter(&(&1["outcome"] == "passed"))
      |> Enum.flat_map(& &1["requirement_ids"])
      |> Enum.uniq()
      |> Enum.sort()

    required =
      if Map.get(context, :suite, :shared) == :terminal do
        ["WBA-CP25"]
      else
        for(
          number <- Enum.to_list(2..9) ++ Enum.to_list(11..24),
          do: "WBA-CP" <> String.pad_leading(Integer.to_string(number), 2, "0")
        ) ++
          [
            "WBA-ST01",
            "WBA-ST02",
            "WBA-ST03",
            "WBA-RF01",
            "WBA-RF02",
            "WBA-RF03",
            "WBA-RF04",
            "WBA-RF05",
            "WBA-S03a",
            "WBA-N04",
            "WBA-C09",
            "WBA-V13",
            "WBA-V14"
          ]
      end

    true = Enum.all?(required, &(&1 in executed))
    Map.merge(evidence, %{"required_case_ids" => required, "executed_requirement_ids" => executed})
  end

  defp source_identity(context, root) do
    identity = SoftwareManifest.identity(root)
    paths = Map.keys(identity["source_files_sha256"])
    git = tool("git")

    command = fn args ->
      SoftwareCommand.run(context.guardian, git, ["-C", root | args],
        cd: context.root,
        timeout: 5000
      )
    end

    clean = match?({:ok, _, 0}, command.(["diff", "--quiet", "HEAD", "--" | paths]))

    tracked =
      case command.(["ls-files", "-z", "--" | paths]) do
        {:ok, bytes, 0} -> String.split(bytes, <<0>>, trim: true)
        _ -> []
      end

    clean = clean and Enum.all?(paths, &(&1 in tracked))

    {commit, tree} =
      if clean,
        do: SoftwareManifest.git_identity(command.(["rev-parse", "HEAD", "HEAD^{tree}"])),
        else: {nil, nil}

    Map.merge(identity, %{"source_commit" => commit, "source_tree" => tree})
  end

  defp otp_version do
    path =
      Path.join([List.to_string(:code.root_dir()), "releases", System.otp_release(), "OTP_VERSION"])

    String.trim(File.read!(path))
  end

  defp cleanup_event(line) do
    case Jason.decode(line) do
      {:ok, %{"event" => "cleanup"} = event} -> [event]
      _ -> []
    end
  end

  defp valid_cleanup?([event]),
    do:
      Enum.all?(
        [
          "open_sockets",
          "object_subscribers",
          "property_subscribers",
          "active_invoke_ids",
          "analog_outputs",
          "result"
        ],
        &(event[&1] == 0)
      )

  defp valid_cleanup?(_), do: false

  defp command(_, _, 0), do: {:error, :command_deadline, :unverified}

  defp command(context, arguments, timeout) do
    port =
      SoftwareCommand.open(context.guardian, context.docker, arguments,
        cd: context.root,
        timeout: timeout,
        cleanup: 50,
        limit: @limit
      )

    SoftwareCommand.await(port, timeout + 100, @limit)
  rescue
    ArgumentError -> {:error, :command_unavailable, :unverified}
  end

  defp command_result({:ok, output, status}), do: {output, status}
  defp command_result({:error, _, :unverified, output}), do: {output, "unverified"}
  defp command_result(_), do: {"", "unverified"}
  defp observation_status({:ok, _, _}), do: "complete"
  defp observation_status({:error, reason, :unverified, _}), do: Atom.to_string(reason)

  defp test_arguments(context),
    do: if(Map.get(context, :suite) == :terminal, do: @terminal_argv, else: @test_argv)

  defp budget(deadline), do: max(min(deadline - System.monotonic_time(:millisecond) - 50, 200), 0)
  defp cid_path(context), do: Path.join(context.lane, "owned-container.id")
  defp tool(name), do: System.find_executable(name) || Mix.raise("required_tool_missing")
end
