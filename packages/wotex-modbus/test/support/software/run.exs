defmodule Wotex.Modbus.SoftwareRun do
  @moduledoc false

  alias Wotex.Modbus.{SoftwareCommand, SoftwareManifest}

  @test_argv [
    "test",
    "--include",
    "interop",
    "--include",
    "software",
    "--exclude",
    "hardware",
    "--seed",
    "731942"
  ]
  @limit 16_777_216

  @spec run(map(), map()) :: :ok
  def run(context, manifest) do
    lane = Path.join(context.workspace, "run-#{System.system_time(:nanosecond)}")
    File.mkdir!(lane)

    context = Map.merge(context, %{lane: lane, manifest: manifest})

    result =
      try do
        context =
          Map.merge(context, %{
            docker: tool("docker"),
            run_id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
          })

        execute(context, evidence(context))
      rescue
        _ ->
          %{
            "schema" => "wotex.modbus.software@2",
            "status" => "failed",
            "failure" => "software_initialization_failed",
            "cleanup" => "unverified",
            "owned_containers_after" => "unverified"
          }
      end

    SoftwareManifest.write(Path.join(lane, "result.json"), result)
    Mix.shell().info("software evidence: #{Path.join(lane, "result.json")}")
    unless result["status"] == "passed", do: Mix.raise("software_fixture_failed")
    :ok
  end

  @spec start_peer(map()) :: port()
  def start_peer(context) do
    watcher = watch_peer(context)
    deadline = System.monotonic_time(:millisecond) + 15_000

    peer_options =
      case Map.fetch(context, :peer_command) do
        {:ok, {executable, _}} -> ["--entrypoint", executable]
        :error -> []
      end

    peer_arguments =
      case Map.fetch(context, :peer_command) do
        {:ok, {_, arguments}} -> arguments
        :error -> []
      end

    arguments =
      [
        "create",
        "--rm",
        "--pull=never",
        "--label",
        "wotex.modbus.run=" <> context.run_id,
        "--cidfile",
        cid_path(context),
        "--read-only",
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges",
        "--pids-limit=32",
        "--memory=256m",
        "-p",
        "127.0.0.1::1502"
      ] ++ peer_options ++ Enum.concat([context.manifest["image_id"]], peer_arguments)

    try do
      {:ok, _, 0} = command(context, arguments, 5000)
      cid = container(context)
      if before_start = Map.get(context, :before_start), do: before_start.(cid)

      port =
        SoftwareCommand.open(context.guardian, context.docker, ["start", "--attach", cid],
          cd: context.root,
          timeout: 240_000,
          cleanup: 2000
        )

      Process.put({__MODULE__, :watcher, port}, watcher)
      Process.put({__MODULE__, :ready_deadline, port}, deadline)
      port
    rescue
      error ->
        send(watcher, :cleanup)
        reraise error, __STACKTRACE__
    end
  end

  @spec watch_peer(map()) :: pid()
  def watch_peer(context) do
    owner = self()

    spawn(fn ->
      monitor = Process.monitor(owner)

      receive do
        :cleaned ->
          Process.demonitor(monitor, [:flush])

        :cleanup ->
          Process.demonitor(monitor, [:flush])
          recover_peer(context)

        {:DOWN, ^monitor, :process, ^owner, _} ->
          recover_peer(context)
      end
    end)
  end

  @spec ready(port(), pos_integer()) :: {:ok, binary()} | {:error, atom()}
  def ready(port, timeout \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    deadline = min(deadline, Process.delete({__MODULE__, :ready_deadline, port}) || deadline)
    ready_output(port, "", deadline)
  end

  @spec container(map()) :: String.t()
  def container(context) do
    value = String.trim(File.read!(cid_path(context)))
    unless Regex.match?(~r/\A[0-9a-f]{64}\z/, value), do: Mix.raise("invalid_owned_container")

    {:ok, label, 0} =
      command(
        context,
        ["inspect", value, "--format", "{{index .Config.Labels \"wotex.modbus.run\"}}"],
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
      {:ok, initial} = ready(peer, Map.get(context, :ready_timeout, 15_000))
      Process.put(state_key, initial)
      cid = container(context)
      port = endpoint(context, cid)

      env = [
        {"WOTEX_REQUIRE_SOFTWARE", "1"},
        {"WOTEX_MODBUS_INTEROP_HOST", "127.0.0.1"},
        {"WOTEX_MODBUS_INTEROP_PORT", Integer.to_string(port)},
        {"WOTEX_MODBUS_SOFTWARE_EVIDENCE", context.lane},
        {"WOTEX_MODBUS_SOFTWARE_WORKSPACE", context.workspace}
      ]

      {test_executable, test_arguments, test_options} =
        Map.get_lazy(context, :test_command, fn -> {tool("mix"), @test_argv, []} end)

      options =
        Keyword.merge(
          [
            cd: context.root,
            timeout: 180_000,
            cleanup: 2000,
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
      if Port.info(peer), do: Port.close(peer)
      if watcher = Process.delete({__MODULE__, :watcher, peer}), do: send(watcher, :cleanup)
    end
  end

  defp finish(context, peer, initial, evidence) do
    deadline = System.monotonic_time(:millisecond) + 5000
    result = cleanup(context, peer, initial, evidence, deadline)

    logs =
      Path.wildcard(Path.join(context.lane, "*.log"))
      |> Map.new(&{Path.basename(&1), SoftwareManifest.digest(&1)})

    Map.put(result, "logs_sha256", logs)
  end

  defp cleanup(context, peer, initial, evidence, deadline) do
    context = Map.put(context, :docker, Map.get(context, :cleanup_docker, context.docker))
    cid = container(context)
    stop = command(context, ["stop", "--time", "1", cid], budget(deadline))
    {output, code} = command_result(SoftwareCommand.await(peer, budget(deadline), @limit, initial))
    File.write!(Path.join(context.lane, "peer.log"), output)
    cleanup = Enum.flat_map(String.split(output, "\n", trim: true), &cleanup_event/1)

    diagnostics =
      not String.contains?(output, [
        "ERROR: AddressSanitizer",
        "runtime error:",
        "LeakSanitizer",
        "DEADLYSIGNAL"
      ])

    removed = removed?(context, cid, deadline)

    if removed do
      if watcher = Process.delete({__MODULE__, :watcher, peer}), do: send(watcher, :cleaned)
    end

    clean =
      match?({:ok, _, 0}, stop) and code == 0 and valid_cleanup?(cleanup) and diagnostics and
        removed

    Map.merge(evidence, %{
      "peer_exit_code" => code,
      "peer_cleanup" => cleanup,
      "native_sanitizers" => %{
        "address" => diagnostics,
        "undefined" => diagnostics,
        "leak" => diagnostics
      },
      "owned_containers_after" => if(removed, do: 0, else: "unverified"),
      "cleanup" => if(clean, do: "passed", else: "failed"),
      "status" => if(clean and evidence["status"] == "passed", do: "passed", else: "failed")
    })
  rescue
    _ ->
      if Port.info(peer), do: Port.close(peer)

      Map.merge(evidence, %{
        "status" => "failed",
        "cleanup" => "unverified",
        "owned_containers_after" => "unverified"
      })
  end

  defp recover_peer(context) do
    deadline = System.monotonic_time(:millisecond) + 5000
    recover_until(context, deadline, false)
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
          "label=wotex.modbus.run=" <> context.run_id
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
             ["inspect", id, "--format", "{{index .Config.Labels \"wotex.modbus.run\"}}"],
             budget(deadline)
           ),
         true <- String.trim(label) == context.run_id do
      command(context, ["rm", "--force", id], budget(deadline))
    end
  end

  defp recover_again(context, deadline, observed) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(20)
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

  defp endpoint(context, cid) do
    {:ok, value, 0} = command(context, ["port", cid, "1502/tcp"], 3000)

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
    if String.contains?(output, "{\"event\":\"ready\",\"port\":1502}\n") do
      {:ok, output}
    else
      receive do
        {^port, {:data, bytes}} when byte_size(bytes) + byte_size(output) <= @limit ->
          ready_output(port, output <> bytes, deadline)

        {^port, {:data, _}} ->
          {:error, :peer_output_limit}

        {^port, {:exit_status, _}} ->
          {:error, :peer_exit}
      after
        max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :peer_readiness_timeout}
      end
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
        :error -> ["mix" | @test_argv]
      end

    %{
      "schema" => "wotex.modbus.software@2",
      "status" => "failed",
      "subject" => identity,
      "dependencies" => dependencies,
      "dependency_mode" =>
        if(System.get_env("WOTEX_PATH_DEPS") == "1", do: "path", else: "released"),
      "fixture_image" => context.manifest["image_id"],
      "manifest_sha256" =>
        SoftwareManifest.digest(Path.join(context.workspace, "peer-manifest.json")),
      "binary_hashes" => context.manifest["native"]["binary_hashes"],
      "toolchain" => %{
        "elixir" => System.version(),
        "otp" => otp_version()
      },
      "command" => command,
      "seed" => 731_942,
      "lanes" => ["independent-stack", "malformed-peer", "injected-contract"],
      "subscription_cycles" => %{
        "status" => "inapplicable",
        "reason" => "profile declares no subscriptions"
      }
    }
  end

  defp measurements(context, evidence) do
    Enum.reduce(
      ["sequential", "cycles", "concurrency", "failures", "test-results"],
      evidence,
      fn name, current ->
        Map.put(current, name, SoftwareManifest.read(Path.join(context.lane, name <> ".json")))
      end
    )
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
    commit = if clean, do: git_value(command.(["rev-parse", "HEAD"])), else: nil
    tree = if clean, do: git_value(command.(["rev-parse", "HEAD^{tree}"])), else: nil
    Map.merge(identity, %{"source_commit" => commit, "source_tree" => tree})
  end

  defp git_value({:ok, value, 0}), do: String.trim(value)
  defp git_value(_), do: nil

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
    do: Enum.all?(["open_sockets", "contexts", "mappings", "result"], &(event[&1] == 0))

  defp valid_cleanup?(_), do: false

  defp command(context, arguments, timeout),
    do:
      SoftwareCommand.run(context.guardian, context.docker, arguments,
        cd: context.root,
        timeout: timeout,
        cleanup: 100
      )

  defp command_result({:ok, output, status}), do: {output, status}
  defp command_result(_), do: {"", "unverified"}
  defp budget(deadline), do: max(min(deadline - System.monotonic_time(:millisecond) - 200, 2000), 1)
  defp cid_path(context), do: Path.join(context.lane, "owned-container.id")
  defp tool(name), do: System.find_executable(name) || Mix.raise("required_tool_missing")
end
