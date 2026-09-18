defmodule Wotex.CoAP.Software.Run do
  @moduledoc """
  Verifies a completed software workspace and runs the owned interop suite.

  The tagged ExUnit files own their peers, ports and credential workspaces. UDP
  and DTLS peers are independent stacks; the libcoap OSCORE peer shares the
  pinned libcoap stack with the manifest-bound native helper, so its cases are
  same-stack evidence. The independent OSCORE file instead drives the pinned
  Eclipse Californium plugtest server, whose CoAP engine, OSCORE implementation
  and observation model are upstream of this repository, so its cases are
  cross-stack evidence. The lifecycle stress file repeats those transports
  under the WCO-C09 load, lifecycle and forced-failure matrix. The native corpus
  file drives native-v1 cases through the manifest-bound helper, and the
  saturation file samples a suspended native owner's Port mailbox. This runner
  invokes them through the native command guardian with one five-minute suite
  deadline and a 16 MiB combined log bound.
  It always writes a bounded `result.json` after command execution.
  """

  alias Wotex.CoAP.Native.{Build, BuildOperations, Workspace}
  alias Wotex.CoAP.Software.Build, as: SoftwareBuild

  @project_root Path.expand("../../../..", __DIR__)
  @cases ~w(test/interop/libcoap_test.exs test/interop/dtls_test.exs
    test/interop/dtls_pki_test.exs test/interop/oscore_test.exs
    test/software/independent_oscore_test.exs test/software/lifecycle_stress_test.exs
    test/software/native_corpus_test.exs test/software/native_saturation_test.exs)
  @arguments ["test" | @cases] ++
               ~w(--include interop --include software --exclude hardware --seed 0)
  @scenario_ids ~w(WCO-C03 WCO-C05 WCO-C07 WCO-C09 WCO-I02 WCO-I03 WCO-I04 WCO-I05 WCO-N03 WCO-N04
    WCO-S01 WCO-S02 WCO-S03 WCO-S05 WCO-S06 WCO-V02 WCO-V04 WCO-V05 WCO-V09 WCO-V12 WCO-V13
    WCO-V15)
  @source_files [
                  __ENV__.file,
                  Path.join(@project_root, "lib/mix/tasks/wotex.coap.software.run.ex"),
                  Path.join(@project_root, "mix.exs"),
                  Path.join(@project_root, "mix.lock"),
                  Path.join(@project_root, "test/test_helper.exs"),
                  Path.join(@project_root, "priv/fixtures/native-v1.json")
                ] ++
                  Enum.map(@cases, &Path.join(@project_root, &1)) ++
                  Path.wildcard(Path.join(@project_root, "test/support/*.ex")) ++
                  Path.wildcard(Path.join(@project_root, "test/fixtures/dtls_pki/*"))
  @maximum_result 1_048_576
  @timeout 300_000
  @output_limit 16_777_216

  for file <- @source_files, File.regular?(file), do: @external_resource(file)

  @type result :: %{evidence: map(), path: String.t()}

  @doc "Runs the explicit software suite against an existing verified workspace."
  @spec run(term()) :: {:ok, result()} | {:error, term()}
  def run(workspace), do: run(workspace, SoftwareBuild, BuildOperations)

  @doc false
  @spec run(term(), module(), module()) :: {:ok, result()} | {:error, term()}
  def run(workspace, verifier, operations)
      when is_binary(workspace) and is_atom(verifier) and is_atom(operations) do
    with {:ok, ^workspace} <- Build.arguments(["--workspace", workspace]),
         {:ok, %{manifest: manifest, reused: true}} <- verifier.verify(workspace),
         :ok <- validate_manifest(manifest),
         {:ok, tools} <- tools(),
         {:ok, output} <- output_directory(workspace),
         evidence <- execute(workspace, output, manifest, tools, operations),
         {:ok, path} <- write_result(output, evidence) do
      if evidence["status"] == "passed",
        do: {:ok, %{evidence: evidence, path: path}},
        else: {:error, {:software_suite_failed, path, evidence["failure"]}}
    end
  rescue
    error in [ArgumentError, File.Error, UndefinedFunctionError] ->
      {:error, {:software_run_setup, Exception.message(error)}}
  end

  def run(_, _, _), do: {:error, :invalid_software_run_workspace}

  # The package archive check requires every one of these files, because a
  # software run from an unpacked archive executes and hashes them.
  @doc false
  @spec source_files() :: [String.t()]
  def source_files, do: Enum.map(@source_files, &Path.relative_to(&1, @project_root))

  defp validate_manifest(%{
         "schema" => "wotex.coap.native@1",
         "software_build" => %{
           "profile" => "software",
           "peer" => %{"features" => %{"dtls" => true, "oscore" => true, "version" => true}},
           "independent_peer" => %{
             "path" => "bin/cf-plugtest-server.jar",
             "sha256" => independent_hash,
             "runtime" => %{"path" => runtime}
           }
         },
         "executables" => %{
           "coap-server" => %{"sha256" => peer_hash},
           "wotex-coap-oscore" => %{"sha256" => native_hash}
         },
         "workspace" => %{"artifacts" => artifacts}
       })
       when is_map(artifacts) do
    if digest?(peer_hash) and digest?(native_hash) and digest?(independent_hash) and
         is_binary(runtime) and Path.type(runtime) == :absolute,
       do: :ok,
       else: {:error, :invalid_software_manifest}
  end

  defp validate_manifest(_), do: {:error, :invalid_software_manifest}

  defp tools do
    with mix when is_binary(mix) <- System.find_executable("mix"),
         elixir when is_binary(elixir) <- System.find_executable("elixir"),
         erl when is_binary(erl) <- System.find_executable("erl"),
         tools = %{mix: mix, elixir: elixir, erl: erl},
         {:ok, toolchain} <- toolchain(tools) do
      {:ok, Map.put(tools, :toolchain, toolchain)}
    else
      _ -> {:error, :software_toolchain_unavailable}
    end
  end

  defp output_directory(workspace) do
    path = Path.join(workspace, "software-run")

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, :eexist} -> {:error, :software_result_exists}
      _ -> {:error, :software_result_unavailable}
    end
  end

  defp execute(workspace, output, manifest, tools, operations) do
    started = System.monotonic_time(:millisecond)
    guardian = Path.join(workspace, "native/bin/build-command")
    {:ok, source_hash} = source_hash(@source_files)

    {:ok, fixture_hash} =
      Workspace.digest(Path.join(@project_root, "test/fixtures/dtls_pki/manifest.json"))

    {:ok, lock_hash} = Workspace.digest(Path.join(@project_root, "mix.lock"))

    command =
      operations.command(guardian, tools.mix, @arguments, @project_root,
        timeout: @timeout,
        output: @output_limit,
        cleanup: 5_000,
        env: environment(tools, workspace, manifest)
      )

    {status, failure, details} = command_result(command)
    log = Path.join(output, "tests.log")
    :ok = File.write(log, details.output, [:exclusive, :sync])
    {:ok, log_hash} = Workspace.digest(log)

    %{
      "schema" => "wotex.coap.software@1",
      "status" => status,
      "failure" => failure,
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "source_sha256" => source_hash,
      "dependency_hashes" => %{"mix.lock" => lock_hash},
      "fixture_hashes" => %{"dtls_pki_manifest" => fixture_hash},
      "native_hashes" => %{
        "coap-server" => manifest["executables"]["coap-server"]["sha256"],
        "wotex-coap-oscore" => manifest["executables"]["wotex-coap-oscore"]["sha256"]
      },
      "independent_peer" => manifest["software_build"]["independent_peer"],
      "native_features" => manifest["software_build"]["peer"]["features"],
      "command" => ["mix" | @arguments],
      "seed" => 0,
      "scenario_ids" => @scenario_ids,
      "exit_status" => details.exit_status,
      "test_log" => %{
        "path" => "tests.log",
        "bytes" => byte_size(details.output),
        "sha256" => log_hash
      },
      "toolchain" => tools.toolchain,
      "cleanup" => %{
        "command_process_groups_retained" => 0,
        "peer_processes_retained" => if(status == "passed", do: 0, else: nil),
        "udp_ports_retained" => if(status == "passed", do: 0, else: nil),
        "session_context_subscription_store_locks_retained" =>
          if(status == "passed", do: 0, else: nil),
        "assertion_source" => "interop peer owners plus build-command process-group cleanup"
      }
    }
  end

  defp command_result({:ok, details}), do: {"passed", nil, details}

  defp command_result({:error, code, details}),
    do: {"failed", Atom.to_string(code), details}

  @doc false
  @spec source_hash([Path.t()]) :: {:ok, String.t()} | {:error, :software_source_unavailable}
  def source_hash(files) when is_list(files) do
    result =
      files
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce_while({:ok, :crypto.hash_init(:sha256)}, fn path, {:ok, hash} ->
        case File.read(path) do
          {:ok, bytes} ->
            relative = Path.relative_to(path, @project_root)
            {:cont, {:ok, :crypto.hash_update(hash, [relative, <<0>>, bytes, <<0>>])}}

          _ ->
            {:halt, {:error, :software_source_unavailable}}
        end
      end)

    case result do
      {:ok, hash} -> {:ok, Base.encode16(:crypto.hash_final(hash), case: :lower)}
      error -> error
    end
  end

  defp toolchain(tools) do
    case System.cmd(tools.elixir, ["--version"],
           stderr_to_stdout: true,
           env: system_environment(tools)
         ) do
      {output, 0} -> {:ok, output}
      _ -> {:error, :software_toolchain_unavailable}
    end
  end

  defp environment(tools, workspace, manifest) do
    path =
      [tools.mix, tools.elixir, tools.erl]
      |> Enum.map(&Path.dirname/1)
      |> Kernel.++(["/usr/bin", "/bin"])
      |> Enum.uniq()
      |> Enum.join(":")

    safe = %{
      "HOME" => System.user_home!(),
      "LC_ALL" => "C",
      "MIX_ENV" => "test",
      "PATH" => path,
      "WOTEX_COAP_INDEPENDENT_PEER" => Path.join(workspace, "bin/cf-plugtest-server.jar"),
      "WOTEX_COAP_JAVA" => manifest["software_build"]["independent_peer"]["runtime"]["path"],
      "WOTEX_COAP_LIBCOAP_SERVER" => Path.join(workspace, "bin/coap-server"),
      "WOTEX_COAP_NATIVE_MANIFEST" => Path.join(workspace, "native/native-manifest.json"),
      "WOTEX_COAP_NATIVE_WORKER" => Path.join(workspace, "native/bin/wotex-coap-oscore")
    }

    safe =
      case System.get_env("WOTEX_PATH_DEPS") do
        nil -> safe
        value -> Map.put(safe, "WOTEX_PATH_DEPS", value)
      end

    command_environment()
    |> Map.new()
    |> Map.merge(safe)
    |> Enum.sort()
  end

  defp command_environment, do: Enum.map(System.get_env(), fn {name, _} -> {name, false} end)

  defp system_environment(tools) do
    command_environment()
    |> Map.new(fn {name, false} -> {name, nil} end)
    |> Map.merge(%{
      "HOME" => System.user_home!(),
      "LC_ALL" => "C",
      "PATH" =>
        [Path.dirname(tools.elixir), Path.dirname(tools.erl), "/usr/bin", "/bin"]
        |> Enum.uniq()
        |> Enum.join(":")
    })
    |> Enum.sort()
  end

  defp write_result(output, evidence) do
    with {:ok, bytes} <- Jason.encode(evidence, pretty: true),
         true <- byte_size(bytes) <= @maximum_result,
         path = Path.join(output, "result.json"),
         :ok <- File.write(path, bytes <> "\n", [:exclusive, :sync]) do
      {:ok, path}
    else
      _ -> {:error, :software_result_unavailable}
    end
  end

  defp digest?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp digest?(_), do: false
end
