defmodule Wotex.OPCUA.Native.Software do
  @moduledoc """
  Builds and runs the explicit software acceptance lanes from a source checkout.

  `build/2` requires the checkout's peer lock, peer script and native sources.
  It builds the pinned native workspace under `WORKSPACE/native`, which runs the
  native CTest step, and a separate ASan/UBSan tree under `WORKSPACE/asan` from
  that workspace's SDK and OpenSSL prefixes. It then creates a peer virtual
  environment under `WORKSPACE/peer/venv` with
  `pip install --require-hashes --no-deps` from `test/interop/requirements.lock`,
  and a separate audit environment under `WORKSPACE/audit/venv` from
  `test/interop/audit-requirements.lock` the same way. It records both lock
  digests, the installed distributions and every executable digest in
  `WORKSPACE/software-build.json`. A non-empty directory without that manifest
  is rejected.

  `run/2` verifies the manifest against the current locks and executables. It
  starts the independent peer with a finite readiness deadline, then runs the
  interop and software ExUnit lanes with `WOTEX_REQUIRE_SOFTWARE=1`, native and
  sanitizer CTest, `mix deps.audit`, `mix hex.audit`, `pip-audit` over the peer
  lock, and the native source audit. `pip-audit` runs from the audit environment
  with `--require-hashes --disable-pip`, so it neither installs nor resolves
  anything and exits nonzero on a known vulnerability. The native source audit
  requires the checkout's `priv/fixtures/native-sources-v1.json` to be the
  manifest compiled into the build, asks the OSV database
  (`https://api.osv.dev/v1/querybatch`, through `curl`) for advisories whose
  affected git ranges contain the pinned open62541, OpenSSL and vendored yyjson
  commits, and writes `WORKSPACE/native-audit.json` with those sources, the SDK
  patch digests and every advisory identifier; any advisory fails the lane.
  OSV matches only advisories that record git ranges. The run stops the peer it
  started and writes `WORKSPACE/software-run.json` with each lane's exit status
  and log digest. Any failed lane makes the run fail. The peer and audit
  environments are test infrastructure; no Python process is part of the runtime
  package. Loading this module performs no I/O.
  """

  alias Wotex.OPCUA.Native.{Build, Source, Workspace}

  @manifest "software-build.json"
  @report "software-run.json"
  @audit_report "native-audit.json"
  @lock "test/interop/requirements.lock"
  @audit_lock "test/interop/audit-requirements.lock"
  @peer "test/interop/secure_peer.py"
  @sources "priv/native/CMakeLists.txt"
  @native_sources "priv/fixtures/native-sources-v1.json"
  @osv "https://api.osv.dev/v1/querybatch"
  @tools [:python, :cmake, :ctest, :mix, :curl]
  @executables %{
    "native" => "native/output/bin/wotex_opcua_native",
    "guardian" => "native/output/bin/wotex_opcua_custody",
    "session_probe" => "native/native-build/wotex_opcua_session_probe",
    "paged_peer" => "native/native-build/wotex_opcua_paged_peer",
    "sanitizer_native" => "asan/wotex_opcua_native"
  }

  @doc """
  Builds the native, sanitizer and peer lanes into an explicit workspace.

  Options are `:root` (checkout, default current directory), `:tools` (explicit
  `python`, `cmake`, `ctest`, `mix` and `curl` paths), `:native_build` (a one-argument
  native build function) and `:command` (a runner receiving executable,
  arguments, options and a log path and returning an exit status).
  """
  @spec build(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(workspace, opts \\ []) do
    with {:ok, workspace} <- workspace(workspace),
         {:ok, root} <- fixtures(opts),
         {:ok, tools} <- tools(opts),
         :ok <- fresh(workspace) do
      for directory <- ~w(native asan peer audit logs),
          do: File.mkdir_p!(Path.join(workspace, directory))

      command = Keyword.get(opts, :command, &command/4)
      native = Path.join(workspace, "native")

      with {:ok, _} <- Keyword.get(opts, :native_build, &Build.run/1).(native),
           :ok <- sanitizer(command, tools, root, workspace),
           {:ok, freeze} <- environment(command, tools, root, workspace, "peer", @lock),
           {:ok, audit} <- environment(command, tools, root, workspace, "audit", @audit_lock),
           {:ok, artifacts} <- artifacts(workspace),
           {:ok, lock} <- Workspace.digest(Path.join(root, @lock)),
           {:ok, audit_lock} <- Workspace.digest(Path.join(root, @audit_lock)) do
        manifest = %{
          "format_version" => 1,
          "lock_sha256" => lock,
          "audit_lock_sha256" => audit_lock,
          "peer_distributions" => freeze,
          "audit_distributions" => audit,
          "artifacts" => artifacts
        }

        File.write!(Path.join(workspace, @manifest), Jason.encode_to_iodata!(manifest))
        {:ok, manifest}
      end
    end
  end

  @doc "Runs every software lane against a verified build workspace."
  @spec run(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workspace, opts \\ []) do
    with {:ok, workspace} <- workspace(workspace),
         {:ok, root} <- fixtures(opts),
         {:ok, tools} <- tools(opts),
         {:ok, manifest} <- verified(workspace, root) do
      command = Keyword.get(opts, :command, &command/4)
      peer_directory = Path.join(workspace, "peer/run-#{System.unique_integer([:positive])}")
      File.mkdir_p!(peer_directory)

      with {:ok, peer} <- start_peer(workspace, root, peer_directory, opts) do
        try do
          lanes(command, tools, root, workspace, manifest, peer_directory)
        after
          stop_peer(peer)
        end
      end
    end
  end

  defp lanes(command, tools, root, workspace, manifest, peer_directory) do
    artifact = &Path.join(workspace, Map.fetch!(@executables, &1))

    env = [
      {"MIX_ENV", "test"},
      {"WOTEX_REQUIRE_SOFTWARE", "1"},
      {"WOTEX_OPCUA_INTEROP_CONFIG", Path.join(peer_directory, "config.json")},
      {"WOTEX_OPCUA_NATIVE_EXECUTABLE", artifact.("native")},
      {"WOTEX_OPCUA_NATIVE_GUARDIAN", artifact.("guardian")},
      {"WOTEX_OPCUA_NATIVE_PROBE", artifact.("session_probe")},
      {"WOTEX_OPCUA_PAGED_PEER", artifact.("paged_peer")}
    ]

    lanes = [
      {"interop", tools.mix,
       ~w(test --include interop --include software --exclude hardware --seed 0), root, env},
      {"native_ctest", tools.ctest,
       ["--test-dir", Path.join(workspace, "native/native-build"), "--output-on-failure"], root,
       []},
      {"sanitizer_ctest", tools.ctest,
       ["--test-dir", Path.join(workspace, "asan"), "--output-on-failure"], root, []},
      {"deps_audit", tools.mix, ["deps.audit"], root, []},
      {"hex_audit", tools.mix, ["hex.audit"], root, []},
      {"pip_audit", Path.join(workspace, "audit/venv/bin/python"),
       [
         "-m",
         "pip_audit",
         "--require-hashes",
         "--disable-pip",
         "--progress-spinner",
         "off",
         "-r",
         Path.join(root, @lock)
       ], root, []}
    ]

    results =
      lanes
      |> Map.new(fn {name, executable, arguments, directory, lane_env} ->
        log = Path.join(workspace, "logs/#{name}.log")
        status = command.(executable, arguments, [cd: directory, env: lane_env], log)
        {:ok, digest} = Workspace.digest(log)
        {name, %{"exit_status" => status, "log_sha256" => digest}}
      end)
      |> Map.put("native_audit", native_audit(command, tools, root, workspace))

    report = %{
      "format_version" => 1,
      "build_manifest" => manifest,
      "lanes" => results
    }

    File.write!(Path.join(workspace, @report), Jason.encode_to_iodata!(report))

    case for({name, %{"exit_status" => status}} <- results, status != 0, do: name) do
      [] -> {:ok, report}
      failed -> {:error, {:software_lanes_failed, Enum.sort(failed)}}
    end
  end

  defp workspace(workspace) do
    case Build.arguments(["--workspace", workspace]) do
      {:ok, workspace} -> {:ok, workspace}
      _ -> {:error, :invalid_software_workspace}
    end
  end

  defp fixtures(opts) do
    root = Keyword.get(opts, :root, File.cwd!())

    if Enum.all?(
         [@lock, @audit_lock, @peer, @sources, @native_sources],
         &File.regular?(Path.join(root, &1))
       ),
       do: {:ok, root},
       else: {:error, :software_fixtures_unavailable}
  end

  defp tools(opts) do
    names = %{python: "python3", cmake: "cmake", ctest: "ctest", mix: "mix", curl: "curl"}
    explicit = Keyword.get(opts, :tools, %{})
    tools = Map.new(@tools, &{&1, Map.get(explicit, &1) || System.find_executable(names[&1])})

    case Enum.find(@tools, &(not is_binary(tools[&1]) or not File.regular?(tools[&1]))) do
      nil -> {:ok, tools}
      missing -> {:error, {:missing_software_tool, missing}}
    end
  end

  defp fresh(workspace) do
    case File.ls(workspace) do
      {:error, :enoent} -> :ok
      {:ok, []} -> :ok
      {:ok, _} -> {:error, :unrelated_software_workspace}
      {:error, reason} -> {:error, {:software_workspace, reason}}
    end
  end

  defp sanitizer(command, tools, root, workspace) do
    native = Path.join(workspace, "native")
    build = Path.join(workspace, "asan")

    configure = [
      "-S",
      Path.join(root, "priv/native"),
      "-B",
      build,
      "-DCMAKE_BUILD_TYPE=Debug",
      "-DWOTEX_SANITIZERS=ON",
      "-DWOTEX_SDK_PREFIX=" <> Path.join(native, "sdk-prefix"),
      "-DWOTEX_OPENSSL_PREFIX=" <> Path.join(native, "openssl-prefix")
    ]

    steps = [
      {"sanitizer_configure", configure},
      {"sanitizer_compile", ["--build", build, "--parallel", "4"]}
    ]

    run_steps(command, tools.cmake, steps, root, workspace)
  end

  defp environment(command, tools, root, workspace, name, lock) do
    venv = Path.join(workspace, "#{name}/venv")
    python = Path.join(venv, "bin/python")

    steps = [
      {tools.python, "#{name}_venv", ["-m", "venv", venv]},
      {python, "#{name}_install",
       ["-m", "pip", "install", "--require-hashes", "--no-deps", "-r", Path.join(root, lock)]},
      {python, "#{name}_freeze", ["-m", "pip", "freeze", "--all"]}
    ]

    result =
      Enum.reduce_while(steps, :ok, fn {executable, step, arguments}, :ok ->
        log = Path.join(workspace, "logs/#{step}.log")

        case command.(executable, arguments, [cd: root, env: []], log) do
          0 -> {:cont, :ok}
          status -> {:halt, {:error, {:software_step_failed, step, status}}}
        end
      end)

    with :ok <- result do
      freeze =
        workspace
        |> Path.join("logs/#{name}_freeze.log")
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.sort()

      {:ok, freeze}
    end
  end

  # One OSV batch query for the pinned SDK, cryptographic library and vendored
  # parser commits; the lane fails on a transport error, a malformed answer or
  # any advisory, and its report records every audited input.
  defp native_audit(command, tools, root, workspace) do
    log = Path.join(workspace, "logs/native_audit.log")
    query = Path.join(workspace, "logs/native_audit_query.json")
    response = Path.join(workspace, "logs/native_audit_response.json")

    status =
      with {:ok, bytes} <- File.read(Path.join(root, @native_sources)),
           true <- digest(bytes) == Source.manifest_digest(),
           {:ok, %{"sources" => sources, "vendored_sources" => vendored} = manifest} <-
             Jason.decode(bytes) do
        audited = sources ++ vendored
        queries = Enum.map(audited, &%{"commit" => &1["commit"]})
        File.write!(query, Jason.encode_to_iodata!(%{"queries" => queries}))

        arguments = [
          "--fail",
          "--silent",
          "--show-error",
          "--max-time",
          "60",
          "--proto",
          "=https",
          "--tlsv1.2",
          "--header",
          "Content-Type: application/json",
          "--data-binary",
          "@" <> query,
          "--output",
          response,
          @osv
        ]

        case command.(tools.curl, arguments, [cd: root, env: []], log) do
          0 -> audit_response(response, audited, manifest, workspace, log)
          failed -> failed
        end
      else
        _ ->
          File.write!(log, "native source manifest does not match the built pins\n")
          1
      end

    {:ok, log_digest} = Workspace.digest(log)
    %{"exit_status" => status, "log_sha256" => log_digest}
  end

  defp audit_response(response, audited, manifest, workspace, log) do
    with {:ok, bytes} <- File.read(response),
         {:ok, %{"results" => results}} when length(results) == length(audited) <-
           Jason.decode(bytes),
         {:ok, advisories} <- advisories(results) do
      entries =
        audited
        |> Enum.zip(advisories)
        |> Enum.map(fn {source, ids} ->
          source
          |> Map.take(~w(name version commit sha256))
          |> Map.put("advisories", ids)
        end)

      vulnerable = Enum.any?(advisories, &(&1 != []))

      report = %{
        "format_version" => 1,
        "service" => @osv,
        "source_manifest_sha256" => Source.manifest_digest(),
        "sources" => entries,
        "sdk_patches" => Enum.map(manifest["sdk_patches"], &Map.take(&1, ~w(id path sha256))),
        "status" => if(vulnerable, do: "vulnerable", else: "clean")
      }

      File.write!(Path.join(workspace, @audit_report), Jason.encode_to_iodata!(report))

      File.write!(
        log,
        Enum.map(entries, fn entry ->
          Enum.join(
            [
              "#{entry["name"]} #{entry["version"]} #{entry["commit"]}:",
              "#{length(entry["advisories"])} advisories" | entry["advisories"]
            ],
            " "
          ) <> "\n"
        end),
        [:append]
      )

      if vulnerable, do: 1, else: 0
    else
      _ ->
        File.write!(log, "malformed OSV response\n", [:append])
        1
    end
  end

  defp advisories(results) do
    case Enum.reduce_while(results, {:ok, []}, &advisory/2) do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      :error -> :error
    end
  end

  defp advisory(%{"vulns" => vulns}, {:ok, acc}) when is_list(vulns) do
    ids = for %{"id" => id} when is_binary(id) <- vulns, do: id

    if length(ids) == length(vulns),
      do: {:cont, {:ok, [Enum.sort(ids) | acc]}},
      else: {:halt, :error}
  end

  defp advisory(result, {:ok, acc}) when result == %{}, do: {:cont, {:ok, [[] | acc]}}
  defp advisory(_, _), do: {:halt, :error}

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp run_steps(command, executable, steps, root, workspace) do
    Enum.reduce_while(steps, :ok, fn {name, arguments}, :ok ->
      log = Path.join(workspace, "logs/#{name}.log")

      case command.(executable, arguments, [cd: root, env: []], log) do
        0 -> {:cont, :ok}
        status -> {:halt, {:error, {:software_step_failed, name, status}}}
      end
    end)
  end

  defp artifacts(workspace) do
    Enum.reduce_while(@executables, {:ok, %{}}, fn {name, path}, {:ok, artifacts} ->
      case Workspace.digest(Path.join(workspace, path)) do
        {:ok, digest} -> {:cont, {:ok, Map.put(artifacts, name, digest)}}
        _ -> {:halt, {:error, {:missing_software_artifact, name}}}
      end
    end)
  end

  defp verified(workspace, root) do
    with {:ok, bytes} <- File.read(Path.join(workspace, @manifest)),
         {:ok,
          %{
            "format_version" => 1,
            "lock_sha256" => lock,
            "audit_lock_sha256" => audit_lock,
            "artifacts" => recorded
          } = manifest} <- Jason.decode(bytes),
         {:ok, ^lock} <- Workspace.digest(Path.join(root, @lock)),
         {:ok, ^audit_lock} <- Workspace.digest(Path.join(root, @audit_lock)),
         {:ok, ^recorded} <- artifacts(workspace) do
      {:ok, manifest}
    else
      _ -> {:error, :stale_software_build}
    end
  end

  defp start_peer(workspace, root, directory, opts) do
    python = Path.join(workspace, "peer/venv/bin/python")
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :peer_deadline_ms, 30_000)

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [Path.join(root, @peer), directory]},
        {:cd, root}
      ])

    case await_peer(port, deadline) do
      :ok ->
        {:ok, port}

      {:error, _} = error ->
        stop_peer(port)
        error
    end
  end

  defp await_peer(port, deadline) do
    receive do
      {^port, {:data, {:eol, "secure peer ready"}}} -> :ok
      {^port, {:data, _}} -> await_peer(port, deadline)
      {^port, {:exit_status, status}} -> {:error, {:software_peer_exited, status}}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :software_peer_not_ready}
    end
  end

  defp stop_peer(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        Port.close(port)

        System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)],
          stderr_to_stdout: true,
          env: [{"LC_ALL", "C"}]
        )

      nil ->
        :ok
    end

    :ok
  end

  defp command(executable, arguments, options, log) do
    File.mkdir_p!(Path.dirname(log))

    {_, status} =
      System.cmd(
        executable,
        arguments,
        options ++ [stderr_to_stdout: true, into: File.stream!(log)]
      )

    status
  end
end
