defmodule Wotex.OPCUA.Native.Software do
  @moduledoc """
  Builds and runs the explicit software acceptance lanes from a source checkout.

  `build/2` requires the checkout's peer lock, peer script and native sources.
  It builds the pinned native workspace under `WORKSPACE/native`, which runs the
  native CTest step, and a separate ASan/UBSan tree under `WORKSPACE/asan` from
  that workspace's SDK and OpenSSL prefixes. It then creates a peer virtual
  environment under `WORKSPACE/peer/venv` with
  `pip install --require-hashes --no-deps` from `test/interop/requirements.lock`.
  It records the lock digest, installed distributions and every executable
  digest in `WORKSPACE/software-build.json`. A non-empty directory without that
  manifest is rejected.

  `run/2` verifies the manifest against the current lock and executables. It
  starts the independent peer with a finite readiness deadline, then runs the
  interop and software ExUnit lanes with `WOTEX_REQUIRE_SOFTWARE=1`, native and
  sanitizer CTest, and `mix deps.audit` and `mix hex.audit`. It stops the peer
  it started and writes `WORKSPACE/software-run.json` with each lane's exit
  status and log digest. Any failed lane makes the run fail. The peer
  environment is test infrastructure; no Python process is part of the runtime
  package. Loading this module performs no I/O.
  """

  alias Wotex.OPCUA.Native.{Build, Workspace}

  @manifest "software-build.json"
  @report "software-run.json"
  @lock "test/interop/requirements.lock"
  @peer "test/interop/secure_peer.py"
  @sources "priv/native/CMakeLists.txt"
  @tools [:python, :cmake, :ctest, :mix]
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
  `python`, `cmake`, `ctest` and `mix` paths), `:native_build` (a one-argument
  native build function) and `:command` (a runner receiving executable,
  arguments, options and a log path and returning an exit status).
  """
  @spec build(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(workspace, opts \\ []) do
    with {:ok, workspace} <- workspace(workspace),
         {:ok, root} <- fixtures(opts),
         {:ok, tools} <- tools(opts),
         :ok <- fresh(workspace) do
      for directory <- ~w(native asan peer logs), do: File.mkdir_p!(Path.join(workspace, directory))
      command = Keyword.get(opts, :command, &command/4)
      native = Path.join(workspace, "native")

      with {:ok, _} <- Keyword.get(opts, :native_build, &Build.run/1).(native),
           :ok <- sanitizer(command, tools, root, workspace),
           {:ok, freeze} <- peer(command, tools, root, workspace),
           {:ok, artifacts} <- artifacts(workspace),
           {:ok, lock} <- Workspace.digest(Path.join(root, @lock)) do
        manifest = %{
          "format_version" => 1,
          "lock_sha256" => lock,
          "peer_distributions" => freeze,
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
      {"hex_audit", tools.mix, ["hex.audit"], root, []}
    ]

    results =
      Map.new(lanes, fn {name, executable, arguments, directory, lane_env} ->
        log = Path.join(workspace, "logs/#{name}.log")
        status = command.(executable, arguments, [cd: directory, env: lane_env], log)
        {:ok, digest} = Workspace.digest(log)
        {name, %{"exit_status" => status, "log_sha256" => digest}}
      end)

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

    if Enum.all?([@lock, @peer, @sources], &File.regular?(Path.join(root, &1))),
      do: {:ok, root},
      else: {:error, :software_fixtures_unavailable}
  end

  defp tools(opts) do
    names = %{python: "python3", cmake: "cmake", ctest: "ctest", mix: "mix"}
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

  defp peer(command, tools, root, workspace) do
    venv = Path.join(workspace, "peer/venv")
    python = Path.join(venv, "bin/python")

    steps = [
      {tools.python, "peer_venv", ["-m", "venv", venv]},
      {python, "peer_install",
       ["-m", "pip", "install", "--require-hashes", "--no-deps", "-r", Path.join(root, @lock)]},
      {python, "peer_freeze", ["-m", "pip", "freeze", "--all"]}
    ]

    result =
      Enum.reduce_while(steps, :ok, fn {executable, name, arguments}, :ok ->
        log = Path.join(workspace, "logs/#{name}.log")

        case command.(executable, arguments, [cd: root, env: []], log) do
          0 -> {:cont, :ok}
          status -> {:halt, {:error, {:software_step_failed, name, status}}}
        end
      end)

    with :ok <- result do
      freeze =
        workspace
        |> Path.join("logs/peer_freeze.log")
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.sort()

      {:ok, freeze}
    end
  end

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
         {:ok, %{"format_version" => 1, "lock_sha256" => lock, "artifacts" => recorded} = manifest} <-
           Jason.decode(bytes),
         {:ok, ^lock} <- Workspace.digest(Path.join(root, @lock)),
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
